import 'dart:typed_data';

/// Wavely Track / Song Model
class WavelySong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;

  /// Absolute file path, when the platform exposes one.
  final String uri;

  /// `content://` URI, which stays readable on Android 10+ where scoped storage
  /// can block direct access to shared-storage file paths.
  final String? contentUri;

  final String? albumArtUri;
  final Uint8List? artworkBytes;

  /// MediaStore album id, which is the key embedded artwork is stored under.
  final int? albumId;

  final String? genre;
  final int? trackNumber;
  final bool isFavorite;

  /// Size of the file in bytes, when the media store reported one.
  ///
  /// Carried so two devices can tell whether they are holding the *same file*
  /// rather than two rips of the same song: title and artist collide constantly
  /// across compilations and remasters, but byte count does not. A listening
  /// room matches guest libraries on this before it falls back to metadata.
  final int? fileSize;

  const WavelySong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.uri,
    this.contentUri,
    this.albumArtUri,
    this.artworkBytes,
    this.albumId,
    this.genre,
    this.trackNumber,
    this.isFavorite = false,
    this.fileSize,
  });

  String get durationFormatted {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  WavelySong copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? uri,
    String? contentUri,
    String? albumArtUri,
    Uint8List? artworkBytes,
    int? albumId,
    String? genre,
    int? trackNumber,
    bool? isFavorite,
    int? fileSize,
  }) {
    return WavelySong(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      uri: uri ?? this.uri,
      contentUri: contentUri ?? this.contentUri,
      albumArtUri: albumArtUri ?? this.albumArtUri,
      artworkBytes: artworkBytes ?? this.artworkBytes,
      albumId: albumId ?? this.albumId,
      genre: genre ?? this.genre,
      trackNumber: trackNumber ?? this.trackNumber,
      isFavorite: isFavorite ?? this.isFavorite,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}
