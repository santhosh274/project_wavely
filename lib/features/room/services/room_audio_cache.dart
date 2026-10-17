import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/models/song_model.dart';
import '../models/track_ref.dart';
import 'local_room_transport.dart' show LocalRoomRoutes;

/// Fetches tracks the host is willing to share, and remembers where they landed.
///
/// This is the escape hatch from the one hard rule of a listening room: every
/// device plays its own copy, so a guest that does not own the track is silent.
/// On a LAN the host can simply hand the file over -- a few seconds for a whole
/// album track over Wi-Fi -- and the guest plays that instead. It is the reason
/// the room is worth building peer-to-peer first: this costs nothing, needs no
/// third party, and does not exist at all if the guests are on a different
/// network.
///
/// Downloads are keyed by fingerprint, so a track is fetched once per session
/// however many times it comes back around the queue.
class RoomAudioCache {
  RoomAudioCache({Future<Directory> Function()? directory, HttpClient? client})
    : _directory = directory ?? _defaultDirectory,
      _client = client ?? HttpClient();

  /// Where downloads are written. App *temporary* storage: these are copies of a
  /// file the user already owns somewhere else, and the OS may reclaim them.
  final Future<Directory> Function() _directory;

  /// Injectable so a test can serve the bytes without a socket.
  final HttpClient _client;

  final Map<String, WavelySong> _byFingerprint = {};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}/wavely_room');

  /// A track already fetched this session, if any.
  WavelySong? cachedFor(String fingerprint) => _byFingerprint[fingerprint];

  /// Download [ref] from the host serving at [base], or null when it cannot be
  /// had.
  ///
  /// Null is an ordinary answer, not an error: the host may have moved on, the
  /// socket may have dropped, or the file may not be readable on the host's side.
  /// The caller shows "not in your library" either way, which is what the user
  /// can act on.
  Future<WavelySong?> fetch({
    required Uri base,
    required String roomCode,
    required TrackRef ref,
  }) async {
    final existing = _byFingerprint[ref.fingerprint];
    if (existing != null) return existing;

    try {
      final directory = await _directory();
      if (!await directory.exists()) await directory.create(recursive: true);

      final request = await _client.getUrl(
        base.replace(
          // The link the room handed over is a *socket* address, and the same
          // server answers plain HTTP on the same port. `HttpClient` speaks
          // http(s) and nothing else, so the scheme has to be translated here
          // rather than reused: a request to `ws://` throws before a byte
          // leaves the device.
          scheme: base.scheme == 'wss' ? 'https' : 'http',
          path: LocalRoomRoutes.audio,
          queryParameters: {'code': roomCode, 'id': ref.hostSongId},
        ),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      // The extension is not cosmetic. A player picks its extractor from the
      // container, and a local file with no extension makes ExoPlayer guess --
      // which for some codecs it guesses wrong, and the track opens as silence.
      final file = File(
        '${directory.path}/${_fileName(ref)}${_extensionFor(response.headers.contentType)}',
      );
      await response.pipe(file.openWrite());

      final song = WavelySong(
        // Namespaced: this is a copy, not the user's own library row, and giving
        // it the host's id would let it collide with a real song on this device.
        id: 'room:${ref.fingerprint}',
        title: ref.title,
        artist: ref.artist,
        album: ref.album,
        duration: ref.duration,
        uri: file.path,
        fileSize: ref.fileSize,
      );
      _byFingerprint[ref.fingerprint] = song;
      return song;
    } on Object {
      return null;
    }
  }

  /// Forget the downloads. Called when the room is left, so the next room does
  /// not inherit another host's files.
  Future<void> clear() async {
    _byFingerprint.clear();
    try {
      final directory = await _directory();
      if (await directory.exists()) await directory.delete(recursive: true);
    } on Object {
      // The OS may have reclaimed the directory already; either way there is
      // nothing left for this session to do with it.
    }
  }

  static String _fileName(TrackRef ref) {
    final safe = ref.fingerprint.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return safe.length <= 96 ? safe : safe.substring(0, 96);
  }

  static String _extensionFor(ContentType? contentType) => switch (contentType
      ?.mimeType) {
    'audio/mpeg' || 'audio/mp3' => '.mp3',
    'audio/flac' || 'audio/x-flac' => '.flac',
    'audio/mp4' || 'audio/aac' || 'audio/x-m4a' => '.m4a',
    'audio/ogg' => '.ogg',
    'audio/wav' || 'audio/x-wav' => '.wav',
    'audio/opus' => '.opus',
    // Container unknown: mp3 is the widest-supported guess, and the bytes are
    // named as they were served on the host's side.
    _ => '.mp3',
  };
}
