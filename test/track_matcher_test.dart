import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/room/models/track_ref.dart';
import 'package:wavely/features/room/services/track_fingerprint.dart';
import 'package:wavely/features/room/services/track_matcher.dart';

const _hostCopy = WavelySong(
  id: '10',
  title: 'Aurora Fields',
  artist: 'Real Artist',
  album: 'Real Album',
  duration: Duration(minutes: 3, seconds: 20),
  uri: '/host/aurora.mp3',
  fileSize: 4200,
);

/// The same recording, as it landed on the guest's device: another row id, a
/// re-tagged title ("feat." vs "Feat"), and a byte count one tag block
/// different.
const _guestCopy = WavelySong(
  id: '99',
  title: 'Aurora Fields (Feat. Nova)',
  artist: 'Real Artist',
  album: 'Real Album',
  duration: Duration(minutes: 3, seconds: 20),
  uri: '/guest/aurora.mp3',
  fileSize: 4321,
);

void main() {
  group('track fingerprint', () {
    test('the same file on two devices fingerprints identically', () {
      expect(
        trackFingerprint(_hostCopy),
        trackFingerprint(
          _hostCopy.copyWith(id: 'different', uri: '/elsewhere/aurora.mp3'),
        ),
      );
    });

    test('a different byte count is a different key, but not a different song', () {
      expect(trackFingerprint(_hostCopy), isNot(trackFingerprint(_guestCopy)));
      expect(looseFingerprint(_hostCopy), isNot(equals(looseFingerprint(_guestCopy))));
    });

    test('punctuation and case are not what separates two rips', () {
      final punctuated = _hostCopy.copyWith(
        title: "Aurora  FIELDS!",
        artist: 'real artist',
      );
      expect(trackFingerprint(punctuated), trackFingerprint(_hostCopy));
    });

    test('a duration within the same second reads as one song', () {
      final trimmed = _hostCopy.copyWith(
        duration: const Duration(milliseconds: 200400),
      );
      expect(looseFingerprint(trimmed), looseFingerprint(_hostCopy));
    });

    test('a device that reported no size still produces a key', () {
      // A media store that did not report a byte count must not leave the room
      // unable to match a track at all, so the size slot is filled with a
      // marker rather than dropped from the key.
      const unsized = WavelySong(
        id: '10',
        title: 'Aurora Fields',
        artist: 'Real Artist',
        album: 'Real Album',
        duration: Duration(minutes: 3, seconds: 20),
        uri: '/host/aurora.mp3',
      );

      expect(trackFingerprint(unsized), contains('|-'),
          reason: 'the missing size takes a slot of its own');
      expect(
        looseFingerprint(unsized),
        looseFingerprintOf(
          title: 'Aurora Fields',
          artist: 'Real Artist',
          durationMs: 200000,
        ),
      );
      expect(trackFingerprint(unsized), isNot(trackFingerprint(_hostCopy)));
    });
  });

  group('track matcher', () {
    test('finds the identical file', () {
      final match = TrackMatcher([_guestCopy, _hostCopy]).match(
        TrackRef.of(_hostCopy),
      );
      expect(match?.id, '10');
    });

    test('falls back to metadata when the byte count differs', () {
      // "Feat." is not the same punctuation as the host's plain title, and the
      // size differs, so this is exactly the case the loose pass exists for.
      final renamed = _guestCopy.copyWith(title: 'Aurora Fields');
      final match = TrackMatcher([renamed]).match(TrackRef.of(_hostCopy));
      expect(match?.id, '99');
    });

    test('prefers the exact file over a loose match', () {
      final renamed = _guestCopy.copyWith(title: 'Aurora Fields');
      final match = TrackMatcher([renamed, _hostCopy]).match(
        TrackRef.of(_hostCopy),
      );
      expect(match?.id, '10');
    });

    test('a song the guest does not have matches nothing', () {
      const other = WavelySong(
        id: '50',
        title: 'Neon Tide',
        artist: 'Another Artist',
        album: 'Real Album',
        duration: Duration(minutes: 4, seconds: 5),
        uri: '/guest/neon.mp3',
      );
      expect(TrackMatcher([other]).match(TrackRef.of(_hostCopy)), isNull);
    });

    test('a different duration is a different recording, not a match', () {
      final slowed = _guestCopy.copyWith(
        title: 'Aurora Fields',
        duration: const Duration(minutes: 5),
      );
      expect(TrackMatcher([slowed]).match(TrackRef.of(_hostCopy)), isNull);
    });

    test('a queue keeps the host\'s order and drops what is missing', () {
      const neon = WavelySong(
        id: '11',
        title: 'Neon Tide',
        artist: 'Another Artist',
        album: 'Real Album',
        duration: Duration(minutes: 4, seconds: 5),
        uri: '/guest/neon.mp3',
      );
      final renamed = _guestCopy.copyWith(title: 'Aurora Fields');

      final resolved = TrackMatcher([neon, renamed]).matchQueue([
        TrackRef.of(_hostCopy),
        TrackRef.of(neon.copyWith(title: 'Not Here')),
        TrackRef.of(neon),
      ]);

      expect(resolved.map((s) => s.id), ['99', '11']);
    });

    test('a queue that repeats a track resolves it once', () {
      final renamed = _guestCopy.copyWith(title: 'Aurora Fields');
      final resolved = TrackMatcher([renamed]).matchQueue([
        TrackRef.of(_hostCopy),
        TrackRef.of(_hostCopy),
      ]);

      // Two entries of the same file in a just_audio queue is a source list the
      // player cannot walk, so the duplicate is dropped rather than kept.
      expect(resolved.length, 1);
    });

    test('an empty library resolves nothing, quietly', () {
      expect(const TrackMatcher([]).match(TrackRef.of(_hostCopy)), isNull);
      expect(const TrackMatcher([]).matchQueue([TrackRef.of(_hostCopy)]), isEmpty);
    });
  });
}
