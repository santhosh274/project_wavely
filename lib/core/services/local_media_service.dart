import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song_model.dart';
import '../models/album_model.dart';
import '../models/artist_model.dart';
import '../models/playlist_model.dart';

/// Why a library load ended the way it did.
///
/// This distinction matters: the previous implementation caught every failure and
/// returned demo tracks instead, so a missing permission was indistinguishable
/// from a device that actually had music on it.
enum LibraryLoadStatus {
  /// Songs were read from the device media store.
  success,

  /// The media permission was declined, so the device store cannot be read.
  permissionDenied,

  /// Permission was granted but the device genuinely holds no audio.
  empty,

  /// The media query itself failed.
  error,
}

/// Outcome of a single attempt to read the device media store.
class LibraryLoadResult {
  final LibraryLoadStatus status;
  final List<WavelySong> songs;
  final String? message;

  const LibraryLoadResult({
    required this.status,
    this.songs = const [],
    this.message,
  });
}

/// Service for scanning and fetching local audio files
class LocalMediaService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request the media permission needed to read the device audio store.
  ///
  /// The two platforms need genuinely different permissions, and picking the
  /// wrong one is not a no-op:
  ///
  /// * Android 13 (API 33) replaced READ_EXTERNAL_STORAGE with READ_MEDIA_AUDIO,
  ///   so both are requested and either one satisfying the platform is enough.
  ///   Both must also be declared in AndroidManifest.xml -- Android silently
  ///   denies an undeclared permission rather than prompting for it.
  /// * iOS has no storage permission. Reading the media library is MPMediaLibrary,
  ///   reached through [Permission.mediaLibrary], which is only compiled into the
  ///   plugin when PERMISSION_MEDIA_LIBRARY is set in the Podfile.
  ///
  /// Requesting [Permission.audio] on iOS looks like it should work and does
  /// not: permission_handler maps it to the *microphone*, and with only the media
  /// library macro enabled it falls through to UnknownPermissionStrategy and
  /// reports PermissionStatusPermanentlyDenied. [Permission.storage] is
  /// hardcoded to granted on iOS, so treating it as the fallback made the app
  /// believe it had access to the library it had never been authorized for.
  Future<bool> requestPermissions() async {
    if (_isApple) {
      return (await Permission.mediaLibrary.request()).isGranted;
    }

    final audio = await Permission.audio.request();
    if (audio.isGranted) {
      return true;
    }
    // No-op on Android 13+, but required on Android 12 and below.
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  /// Whether the media permission is already granted, without prompting.
  Future<bool> hasPermission() async {
    if (_isApple) {
      return Permission.mediaLibrary.isGranted;
    }

    if (await Permission.audio.isGranted) {
      return true;
    }
    return Permission.storage.isGranted;
  }

  /// True on the Apple platforms, which share the MPMediaLibrary permission.
  static bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Send the user to the OS settings page, needed once the system has stopped
  /// showing the permission prompt (permanently denied).
  Future<void> openSettings() => openAppSettings();

  /// Query the device media store.
  ///
  /// No demo data is substituted on failure. Returning fabricated tracks made a
  /// permission problem look like a populated library.
  Future<LibraryLoadResult> fetchLocalSongs() async {
    try {
      if (!await requestPermissions()) {
        return const LibraryLoadResult(
          status: LibraryLoadStatus.permissionDenied,
          message:
              'Storage access is needed to read songs stored on this device.',
        );
      }

      final querySongs = await _audioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      if (querySongs.isEmpty) {
        return const LibraryLoadResult(
          status: LibraryLoadStatus.empty,
          message: 'No audio files were found on this device.',
        );
      }

      return LibraryLoadResult(
        status: LibraryLoadStatus.success,
        songs: querySongs.map(_mapSong).toList(),
      );
    } on PlatformException catch (e) {
      // permission_handler throws when there is no foreground Activity to host
      // the dialog, and on_audio_query surfaces channel failures the same way.
      return LibraryLoadResult(
        status: LibraryLoadStatus.error,
        message: 'Media access failed (${e.code}). '
            'This usually clears on retry -- otherwise grant the permission '
            'from Settings.',
      );
    } on Exception catch (e) {
      return LibraryLoadResult(
        status: LibraryLoadStatus.error,
        message: 'Could not read the media library: $e',
      );
    }
  }

  /// MediaStore stores a lot of missing metadata as the literal `"<unknown>"`.
  String? _cleanOrNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == '<unknown>') return null;
    return trimmed;
  }

  WavelySong _mapSong(SongModel s) {
    return WavelySong(
      id: s.id.toString(),
      title: s.title.trim().isEmpty ? 'Unknown Title' : s.title.trim(),
      artist: _cleanOrNull(s.artist) ?? 'Unknown Artist',
      album: _cleanOrNull(s.album) ?? 'Unknown Album',
      duration: Duration(milliseconds: s.duration ?? 0),
      uri: s.data,
      contentUri: _cleanOrNull(s.uri),
      albumId: s.albumId,
      // The media notification reads its cover from the MediaItem artUri,
      // which is built from this. The well-known albumart content URI stays
      // readable through the ContentResolver even under scoped storage, where
      // a raw file path would not be.
      albumArtUri: s.albumId == null
          ? null
          : 'content://media/external/audio/albumart/${s.albumId}',
      genre: _cleanOrNull(s.genre),
      trackNumber: s.track,
    );
  }

  /// Extract albums list from tracks
  List<WavelyAlbum> extractAlbums(List<WavelySong> songs) {
    final Map<String, List<WavelySong>> grouped = {};
    for (final song in songs) {
      grouped.putIfAbsent(song.album, () => []).add(song);
    }

    return grouped.entries.map((entry) {
      final albumName = entry.key;
      final albumSongs = entry.value;
      return WavelyAlbum(
        id: albumName,
        albumName: albumName,
        artist: albumSongs.first.artist,
        songCount: albumSongs.length,
      );
    }).toList();
  }

  /// Extract artists list from tracks
  List<WavelyArtist> extractArtists(List<WavelySong> songs) {
    final Map<String, List<WavelySong>> grouped = {};
    for (final song in songs) {
      grouped.putIfAbsent(song.artist, () => []).add(song);
    }

    return grouped.entries.map((entry) {
      final artistName = entry.key;
      final artistSongs = entry.value;
      final albumNames = artistSongs.map((s) => s.album).toSet();

      return WavelyArtist(
        id: artistName,
        artistName: artistName,
        numberOfAlbums: albumNames.length,
        numberOfTracks: artistSongs.length,
      );
    }).toList();
  }

  /// Build playlists from the genres actually present on the device.
  ///
  /// These replace a set of hardcoded playlists whose song IDs ('1'..'5') only
  /// ever matched the demo tracks.
  List<WavelyPlaylist> extractGenrePlaylists(List<WavelySong> songs) {
    final Map<String, List<String>> byGenre = {};
    for (final song in songs) {
      final genre = song.genre;
      if (genre == null) continue;
      byGenre.putIfAbsent(genre, () => []).add(song.id);
    }

    final playlists = byGenre.entries.map((entry) {
      final slug = entry.key
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      return WavelyPlaylist(
        id: 'genre-$slug',
        name: entry.key,
        songIds: entry.value,
        createdAt: DateTime.now(),
        source: PlaylistSource.genre,
      );
    }).toList();

    playlists.sort((a, b) => b.songCount.compareTo(a.songCount));
    return playlists;
  }
}
