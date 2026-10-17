import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/song_model.dart';
import 'audio_player_service.dart' show RepeatBehaviour;

/// What the player was doing when the app was last used, in a form that can be
/// written to disk and read back on the next launch.
///
/// The queue is stored as the songs themselves, not only as ids. Ids alone are
/// enough to rebuild a queue, but only *after* the media store has been read --
/// and that is a scan of the whole device, which leaves the player sitting on
/// "Nothing playing" for the first seconds of every launch. With the songs, the
/// last session is on screen in the first moments after launch and the scan only
/// matters for the rest of the library.
class PlaybackSnapshot {
  /// The queue, in order, as song ids.
  final List<String> songIds;

  /// The same queue as whole songs, so it can be rebuilt without a media scan.
  ///
  /// Empty for a snapshot written by an older build, which held ids only: those
  /// are still restored, by matching the ids against a fresh scan.
  final List<WavelySong> songs;

  /// Which entry of [songIds] was current.
  final int index;

  /// How far into the current track playback had got.
  final Duration position;

  /// Whether the music was actually playing, as opposed to paused.
  ///
  /// Restoring a paused player silently would look like the app had forgotten
  /// what it was doing; restoring a playing one makes reopening the app pick up
  /// exactly where it left off.
  final bool wasPlaying;

  final bool shuffle;
  final RepeatBehaviour repeatMode;
  final double volume;

  /// Where the queue came from, so the home screen can show the same heading.
  final String? queueTitle;

  final DateTime savedAt;

  const PlaybackSnapshot({
    required this.songIds,
    required this.index,
    required this.position,
    required this.wasPlaying,
    required this.shuffle,
    required this.repeatMode,
    required this.volume,
    required this.savedAt,
    this.songs = const [],
    this.queueTitle,
  });

  /// A snapshot of a live queue.
  ///
  /// [songIds] is derived from [songs] rather than passed alongside it, so the
  /// two can never disagree about what the queue was.
  factory PlaybackSnapshot.of({
    required List<WavelySong> songs,
    required int index,
    required Duration position,
    required bool wasPlaying,
    required bool shuffle,
    required RepeatBehaviour repeatMode,
    required double volume,
    required DateTime savedAt,
    String? queueTitle,
  }) => PlaybackSnapshot(
    songIds: [for (final song in songs) song.id],
    songs: List<WavelySong>.unmodifiable(songs),
    index: index,
    position: position,
    wasPlaying: wasPlaying,
    shuffle: shuffle,
    repeatMode: repeatMode,
    volume: volume,
    savedAt: savedAt,
    queueTitle: queueTitle,
  );

  /// Schema version, so a later format change can be told apart from garbage.
  ///
  /// 2 added the songs themselves. A version 1 file still reads: it carries ids,
  /// which is what the older restore path matches against a fresh scan.
  static const int currentVersion = 2;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    // Written only when there are no whole songs to write: an id list next to
    // the songs would be a second copy of the same queue, thousands of ids long.
    if (songs.isEmpty) 'songIds': songIds,
    if (songs.isNotEmpty)
      'songs': [for (final song in songs) _songToJson(song)],
    'index': index,
    'positionMs': position.inMilliseconds,
    'wasPlaying': wasPlaying,
    'shuffle': shuffle,
    'repeat': repeatMode.name,
    'volume': volume,
    'queueTitle': queueTitle,
    'savedAtMs': savedAt.millisecondsSinceEpoch,
  };

  /// The same snapshot with a different playhead and play/pause state.
  ///
  /// Used by the store, which keeps the queue and the position in two files: the
  /// queue is rewritten only when it changes, and the position -- which moves
  /// every few seconds -- is overlaid back onto the queue when the pair is read.
  PlaybackSnapshot withProgress({
    required int index,
    required Duration position,
    required bool wasPlaying,
    required DateTime savedAt,
  }) => PlaybackSnapshot(
    songIds: songIds,
    songs: songs,
    index: index,
    position: position,
    wasPlaying: wasPlaying,
    shuffle: shuffle,
    repeatMode: repeatMode,
    volume: volume,
    savedAt: savedAt,
    queueTitle: queueTitle,
  );

  /// Rebuild a snapshot from stored JSON, or null when it is not one.
  ///
  /// Everything is validated rather than cast: the file survives app upgrades,
  /// and a player that throws on startup because of a stale field would be a far
  /// worse outcome than starting with an empty queue.
  static PlaybackSnapshot? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    // The songs are preferred, and stand in for the ids entirely: they are the
    // same queue, with enough on each entry to build the player's sources.
    final songs = _songsFrom(decoded['songs']);
    final songIds = songs.isNotEmpty
        ? [for (final song in songs) song.id]
        : _idsFrom(decoded['songIds']);
    if (songIds.isEmpty) return null;

    final index = decoded['index'];
    final positionMs = decoded['positionMs'];
    final savedAtMs = decoded['savedAtMs'];
    if (index is! int || positionMs is! int || savedAtMs is! int) return null;

    final volume = decoded['volume'];
    final repeat = decoded['repeat'];
    final title = decoded['queueTitle'];

    return PlaybackSnapshot(
      songIds: songIds,
      songs: songs,
      index: index,
      position: Duration(milliseconds: positionMs),
      wasPlaying: decoded['wasPlaying'] == true,
      shuffle: decoded['shuffle'] == true,
      // An unrecognised name falls back to the safe default rather than
      // throwing: the queue is worth restoring even if a mode was lost.
      repeatMode: RepeatBehaviour.values.firstWhere(
        (mode) => mode.name == repeat,
        orElse: () => RepeatBehaviour.off,
      ),
      volume: volume is num ? volume.toDouble().clamp(0.0, 1.0) : 0.8,
      queueTitle: title is String && title.isNotEmpty ? title : null,
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
    );
  }

  @override
  String toString() =>
      'PlaybackSnapshot(${songIds.length} songs, index $index, '
      '${position.inSeconds}s, playing: $wasPlaying)';
}

/// The stored form of one queued track.
///
/// Everything the player needs to open the file and everything the UI draws,
/// including the album id the artwork is keyed on and the file size the listening
/// room matches two devices' copies of a song by. Decoded image bytes are left
/// out deliberately: they are large, and they are rederived on demand.
Map<String, Object?> _songToJson(WavelySong song) => {
  'id': song.id,
  'title': song.title,
  'artist': song.artist,
  'album': song.album,
  'durationMs': song.duration.inMilliseconds,
  'uri': song.uri,
  if (song.contentUri != null) 'contentUri': song.contentUri,
  if (song.albumArtUri != null) 'albumArtUri': song.albumArtUri,
  if (song.albumId != null) 'albumId': song.albumId,
  if (song.genre != null) 'genre': song.genre,
  if (song.trackNumber != null) 'trackNumber': song.trackNumber,
  if (song.isFavorite) 'isFavorite': true,
  if (song.fileSize != null) 'fileSize': song.fileSize,
};

/// Read one stored track back, or null when it is not one.
///
/// A track with no id or no uri is dropped: there would be nothing to play and
/// nothing to name it by. Every other field falls back, because a queue that is
/// missing a title is still a queue worth restoring.
WavelySong? _songFromJson(Object? raw) {
  if (raw is! Map) return null;

  final id = raw['id'];
  final uri = raw['uri'];
  if (id is! String || id.isEmpty || uri is! String) return null;

  return WavelySong(
    id: id,
    title: _string(raw['title']) ?? 'Unknown track',
    artist: _string(raw['artist']) ?? '',
    album: _string(raw['album']) ?? '',
    duration: Duration(milliseconds: _int(raw['durationMs']) ?? 0),
    uri: uri,
    contentUri: _string(raw['contentUri']),
    albumArtUri: _string(raw['albumArtUri']),
    albumId: _int(raw['albumId']),
    genre: _string(raw['genre']),
    trackNumber: _int(raw['trackNumber']),
    isFavorite: raw['isFavorite'] == true,
    fileSize: _int(raw['fileSize']),
  );
}

List<WavelySong> _songsFrom(Object? raw) {
  if (raw is! List) return const [];
  final songs = <WavelySong>[];
  for (final entry in raw) {
    final song = _songFromJson(entry);
    if (song != null) songs.add(song);
  }
  return songs;
}

List<String> _idsFrom(Object? raw) {
  if (raw is! List || raw.isEmpty) return const [];
  if (raw.any((id) => id is! String)) return const [];
  return List.of(raw.cast<String>());
}

String? _string(Object? raw) => raw is String && raw.isNotEmpty ? raw : null;

int? _int(Object? raw) => raw is int ? raw : null;

/// Where the last session's playback is kept between launches.
///
/// An interface so the player can be tested against an in-memory store, and so
/// that failing to persist can never be confused with "nothing was playing".
abstract interface class PlaybackStateStore {
  /// The stored snapshot, or null when there is nothing usable to restore.
  Future<PlaybackSnapshot?> read();

  Future<void> write(PlaybackSnapshot snapshot);

  /// Forget the stored snapshot.
  Future<void> clear();
}

/// Keeps the snapshot in the app's private storage, in two files.
///
/// App support rather than documents: this is app state, not something the user
/// made or should find in a file browser. Writes go to a temporary file that is
/// then renamed over the target, so a write interrupted by the app being
/// backgrounded and killed cannot leave a half-written file that fails to parse
/// on the next launch.
///
/// Split in two because the two halves change at wildly different rates. The
/// queue is rewritten only when it actually changes; the playhead moves every
/// few seconds, and folding it into the same file would rewrite every queued
/// song -- tens of thousands of ids and their metadata -- several times a minute
/// for the rest of the session. The small file carries a fingerprint of the queue
/// it belongs to, so a playhead left over from a *different* queue is ignored
/// rather than used to drop the user into the wrong track.
class FilePlaybackStateStore implements PlaybackStateStore {
  static const String fileName = 'playback_state.json';
  static const String progressFileName = 'playback_progress.json';

  /// Resolves the directory the files live in.
  final Future<Directory> Function() _directory;

  /// Fingerprint of the queue last read or written by this process, or null
  /// until one of the two happens.
  ///
  /// Null on the first save of a launch, which therefore rewrites the queue once
  /// -- harmless, and it means a snapshot written by an older build is upgraded
  /// the moment anything is saved.
  int? _storedQueueToken;

  /// [directory] is injectable so tests can point the store at a temp directory
  /// instead of going through path_provider, which has no platform in tests.
  FilePlaybackStateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file(String name) async =>
      File('${(await _directory()).path}/$name');

  @override
  Future<PlaybackSnapshot?> read() async {
    try {
      final file = await _file(fileName);
      if (!await file.exists()) return null;

      final snapshot = PlaybackSnapshot.tryParse(await file.readAsString());
      if (snapshot == null) return null;
      final token = _queueToken(snapshot.songIds, snapshot.songs);
      _storedQueueToken = token;

      final progressFile = await _file(progressFileName);
      if (!await progressFile.exists()) return snapshot;

      final progress = _progressFrom(await progressFile.readAsString());
      if (progress == null || progress.$1 != token) return snapshot;

      return snapshot.withProgress(
        index: progress.$2,
        position: progress.$3,
        wasPlaying: progress.$4,
        savedAt: progress.$5,
      );
    } on Object {
      // Storage that cannot be read is not worth failing a launch over; the app
      // simply opens with an empty player.
      return null;
    }
  }

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    try {
      final token = _queueToken(snapshot.songIds, snapshot.songs);
      if (token != _storedQueueToken) {
        _storedQueueToken = token;
        await _writeAtomically(await _file(fileName), snapshot.toJson());
      }

      // Written every time, and small: one record, whatever the length of the
      // queue. Reading it back only needs the playhead, so the songs are left
      // out of it entirely.
      await _writeAtomically(await _file(progressFileName), {
        'token': token,
        'index': snapshot.index,
        'positionMs': snapshot.position.inMilliseconds,
        'wasPlaying': snapshot.wasPlaying,
        'savedAtMs': snapshot.savedAt.millisecondsSinceEpoch,
      });
    } on Object {
      // Losing a snapshot only costs the user their place in the queue. It must
      // never interrupt playback, so this is swallowed deliberately.
    }
  }

  @override
  Future<void> clear() async {
    try {
      for (final name in [fileName, progressFileName]) {
        final file = await _file(name);
        if (await file.exists()) await file.delete();
      }
      _storedQueueToken = null;
    } on Object {
      // As above: a stale snapshot that fails to delete is harmless, because it
      // is only ever read on the next launch.
    }
  }

  Future<void> _writeAtomically(File file, Object json) async {
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode(json), flush: true);
    await pending.rename(file.path);
  }

  /// The playhead a progress record stands for -- queue fingerprint, index,
  /// position, playing, saved at -- or null when it is not one.
  (int, int, Duration, bool, DateTime)? _progressFrom(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final token = decoded['token'];
    final index = decoded['index'];
    final positionMs = decoded['positionMs'];
    final savedAtMs = decoded['savedAtMs'];
    if (token is! int ||
        index is! int ||
        positionMs is! int ||
        savedAtMs is! int) {
      return null;
    }

    return (
      token,
      index,
      Duration(milliseconds: positionMs),
      decoded['wasPlaying'] == true,
      DateTime.fromMillisecondsSinceEpoch(savedAtMs),
    );
  }

  /// A cheap, stable fingerprint of a queue.
  ///
  /// FNV-1a rather than a hash of the list: Dart's own hash codes are not
  /// promised to be stable across runs, and this one has to survive being written
  /// to disk and compared against the next launch. Ids alone would do for
  /// identity, but the file each track points at is what the player opens, so a
  /// queue whose ids survived a move is not the same queue.
  static int _queueToken(List<String> songIds, List<WavelySong> songs) {
    var hash = 0x811c9dc5;

    void mix(String value) {
      for (var i = 0; i < value.length; i++) {
        hash = ((hash ^ value.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
      }
      // A separator no id or path can contain, so ["ab", "c"] and ["a", "bc"]
      // are not the same queue.
      hash = ((hash ^ 0x1f) * 0x01000193) & 0xffffffff;
    }

    if (songs.isEmpty) {
      for (final id in songIds) {
        mix(id);
      }
      return hash;
    }

    for (final song in songs) {
      mix(song.id);
      mix(song.uri);
    }
    return hash;
  }
}
