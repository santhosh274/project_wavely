import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'audio_player_service.dart' show RepeatBehaviour;

/// What the player was doing when the app was last used, in a form that can be
/// written to disk and read back on the next launch.
///
/// Only song ids are stored, never the songs themselves: ids are the library's
/// own key, so the queue can be rebuilt from a fresh media scan rather than from
/// a copy that would go stale as soon as a file is renamed or deleted.
class PlaybackSnapshot {
  /// The queue, in order, as song ids.
  final List<String> songIds;

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
    this.queueTitle,
  });

  /// Schema version, so a later format change can be told apart from garbage.
  static const int currentVersion = 1;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'songIds': songIds,
    'index': index,
    'positionMs': position.inMilliseconds,
    'wasPlaying': wasPlaying,
    'shuffle': shuffle,
    'repeat': repeatMode.name,
    'volume': volume,
    'queueTitle': queueTitle,
    'savedAtMs': savedAt.millisecondsSinceEpoch,
  };

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

    final songIds = decoded['songIds'];
    if (songIds is! List || songIds.isEmpty) return null;
    if (songIds.any((id) => id is! String)) return null;

    final index = decoded['index'];
    final positionMs = decoded['positionMs'];
    final savedAtMs = decoded['savedAtMs'];
    if (index is! int || positionMs is! int || savedAtMs is! int) return null;

    final volume = decoded['volume'];
    final repeat = decoded['repeat'];
    final title = decoded['queueTitle'];

    return PlaybackSnapshot(
      songIds: List.of(songIds.cast<String>()),
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

/// Keeps the snapshot in a JSON file in the app's private storage.
///
/// App support rather than documents: this is app state, not something the user
/// made or should find in a file browser. Writes go to a temporary file that is
/// then renamed over the target, so a write interrupted by the app being
/// backgrounded and killed cannot leave a half-written file that fails to parse
/// on the next launch.
class FilePlaybackStateStore implements PlaybackStateStore {
  static const String fileName = 'playback_state.json';

  /// Resolves the directory the file lives in.
  final Future<Directory> Function() _directory;

  /// [directory] is injectable so tests can point the store at a temp directory
  /// instead of going through path_provider, which has no platform in tests.
  FilePlaybackStateStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  @override
  Future<PlaybackSnapshot?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return PlaybackSnapshot.tryParse(await file.readAsString());
    } on Object {
      // Storage that cannot be read is not worth failing a launch over; the app
      // simply opens with an empty player.
      return null;
    }
  }

  @override
  Future<void> write(PlaybackSnapshot snapshot) async {
    try {
      final file = await _file();
      final pending = File('${file.path}.tmp');
      await pending.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await pending.rename(file.path);
    } on Object {
      // Losing a snapshot only costs the user their place in the queue. It must
      // never interrupt playback, so this is swallowed deliberately.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object {
      // As above: a stale snapshot that fails to delete is harmless, because it
      // is only ever read on the next launch.
    }
  }
}
