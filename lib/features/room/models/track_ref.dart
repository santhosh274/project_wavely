import '../../../core/models/song_model.dart';
import '../services/track_fingerprint.dart';

/// A track as the room describes it.
///
/// It carries two different things on purpose. The [fingerprint] is what lets a
/// guest find the same recording in its own library; the displayed fields are
/// what let it say *what* is playing when it cannot find one, instead of showing
/// a blank player. [hostSongId] is the host's own key for the track and is how a
/// guest asks for the file when it does not have it.
class TrackRef {
  final String fingerprint;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int? fileSize;
  final String hostSongId;

  const TrackRef({
    required this.fingerprint,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.hostSongId,
    this.fileSize,
  });

  factory TrackRef.of(WavelySong song) => TrackRef(
    fingerprint: trackFingerprint(song),
    title: song.title,
    artist: song.artist,
    album: song.album,
    durationMs: song.duration.inMilliseconds,
    fileSize: song.fileSize,
    hostSongId: song.id,
  );

  Map<String, Object?> toJson() => {
    'fingerprint': fingerprint,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
    'fileSize': fileSize,
    'hostSongId': hostSongId,
  };

  /// Rebuild a reference from decoded JSON, or null when it is not one.
  ///
  /// Everything is validated rather than cast: the frames arrive from another
  /// device over a socket, and a peer running an older or newer build must be
  /// rejected field by field instead of taking the app down.
  static TrackRef? tryParse(Object? json) {
    if (json is! Map) return null;

    final fingerprint = json['fingerprint'];
    final title = json['title'];
    final hostSongId = json['hostSongId'];
    if (fingerprint is! String || title is! String) return null;
    if (hostSongId is! String || fingerprint.isEmpty) return null;

    final artist = json['artist'];
    final album = json['album'];
    final durationMs = json['durationMs'];
    final fileSize = json['fileSize'];

    return TrackRef(
      fingerprint: fingerprint,
      title: title,
      artist: artist is String ? artist : '',
      album: album is String ? album : '',
      durationMs: durationMs is int ? durationMs : 0,
      fileSize: fileSize is int ? fileSize : null,
      hostSongId: hostSongId,
    );
  }

  Duration get duration => Duration(milliseconds: durationMs);

  @override
  String toString() => 'TrackRef($title — $artist)';
}
