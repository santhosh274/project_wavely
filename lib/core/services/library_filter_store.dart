import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The content the user has chosen to keep out of the library.
///
/// Both exclusions are applied to the *scanned* song list, so a track hidden
/// here is hidden everywhere the library is read from -- the song list, album
/// and artist counts, playlists, search results, favourites and "recently
/// added" -- rather than being filtered surface by surface.
class LibraryFilterSettings {
  /// Folder paths whose songs are not part of the library.
  ///
  /// Stored as absolute folder paths (the parent of a track's file path), not
  /// as a flag on a song: a rescan rebuilds every song, so the decision has to
  /// survive as a rule about the folder.
  final Set<String> excludedFolders;

  /// Tracks shorter than this are left out. [Duration.zero] keeps everything.
  final Duration minimumDuration;

  const LibraryFilterSettings({
    this.excludedFolders = const {},
    this.minimumDuration = Duration.zero,
  });

  /// Whether anything is actually excluded right now.
  bool get isActive => excludedFolders.isNotEmpty || minimumDuration > Duration.zero;

  static const int currentVersion = 1;

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'excludedFolders': excludedFolders.toList(),
    'minimumDurationMs': minimumDuration.inMilliseconds,
  };

  /// Rebuild from stored JSON, or null when it is not usable.
  ///
  /// Validated rather than cast: the file outlives app upgrades, and a library
  /// that fails to load because of a stale field would be a worse outcome than
  /// opening with no exclusions set.
  static LibraryFilterSettings? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final folders = decoded['excludedFolders'];
    final minMs = decoded['minimumDurationMs'];

    return LibraryFilterSettings(
      excludedFolders: folders is List
          ? {
              for (final folder in folders)
                if (folder is String && folder.isNotEmpty) folder,
            }
          : const {},
      minimumDuration: minMs is int && minMs > 0
          ? Duration(milliseconds: minMs)
          : Duration.zero,
    );
  }

  @override
  String toString() =>
      'LibraryFilterSettings(${excludedFolders.length} folders, '
      'min ${minimumDuration.inSeconds}s)';
}

/// Where the library exclusions are kept between launches.
///
/// An interface so a test can drive the controller with an in-memory store, and
/// so a store that cannot be read can never be confused with "nothing was
/// excluded".
abstract interface class LibraryFilterStore {
  Future<LibraryFilterSettings?> read();

  Future<void> write(LibraryFilterSettings settings);
}

/// Keeps the exclusions in a JSON file in the app's private storage.
///
/// The same shape as the playback snapshot store, and deliberately
/// error-swallowing: a device where the file cannot be read or written simply
/// opens with no exclusions, which is the safe default.
class FileLibraryFilterStore implements LibraryFilterStore {
  static const String fileName = 'library_filters.json';

  /// Resolves the directory the file lives in.
  ///
  /// [directory] is injectable so tests can point the store at a temp directory
  /// instead of going through path_provider, which has no platform in tests.
  final Future<Directory> Function() _directory;

  FileLibraryFilterStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  @override
  Future<LibraryFilterSettings?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return LibraryFilterSettings.tryParse(await file.readAsString());
    } on Object {
      // Unreadable storage is not worth failing a launch over.
      return null;
    }
  }

  @override
  Future<void> write(LibraryFilterSettings settings) async {
    try {
      final file = await _file();
      final pending = File('${file.path}.tmp');
      await pending.writeAsString(jsonEncode(settings.toJson()), flush: true);
      await pending.rename(file.path);
    } on Object {
      // Losing the preference costs the user one trip back to Settings. It
      // must never interrupt the library, so it is swallowed deliberately.
    }
  }
}
