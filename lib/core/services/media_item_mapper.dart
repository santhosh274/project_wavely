import 'package:audio_service/audio_service.dart';

import '../models/song_model.dart';

/// The tag just_audio_background puts on every source.
///
/// Background playback runs the player through `audio_service`, which shows a
/// media notification and takes lock screen and headset button commands. It reads
/// the title, artist, album and cover for that notification from the tag, and
/// asserts that every source in the queue carries one -- so the queue cannot be
/// loaded with a bare string tag without taking playback down.
///
/// [id] is the same id the library uses, which is also what ties the notification
/// back to the track the app is showing.
MediaItem mediaItemFor(WavelySong song) {
  final artUri =
      song.albumArtUri == null ? null : Uri.tryParse(song.albumArtUri!);
  final extras = <String, dynamic>{
    if (song.albumId != null) 'albumId': song.albumId,
    // Opts the notification service into its fast `ContentResolver`
    // thumbnail path (API 29+, silent fallback below that) instead of the
    // generic file read. The value is the song's own content URI; its
    // presence is what enables the path.
    if (artUri?.scheme == 'content')
      'loadThumbnailUri': song.contentUri ?? artUri.toString(),
  };
  return MediaItem(
    id: song.id,
    title: song.title,
    artist: song.artist,
    album: song.album,
    duration: song.duration,
    // Best effort: a track with no embedded cover simply gets no artwork in the
    // notification. The in-app cover is resolved separately and more reliably.
    // Content URIs are loaded natively by the notification service -- they must
    // never go through the Dart HTTP preloader, which only speaks http(s).
    artUri: artUri,
    extras: extras.isEmpty ? null : extras,
  );
}

/// The song id carried by [tag], or null when it carries none.
///
/// Accepts a plain string as well as a [MediaItem] so a source loaded without
/// background playback still resolves; the audio service looks songs up by id
/// either way.
String? songIdOf(Object? tag) => switch (tag) {
  MediaItem(:final id) => id,
  String() => tag,
  _ => null,
};
