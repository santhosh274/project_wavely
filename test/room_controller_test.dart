import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/room/models/room_message.dart';
import 'package:wavely/features/room/services/local_room_transport.dart'
    show LocalRoomRoutes;
import 'package:wavely/features/room/services/room_audio_cache.dart';
import 'package:wavely/features/room/services/track_fingerprint.dart';

import 'support/fake_local_network_permission.dart';
import 'support/fake_room_device.dart';
import 'support/fake_room_transport.dart';

void main() {
  const aurora = roomTestAurora;
  const neon = roomTestNeon;
  late FakeRoomTransportFactory factory;

  setUp(() => factory = FakeRoomTransportFactory());

  /// A host, and a guest that has joined it.
  Future<(RoomTestDevice, RoomTestDevice)> roomOfTwo({
    List<WavelySong>? guestLibrary,
    RoomAudioCache? cache,
    Duration beatInterval = const Duration(milliseconds: 50),
  }) async {
    final host = RoomTestDevice(factory: factory, displayName: 'Kaushik');
    addTearDown(host.dispose);
    await host.room.startRoom();

    final guest = RoomTestDevice(
      factory: factory,
      library: guestLibrary,
      cache: cache,
      displayName: 'Priya',
      beatInterval: beatInterval,
    );
    addTearDown(guest.dispose);
    await guest.room.joinRoom(factory.hostUri.toString());
    await pumpEventQueue();

    return (host, guest);
  }

  /// Pin the room's expected playhead for the next two seconds.
  ///
  /// A scheduled start names a moment a quarter of a second out, so the expected
  /// position is only settled for a quarter of a second after one. A sync frame
  /// with a host stamp two seconds ahead holds it still for long enough to
  /// measure a correction without racing the clock.
  Future<void> pinExpectedAt(int positionMs, FakeRoomTransport host) async {
    host.send(
      SyncMessage(
        positionMs: positionMs,
        hostAtMs: DateTime.now().millisecondsSinceEpoch + 2000,
        playing: true,
      ),
    );
    await pumpEventQueue();
  }

  /// Move the guest's playhead to [deltaMs] away from where the room expects it,
  /// the way a stall or a slow device running out of buffer would.
  ///
  /// Moved through the player rather than the engine, so the controller's own
  /// idea of the playhead moves with it -- which is the state a correction
  /// measures.
  Future<void> placeGuestPlayhead(RoomTestDevice guest, int deltaMs) async {
    final target = Duration(
      milliseconds: guest.room.expectedPositionMs + deltaMs,
    );
    await guest.player.applyRemote(() => guest.player.seek(target));
    await pumpEventQueue();
  }

  group('hosting', () {
    test('starting a room publishes a code and a link', () async {
      final host = RoomTestDevice(factory: factory, displayName: 'Kaushik');
      addTearDown(host.dispose);
      expect(host.room.isActive, isFalse);

      await host.room.startRoom();

      expect(host.room.isHost, isTrue);
      expect(host.room.roomCode, 'TEST01');
      expect(host.room.joinUri.toString(), contains('code=TEST01'));
      expect(host.room.members.single.name, 'Kaushik');
      expect(host.room.members.single.isHost, isTrue);
      // Nothing to report: the room is simply up.
      expect(host.room.statusMessage, isNull);
    });

    test('closing the room stops answering to it', () async {
      final host = RoomTestDevice(factory: factory);
      addTearDown(host.dispose);
      await host.room.startRoom();

      await host.room.leave();

      expect(host.room.isActive, isFalse);
      expect(host.room.members, isEmpty);
      expect(host.room.joinUri, isNull);
    });

    test('a room that cannot bind reports it instead of pretending', () async {
      factory.failWith = StateError('no socket for you');
      final host = RoomTestDevice(factory: factory);
      addTearDown(host.dispose);

      await host.room.startRoom();

      expect(host.room.isActive, isFalse);
      expect(host.room.statusMessage, contains('Could not open a room'));
    });

    test('opening a room asks for local-network access exactly once', () async {
      final permission = FakeLocalNetworkPermission();
      final host = RoomTestDevice(factory: factory, localNetwork: permission);
      addTearDown(host.dispose);

      await host.room.startRoom();

      expect(permission.requests, 1);
      expect(host.room.isActive, isTrue);
    });

    test('a refused local-network permission is explained before a bind', () async {
      // Android 17 refuses a room's sockets without this permission, so the
      // refusal is caught before a socket is even tried -- and said in a
      // sentence the user can act on rather than a socket error they cannot.
      final permission = FakeLocalNetworkPermission(granted: false);
      final host = RoomTestDevice(factory: factory, localNetwork: permission);
      addTearDown(host.dispose);

      await host.room.startRoom();

      expect(permission.requests, 1);
      expect(factory.hosts, isEmpty);
      expect(host.room.isActive, isFalse);
      expect(host.room.statusMessage, contains('local network access'));
    });
  });

  group('joining', () {
    test('a guest is named in the member list, both ways', () async {
      final (host, guest) = await roomOfTwo();

      expect(host.room.members.length, 2);
      expect(host.room.members.first.isHost, isTrue);
      expect(host.room.members.last.name, 'Priya');
      expect(guest.room.members.first.name, 'Kaushik');
      expect(guest.room.hostName, 'Kaushik');
    });

    test('an address and a code typed by hand are completed into a link', (
      ) async {
      final host = RoomTestDevice(factory: factory, displayName: 'Kaushik');
      addTearDown(host.dispose);
      await host.room.startRoom();

      final guest = RoomTestDevice(factory: factory, displayName: 'Priya');
      addTearDown(guest.dispose);
      // The host's own screen, read out loud: an address with no scheme and no
      // path, and a code typed in whatever case the keyboard offered.
      await guest.room.joinRoom('127.0.0.1:5445', code: 'test01');

      expect(guest.room.isGuest, isTrue);
      final dialled = factory.joinedUris.single;
      // Completed to the route the host answers on. Dialled exactly as typed,
      // this asked for `/` and the host turned it away.
      expect(dialled.path, LocalRoomRoutes.socket);
      expect(dialled.queryParameters['code'], 'TEST01');
    });

    test('an address without its code is turned down locally', () async {
      final guest = RoomTestDevice(factory: factory);
      addTearDown(guest.dispose);

      await guest.room.joinRoom('127.0.0.1:5445');

      // Said here rather than discovered on the host's doorstep: the address
      // alone is not answerable.
      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('room code'));
      expect(factory.joinedUris, isEmpty);
    });

    test('a pasted link keeps its own code beside a typed one', () async {
      final host = RoomTestDevice(factory: factory, displayName: 'Kaushik');
      addTearDown(host.dispose);
      await host.room.startRoom();

      final guest = RoomTestDevice(factory: factory, displayName: 'Priya');
      addTearDown(guest.dispose);
      // Whatever is still in the code field is left over from the last room, so
      // the link the guest pasted wins.
      await guest.room.joinRoom(factory.hostUri.toString(), code: 'WRONG1');

      expect(guest.room.isGuest, isTrue);
      expect(factory.joinedUris.single.queryParameters['code'], 'TEST01');
    });

    test('a guest that is not given a room link is not put in one', () async {
      final guest = RoomTestDevice(factory: factory);
      addTearDown(guest.dispose);

      await guest.room.joinRoom('https://example.com/not-a-room');
      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('room link'));

      await guest.room.joinRoom('   ');
      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('room link'));

      // Nothing was dialled, so nothing was left half-open either.
      expect(factory.joinedUris, isEmpty);
    });

    test('a guest refused local-network access is told before dialling', () async {
      final host = RoomTestDevice(factory: factory);
      addTearDown(host.dispose);
      await host.room.startRoom();

      final permission = FakeLocalNetworkPermission(granted: false);
      final guest = RoomTestDevice(factory: factory, localNetwork: permission);
      addTearDown(guest.dispose);

      await guest.room.joinRoom(factory.hostUri.toString());

      expect(permission.requests, 1);
      expect(factory.joinedUris, isEmpty);
      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('local network access'));
    });

    test('a join that fails leaves the player alone', () async {
      factory.failWith = StateError('unreachable');
      final guest = RoomTestDevice(factory: factory);
      addTearDown(guest.dispose);

      await guest.room.joinRoom(factory.hostUri.toString());

      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('Could not join'));
      expect(guest.player.intentInterceptor, isNull);
    });

    test('the guest measures the host clock as soon as it is in', () async {
      final (_, guest) = await roomOfTwo();
      await pumpEventQueue();

      // The exchange is a round trip, so the number only exists once the host
      // has answered -- which is itself the proof that it did.
      expect(guest.room.roundTripMs, isNotNull);
      expect(guest.room.roundTripMs, lessThan(200));
    });
  });

  group('following the host', () {
    test('a track the host plays is played on the guest, at the same place',
        () async {
      final (host, guest) = await roomOfTwo();

      await host.player.playTrack(aurora, queueContext: const [aurora, neon]);
      await pumpEventQueue();

      expect(guest.player.currentSong?.id, '10');
      expect(guest.player.isPlaying, isTrue);
      // The whole queue comes across, resolved against the guest's own library,
      // so next and previous have something truthful to do.
      expect(guest.engine.queue.map((song) => song.id), ['10', '11']);
      expect(guest.player.position.inMilliseconds, lessThan(400));
      expect(guest.engine.seekCalls, isNotEmpty);
    });

    test('a pause travels and the guest stops where the host did', () async {
      final (host, guest) = await roomOfTwo();
      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();
      expect(guest.player.isPlaying, isTrue);

      await host.player.togglePlayPause();
      await pumpEventQueue();

      expect(host.player.isPlaying, isFalse);
      expect(guest.player.isPlaying, isFalse);
    });

    test('a seek travels to the same position', () async {
      final (host, guest) = await roomOfTwo();
      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();

      await host.player.seek(const Duration(seconds: 30));
      await pumpEventQueue();

      expect(guest.player.position.inMilliseconds, closeTo(30000, 400));
    });

    test('the guest\'s own controls cannot fight the host', () async {
      final (host, guest) = await roomOfTwo();
      await host.player.playTrack(
        aurora,
        queueContext: const [aurora, neon],
      );
      await pumpEventQueue();

      // As if the guest tapped next: consumed by the room, because the host is
      // the single writer and a local change would be undone a moment later.
      await guest.player.skipNext();
      await pumpEventQueue();
      expect(guest.player.currentSong?.id, '10');
      expect(guest.room.controlsLocked, isTrue);

      // The room itself still gets through the interceptor it installed.
      await guest.player.applyRemote(guest.player.skipNext);
      await pumpEventQueue();
      expect(guest.player.currentSong?.id, '11');
    });

    test('leaving hands the controls back', () async {
      final (host, guest) = await roomOfTwo();
      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();
      expect(guest.player.intentInterceptor, isNotNull);

      await guest.room.leave();

      expect(guest.room.isActive, isFalse);
      expect(guest.player.intentInterceptor, isNull);
      // Left at 0.97 by a correction, the next track the user starts themselves
      // would run slow.
      expect(guest.engine.speed, 1.0);
    });

    test('the host leaving ends the guest\'s room', () async {
      final (host, guest) = await roomOfTwo();

      await host.room.leave();
      await pumpEventQueue();

      expect(guest.room.isActive, isFalse);
      expect(guest.room.statusMessage, contains('host left'));
      expect(guest.player.intentInterceptor, isNull);
    });

    test('a guest joining mid-song is told where the song is', () async {
      final host = RoomTestDevice(factory: factory, displayName: 'Kaushik');
      addTearDown(host.dispose);
      await host.room.startRoom();
      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();

      final late_ = RoomTestDevice(factory: factory, displayName: 'Late');
      addTearDown(late_.dispose);
      await late_.room.joinRoom(factory.hostUri.toString());
      await pumpEventQueue();

      expect(late_.player.currentSong?.id, '10');
      expect(host.room.members.length, 2);
    });

    test('a track the guest does not have is reported, not silently skipped',
        () async {
      final (host, guest) = await roomOfTwo(
        guestLibrary: const [],
        cache: FakeRoomAudioCache(),
      );

      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();

      expect(host.room.guestsMissingTrack, isTrue);
      expect(
        host.room.members.where((member) => !member.isHost).single
            .missingCurrentTrack,
        isTrue,
      );
      expect(guest.room.statusMessage, contains('not in your library'));
      expect(guest.player.currentSong, isNull);
    });

    test('a track the guest does not have is fetched from the host', () async {
      final downloaded = aurora.copyWith(
        id: 'room:aurora',
        uri: '/tmp/wavely_room/aurora.mp3',
      );
      final cache = FakeRoomAudioCache(downloaded);
      final (host, guest) = await roomOfTwo(
        guestLibrary: const [],
        cache: cache,
      );

      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();

      expect(cache.fetchedFingerprints, [trackFingerprint(aurora)]);
      expect(cache.lastRoomCode, 'TEST01');
      expect(guest.player.currentSong?.id, 'room:aurora');
      expect(host.room.guestsMissingTrack, isFalse);
    });

    test('a guest lands on the host track deep in a long queue', () async {
      // The queue is far longer than the window of it the room sends with a
      // start, and the track being played sits beyond that window. The guest
      // must still resolve the track rather than play whatever the window's
      // first entry happened to match.
      final songs = [
        for (var i = 1; i <= 120; i++)
          WavelySong(
            id: '$i',
            title: 'Track $i',
            artist: 'Artist',
            album: 'Album',
            duration: const Duration(minutes: 3),
            uri: '/audio/$i.mp3',
            fileSize: 1000 + i,
          ),
      ];

      final host = RoomTestDevice(
        factory: factory,
        library: songs,
        displayName: 'Kaushik',
      );
      addTearDown(host.dispose);
      await host.room.startRoom();

      final guest = RoomTestDevice(
        factory: factory,
        library: songs,
        displayName: 'Priya',
        beatInterval: const Duration(minutes: 1),
      );
      addTearDown(guest.dispose);
      await guest.room.joinRoom(factory.hostUri.toString());
      await pumpEventQueue();

      final deep = songs[90];
      await host.player.playTrack(deep, queueContext: songs);
      await pumpEventQueue();

      expect(guest.player.currentSong?.id, deep.id);
    });
  });

  group('drift correction', () {
    test('a guest a little off is nudged by rate, not by seeking', () async {
      final (_, guest) = await roomOfTwo(beatInterval: const Duration(minutes: 1));
      await pinExpectedAt(4000, factory.lastHost!);
      await placeGuestPlayhead(guest, 50);
      final seeksSoFar = guest.engine.seekCalls.length;

      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Ahead of the room, so slowed: 50ms of drift is worth 2.5%, which the
      // correction spends over the next couple of seconds.
      expect(guest.engine.speed, closeTo(1 - 50 / 2000, 0.0001));
      expect(guest.engine.seekCalls, hasLength(seeksSoFar));
      expect(guest.room.lastDriftMs, isNotNull);
    });

    test('the nudge is clamped to what stays inaudible', () async {
      final (_, guest) = await roomOfTwo(beatInterval: const Duration(minutes: 1));
      await pinExpectedAt(4000, factory.lastHost!);

      // 150ms would ask for a 7.5% slowdown, which is audible as a waver. It is
      // spent at the 3% limit instead, over a longer stretch.
      await placeGuestPlayhead(guest, 150);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.engine.speed, 0.97);

      // And a guest that is behind is sped up, not slowed down.
      await placeGuestPlayhead(guest, -150);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.engine.speed, 1.03);
    });

    test('a guest that has really fallen behind is seeked back', () async {
      final (_, guest) = await roomOfTwo(beatInterval: const Duration(minutes: 1));
      await pinExpectedAt(4000, factory.lastHost!);
      await placeGuestPlayhead(guest, 900);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(guest.engine.seekCalls.last.inMilliseconds, closeTo(4000, 60));
      expect(guest.engine.speed, 1.0);
    });

    test('a guest a few milliseconds off is left alone', () async {
      final (_, guest) = await roomOfTwo(beatInterval: const Duration(minutes: 1));
      // A correction already applied, so "back to normal" is a change worth
      // asserting rather than the state it was already in.
      await pinExpectedAt(4000, factory.lastHost!);
      await placeGuestPlayhead(guest, 150);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guest.engine.speed, lessThan(1.0));

      await placeGuestPlayhead(guest, 5);
      final seeksSoFar = guest.engine.seekCalls.length;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(guest.engine.speed, 1.0);
      expect(guest.engine.seekCalls, hasLength(seeksSoFar));
    });

    test('a paused room is not corrected', () async {
      final (host, guest) = await roomOfTwo(
        beatInterval: const Duration(minutes: 1),
      );
      await host.player.playTrack(aurora, queueContext: const [aurora]);
      await pumpEventQueue();
      await host.player.togglePlayPause();
      await pumpEventQueue();
      expect(guest.player.isPlaying, isFalse);

      final seeksSoFar = guest.engine.seekCalls.length;
      final speedBefore = guest.engine.speed;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Nothing to correct toward while nothing is playing, and a correction
      // here would move a playhead the user is looking at.
      expect(guest.engine.seekCalls, hasLength(seeksSoFar));
      expect(guest.engine.speed, speedBefore);
    });
  });
}
