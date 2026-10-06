/// Wavely Album Model
class WavelyAlbum {
  final String id;
  final String albumName;
  final String artist;
  final int songCount;
  final String? artworkUri;

  const WavelyAlbum({
    required this.id,
    required this.albumName,
    required this.artist,
    required this.songCount,
    this.artworkUri,
  });
}
