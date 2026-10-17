import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/room/models/room_message.dart';
import 'package:wavely/features/room/models/track_ref.dart';
import 'package:wavely/features/room/services/local_room_transport.dart';
import 'package:wavely/features/room/services/room_audio_cache.dart';
import 'package:wavely/features/room/services/room_transport.dart';

void main() {
  // Loopback rather than the device's LAN address: the addresses a phone holds
  // are not reachable from a test process, and everything interesting about the
  // transport -- the handshake, the code check, the audio route, what happens
  // when a peer goes -- is identical on either.
  late LocalRoomTransportFactory factory;

  setUp(() => factory = LocalRoomTransportFactory(advertisedHost: '127.0.0.1'));

  /// Open a host and dial it, closing both however the test ends.
  ///
  /// The host is built from a factory of its own so a test can give it a file
  /// source; the guest always dials through [factory], which is what the
  /// multi-guest tests use to add a second one.
  Future<(RoomTransport, RoomTransport)> openRoom({
    RoomFileSource? fileSource,
  }) async {
    final host = await LocalRoomTransportFactory(
      advertisedHost: '127.0.0.1',
      fileSource: fileSource,
    ).host();
    addTearDown(host.close);

    final guest = await factory.join(host.joinUri!);
    addTearDown(guest.close);

    // The host announces its guests, so let that arrive before the test body
    // starts asserting on it.
    await pumpEventQueue();
    return (host, guest);
  }

  test('the host advertises an address a guest can dial', () async {
    final host = await LocalRoomTransportFactory(advertisedHost: '127.0.0.1')
        .host();
    addTearDown(host.close);

    final uri = host.joinUri!;
    expect(uri.scheme, 'ws');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, greaterThan(0));
    expect(uri.path, LocalRoomRoutes.socket);
    expect(uri.queryParameters['code'], host.roomCode);
    expect(host.roomCode.length, LocalRoomRoutes.codeLength);
    expect(host.selfId, 'host');
  });

  test('a guest that dials with the code is let in and named', () async {
    final (host, guest) = await openRoom();

    final hello = Completer<RoomEnvelope>();
    host.incoming.listen((envelope) {
      if (envelope.message is HelloMessage && !hello.isCompleted) {
        hello.complete(envelope);
      }
    });

    guest.send(const HelloMessage(name: 'Kaushik', isHost: false));

    final envelope = await hello.future;
    // Named by the host, not by itself: the id has to be unique inside the room
    // and only the host can guarantee that.
    expect(envelope.from, startsWith('g'));
    expect((envelope.message as HelloMessage).name, 'Kaushik');
  });

  test('a second guest dialling is announced to the host', () async {
    final (host, _) = await openRoom();

    final joined = <String>[];
    host.peerJoined.listen(joined.add);

    final second = await factory.join(host.joinUri!);
    addTearDown(second.close);
    await pumpEventQueue();

    expect(joined, hasLength(1));
  });

  test('a room that is full turns the next guest away', () async {
    // One guest is the whole room here, so the refusal can be reached without
    // five more phones.
    final host = await LocalRoomTransportFactory(
      advertisedHost: '127.0.0.1',
      maxGuests: 1,
    ).host();
    addTearDown(host.close);

    final first = await factory.join(host.joinUri!);
    addTearDown(first.close);

    // Refused by the handshake, with a status the room can give a sentence to:
    // "full" and "that link is broken" are different things to a user.
    await expectLater(
      factory.join(host.joinUri!),
      throwsA(
        isA<WebSocketException>().having(
          (error) => error.httpStatusCode,
          'httpStatusCode',
          HttpStatus.serviceUnavailable,
        ),
      ),
    );
  });

  test('a room code that is wrong is turned away', () async {
    final host = await LocalRoomTransportFactory(advertisedHost: '127.0.0.1')
        .host();
    addTearDown(host.close);

    await expectLater(
      factory.join(host.joinUri!.replace(queryParameters: {'code': 'WRONG1'})),
      throwsA(isA<Exception>()),
    );
  });

  test('a broadcast reaches the guest, stamped from the host', () async {
    final (host, guest) = await openRoom();

    final received = Completer<RoomEnvelope>();
    guest.incoming.listen((envelope) {
      if (!received.isCompleted) received.complete(envelope);
    });

    host.send(
      const TransportMessage(
        action: TransportAction.pause,
        positionMs: 4000,
        hostAtMs: 123456,
      ),
    );

    final envelope = await received.future;
    // Everything a guest receives is from the host: the topology is a star.
    expect(envelope.from, 'host');
    final message = envelope.message;
    expect(message, isA<TransportMessage>());
    expect((message as TransportMessage).positionMs, 4000);
    expect(message.hostAtMs, 123456);
  });

  test('a frame addressed to one guest does not reach the other', () async {
    final (host, first) = await openRoom();

    final joined = <String>[];
    host.peerJoined.listen(joined.add);
    final second = await factory.join(host.joinUri!);
    addTearDown(second.close);
    await pumpEventQueue();

    final toFirst = <RoomMessage>[];
    final toSecond = <RoomMessage>[];
    first.incoming.listen((envelope) => toFirst.add(envelope.message));
    second.incoming.listen((envelope) => toSecond.add(envelope.message));

    host.send(const NoticeMessage('only for you'), to: joined.single);
    await pumpEventQueue();

    expect(toSecond.whereType<NoticeMessage>().single.text, 'only for you');
    expect(toFirst.whereType<NoticeMessage>(), isEmpty);
  });

  test('garbage on the socket does not tear the room down', () async {
    final (host, _) = await openRoom();

    final received = <RoomMessage>[];
    host.incoming.listen((envelope) => received.add(envelope.message));

    // A raw socket, so the bytes are written without going through the encoder,
    // the way a peer on a different build would send them.
    final raw = await WebSocket.connect(host.joinUri.toString());
    addTearDown(raw.close);
    raw.add('not a frame at all');
    raw.add('{"v":99,"type":"holo-deck"}');
    raw.add('{"v":1,"type":"notice","text":"still here"}');
    await pumpEventQueue();

    expect(received.whereType<NoticeMessage>().single.text, 'still here');
  });

  test('the host serves a track it owns to a guest that asks', () async {
    final bytes = List<int>.generate(64 * 1024, (i) => i % 251);
    final requested = <String>[];

    final host = await LocalRoomTransportFactory(
      advertisedHost: '127.0.0.1',
      fileSource: (songId) async {
        requested.add(songId);
        if (songId != '10') return null;
        return RoomSharedFile(
          bytes: Stream.value(bytes),
          length: bytes.length,
          contentType: 'audio/mpeg',
        );
      },
    ).host();
    addTearDown(host.close);

    final directory = await Directory.systemTemp.createTemp('wavely-room-test');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final cache = RoomAudioCache(directory: () async => directory);
    const ref = TrackRef(
      fingerprint: 'aurora fields|real artist|real album|200|65536',
      title: 'Aurora Fields',
      artist: 'Real Artist',
      album: 'Real Album',
      durationMs: 200000,
      fileSize: 65536,
      hostSongId: '10',
    );

    final song = await cache.fetch(
      base: host.joinUri!,
      roomCode: host.roomCode,
      ref: ref,
    );

    expect(requested, ['10']);
    expect(song, isNotNull);
    // The metadata comes from the room's own description of the track: the guest
    // is playing a file the host was already playing, not a file it found.
    expect(song!.title, 'Aurora Fields');
    expect(song.duration, const Duration(milliseconds: 200000));
    // The extension is load-bearing: it is how the player picks a container.
    expect(song.uri, endsWith('.mp3'));
    expect(await File(song.uri).readAsBytes(), bytes);

    // And it is remembered, so a track that comes round the queue again is not
    // fetched a second time.
    expect(cache.cachedFor(ref.fingerprint)?.uri, song.uri);
    expect(await cache.fetch(
      base: host.joinUri!,
      roomCode: host.roomCode,
      ref: ref,
    ), isNotNull);
    expect(requested, hasLength(1));
  });

  test('a track the host cannot serve answers 404 rather than throwing', () async {
    final host = await LocalRoomTransportFactory(
      advertisedHost: '127.0.0.1',
      fileSource: (_) async => null,
    ).host();
    addTearDown(host.close);

    final directory = await Directory.systemTemp.createTemp('wavely-room-test');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    final song = await RoomAudioCache(
      directory: () async => directory,
    ).fetch(
      base: host.joinUri!,
      roomCode: host.roomCode,
      ref: const TrackRef(
        fingerprint: 'k',
        title: 'Gone',
        artist: 'Nobody',
        album: '',
        durationMs: 1000,
        hostSongId: '404',
      ),
    );

    expect(song, isNull);
  });

  test('an audio request without the room code is refused', () async {
    final bytes = List<int>.filled(8, 7);
    final host = await LocalRoomTransportFactory(
      advertisedHost: '127.0.0.1',
      fileSource: (_) async => RoomSharedFile(
        bytes: Stream.value(bytes),
        length: bytes.length,
        contentType: 'audio/mpeg',
      ),
    ).host();
    addTearDown(host.close);

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      host.joinUri!.replace(
        // The room link is a socket address; the audio route is plain HTTP on
        // the same port.
        scheme: 'http',
        path: LocalRoomRoutes.audio,
        queryParameters: {'code': 'NOPE12', 'id': '10'},
      ),
    );
    final response = await request.close();

    expect(response.statusCode, HttpStatus.forbidden);
    await response.drain<void>();
  });

  test('the room closes when the host goes', () async {
    final (host, guest) = await openRoom();

    final gone = Completer<String>();
    guest.peerLeft.listen((peerId) {
      if (!gone.isCompleted) gone.complete(peerId);
    });

    await host.close();

    expect(await gone.future, 'host');
  });

  test('a guest dropping is reported to the host', () async {
    final (host, guest) = await openRoom();

    final left = Completer<String>();
    host.peerLeft.listen((peerId) {
      if (!left.isCompleted) left.complete(peerId);
    });

    await guest.close();

    expect(await left.future, 'g1');
  });

  test('a device that refuses the wildcard bind still opens on loopback', () async {
    final tried = <InternetAddress>[];
    final host = await LocalRoomTransportFactory(
      binder: (address, port) async {
        tried.add(address);
        if (!address.isLoopback) {
          throw const SocketException('Failed to create server socket');
        }
        return HttpServer.bind(address, port);
      },
    ).host();
    addTearDown(host.close);

    // anyIPv4 and anyIPv6 were refused, loopback stood in -- and the link says
    // so, because a guest can only dial an address the server is listening on.
    expect(tried, [
      InternetAddress.anyIPv4,
      InternetAddress.anyIPv6,
      InternetAddress.loopbackIPv4,
    ]);
    expect(host.joinUri!.host, InternetAddress.loopbackIPv4.address);
    expect(host.joinUri!.port, greaterThan(0));
  });

  test('a device that refuses every bind reports a failure the user can act on',
      () async {
    final factory = LocalRoomTransportFactory(
      binder: (address, port) async =>
          throw const SocketException('Failed to create server socket'),
    );

    await expectLater(
      factory.host(),
      throwsA(
        isA<RoomHostUnavailableException>().having(
          (error) => error.toString(),
          'toString',
          contains('VPN or firewall'),
        ),
      ),
    );
  });
}
