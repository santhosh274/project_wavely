import '../../../core/models/song_model.dart';
import '../models/track_ref.dart';
import 'track_fingerprint.dart';

/// Finds the local recording behind a track the room is describing.
///
/// Two passes, in order of confidence:
///
///  1. The exact fingerprint, byte count included. This is the same file or a
///     byte-identical copy of it, so playing it is indistinguishable from
///     playing the host's.
///  2. Metadata alone -- title, artist and duration to the second. A track that
///     travelled between devices by a different route is often the same music
///     with a different container, and refusing to match it would leave a guest
///     silent for a song it plainly owns.
///
/// The library is passed in rather than held, because it changes on every scan
/// and the matcher is created per look-up.
class TrackMatcher {
  /// The songs to search. Passed as an [Iterable] so a caller can hand over a
  /// view (a queue, a filtered list) without copying it.
  final Iterable<WavelySong> library;

  const TrackMatcher(this.library);

  /// The local song for [ref], or null when this device does not have it.
  WavelySong? match(TrackRef ref) {
    WavelySong? loose;
    final wantedLoose = looseFingerprintOf(
      title: ref.title,
      artist: ref.artist,
      durationMs: ref.durationMs,
    );

    for (final song in library) {
      if (trackFingerprint(song) == ref.fingerprint) return song;
      // Kept rather than returned: the exact pass has to finish first, because a
      // metadata match can be a different rip of the same song.
      if (loose == null && looseFingerprint(song) == wantedLoose) loose = song;
    }

    return loose;
  }

  /// Resolve a whole queue, preserving order and dropping what is missing.
  ///
  /// The guest's queue is deliberately the resolvable subset of the host's: it
  /// exists so the next/previous controls and the queue list have something
  /// truthful to show. It is not what keeps the room in step -- that is the
  /// host's start frame, which arrives for every track regardless.
  List<WavelySong> matchQueue(Iterable<TrackRef> refs) {
    final resolved = <WavelySong>[];
    final seen = <String>{};
    for (final ref in refs) {
      final song = match(ref);
      // A queue can repeat a track; a song may only appear once, or
      // just_audio would resolve two sources to the same file.
      if (song == null || !seen.add(song.id)) continue;
      resolved.add(song);
    }
    return resolved;
  }
}
