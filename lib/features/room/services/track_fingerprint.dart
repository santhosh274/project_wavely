import '../../../core/models/song_model.dart';

/// A stable identity for a *recording*, not for a row in one device's library.
///
/// A listening room has to answer one question constantly: "do I have the track
/// the host is playing?" Song ids cannot answer it -- they are MediaStore row
/// ids, unique per device -- and metadata alone is not enough either, because
/// "Neon Tide" by Vela exists on every compilation and remaster. Byte count is
/// what separates the same file from a different rip of it, so it is part of the
/// key, and the metadata is only the fallback when a device did not report one.
///
/// The string is deliberately human-readable: it travels in the protocol and in
/// logs, and a key nobody can read is a key nobody can debug.
String trackFingerprint(WavelySong song) {
  return [
    _normalize(song.title),
    _normalize(song.artist),
    _normalize(song.album),
    // Bucketed to the second: the same encode reported by two platforms can
    // differ by a few milliseconds, and that must not read as a different song.
    '${(song.duration.inMilliseconds / 1000).round()}',
    song.fileSize?.toString() ?? '-',
  ].join('|');
}

/// The same identity with the byte count left out.
///
/// Used as a second pass when the exact key misses: a track copied between
/// devices can legitimately change size (a re-encode, a different tag block),
/// and refusing to match it would leave the guest silent for a song it does
/// have. Matching on metadata alone is looser, which is why it is the fallback
/// rather than the key.
String looseFingerprint(WavelySong song) => looseFingerprintOf(
  title: song.title,
  artist: song.artist,
  durationMs: song.duration.inMilliseconds,
);

/// The loose key built from raw fields, for a track a peer described but this
/// device has not been able to resolve to a song yet.
String looseFingerprintOf({
  required String title,
  required String artist,
  required int durationMs,
}) {
  return [
    _normalize(title),
    _normalize(artist),
    '${(durationMs / 1000).round()}',
  ].join('|');
}

/// Lower-cased, punctuation-stripped, single-spaced text.
///
/// Punctuation and case are the two things that differ most between how two
/// devices spell the same track ("Feat." vs "feat", "Aurora's" vs "Auroras"), and
/// collapsing them is safe in a way that dropping whole words would not be.
String _normalize(String value) {
  final cleaned = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}
