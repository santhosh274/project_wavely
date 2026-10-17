import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/room/models/room_message.dart';
import 'package:wavely/features/room/models/track_ref.dart';

const _ref = TrackRef(
  fingerprint: 'aurora fields|real artist|real album|200|4200',
  title: 'Aurora Fields',
  artist: 'Real Artist',
  album: 'Real Album',
  durationMs: 200000,
  fileSize: 4200,
  hostSongId: '10',
);

void main() {
  /// Encode, decode, and hand the frame back, the way the wire does it.
  RoomMessage? roundTrip(RoomMessage message) =>
      RoomMessage.tryParse(jsonEncode(message.toJson()));

  group('room protocol', () {
    test('a start round-trips through the wire with its queue', () {
      const message = StartMessage(
        track: _ref,
        positionMs: 12000,
        hostAtMs: 1750000000250,
        playing: true,
        queue: [_ref],
      );

      final decoded = roundTrip(message);

      expect(decoded, isA<StartMessage>());
      final start = decoded! as StartMessage;
      expect(start.track.fingerprint, _ref.fingerprint);
      expect(start.track.hostSongId, '10');
      expect(start.positionMs, 12000);
      expect(start.hostAtMs, 1750000000250);
      expect(start.playing, isTrue);
      expect(start.queue.single.title, 'Aurora Fields');
    });

    test('a start carrying a paused transport is not read as playing', () {
      const message = StartMessage(
        track: _ref,
        positionMs: 0,
        hostAtMs: 1,
        playing: false,
      );

      expect((roundTrip(message)! as StartMessage).playing, isFalse);
    });

    test('the clock exchange round-trips both hosts stamps', () {
      final request = roundTrip(
        const TimeRequestMessage(seq: 7, clientEpochMs: 1000),
      );
      final ping = request! as TimeRequestMessage;
      expect(ping.seq, 7);
      expect(ping.clientEpochMs, 1000);

      final reply = roundTrip(
        const TimeReplyMessage(
          seq: 7,
          clientEpochMs: 1000,
          hostEpochMs: 1400,
          hostReplyMs: 1405,
        ),
      );
      final pong = reply! as TimeReplyMessage;
      expect(pong.clientEpochMs, 1000);
      expect(pong.hostEpochMs, 1400);
      expect(pong.hostReplyMs, 1405);
    });

    test('transport frames carry their action and where the host jumped to', () {
      final decoded = roundTrip(
        const TransportMessage(
          action: TransportAction.seek,
          positionMs: 45000,
          hostAtMs: 2000,
        ),
      );
      final transport = decoded! as TransportMessage;
      expect(transport.action, TransportAction.seek);
      expect(transport.positionMs, 45000);
    });

    test('a sync frame round-trips', () {
      final decoded = roundTrip(
        const SyncMessage(positionMs: 900, hostAtMs: 5000, playing: true),
      );
      final sync = decoded! as SyncMessage;
      expect(sync.positionMs, 900);
      expect(sync.playing, isTrue);
    });

    test('hello, missing and notice round-trip', () {
      expect((roundTrip(const HelloMessage(name: 'Kaushik', isHost: true))!
                  as HelloMessage)
              .isHost,
          isTrue);
      expect(
        (roundTrip(
          const MissingTrackMessage(fingerprint: 'a|b|c', hostSongId: '10'),
        )! as MissingTrackMessage)
            .hostSongId,
        '10',
      );
      expect(
        (roundTrip(const NoticeMessage('Waiting for the host…'))!
                as NoticeMessage)
            .text,
        'Waiting for the host…',
      );
    });

    test('every frame carries the protocol version', () {
      final json = const NoticeMessage('hi').toJson();
      expect(json['v'], RoomMessage.protocolVersion);
      expect(json['type'], 'notice');
    });

    test('a frame from a newer peer is dropped rather than fatal', () {
      expect(
        RoomMessage.tryParse('{"v":99,"type":"holo-deck","deck":"A"}'),
        isNull,
      );
    });

    test('garbage on the socket is dropped rather than fatal', () {
      expect(RoomMessage.tryParse('not json at all'), isNull);
      expect(RoomMessage.tryParse('[]'), isNull);
      expect(RoomMessage.tryParse('"a string"'), isNull);
      expect(RoomMessage.tryParse('{"type":42}'), isNull);
    });

    test('a frame missing required fields is dropped', () {
      // A start with no track cannot be applied by any guest.
      expect(
        RoomMessage.tryParse('{"v":1,"type":"start","positionMs":0}'),
        isNull,
      );
      expect(RoomMessage.tryParse('{"v":1,"type":"ping","seq":1}'), isNull);
      expect(
        RoomMessage.tryParse('{"v":1,"type":"start","track":{"title":"x"}}'),
        isNull,
      );
    });

    test('a track reference with no usable key is rejected', () {
      expect(TrackRef.tryParse({'title': 'Aurora'}), isNull);
      expect(
        TrackRef.tryParse({
          'fingerprint': 'a|b',
          'title': 'Aurora',
          'hostSongId': '10',
          'durationMs': 'soon',
        })?.durationMs,
        0,
      );
    });

    test('an unrecognised transport action is rejected', () {
      expect(
        RoomMessage.tryParse(
          '{"v":1,"type":"transport","action":"rewind","hostAtMs":1}',
        ),
        isNull,
      );
    });
  });
}
