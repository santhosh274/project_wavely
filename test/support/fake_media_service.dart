import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/local_media_service.dart';

/// A device whose media store can be swapped between loads.
///
/// Lets a test prove behaviour across a rescan -- specifically that playlists the
/// user created survive one -- without the platform channels a real
/// [LocalMediaService] talks to.
class FakeLocalMediaService extends LocalMediaService {
  FakeLocalMediaService(this.songs);

  List<WavelySong> songs;

  /// When true the scan reports a declined permission instead of the tracks.
  bool permissionGranted = true;

  @override
  Future<bool> requestPermissions() async => permissionGranted;

  @override
  Future<LibraryLoadResult> fetchLocalSongs() async {
    if (!permissionGranted) {
      return const LibraryLoadResult(
        status: LibraryLoadStatus.permissionDenied,
        message: 'Storage access is needed to read songs on this device.',
      );
    }

    return LibraryLoadResult(status: LibraryLoadStatus.success, songs: songs);
  }
}

/// Four tracks across two albums, two artists and two genres.
///
/// Ordered newest first, matching how the real media query returns them, so the
/// "recently added" behaviour is representable.
List<WavelySong> libraryFixture() => const [
      WavelySong(
        id: '1',
        title: 'Neon Tide',
        artist: 'Vela',
        album: 'Harbour Lights',
        duration: Duration(minutes: 3),
        uri: 'content://media/external/audio/media/1',
        genre: 'Ambient',
        albumId: 100,
      ),
      WavelySong(
        id: '2',
        title: 'Aurora Fields',
        artist: 'Vela',
        album: 'Harbour Lights',
        duration: Duration(minutes: 4),
        uri: 'content://media/external/audio/media/2',
        genre: 'Ambient',
        albumId: 100,
      ),
      WavelySong(
        id: '3',
        title: 'Paper Lanterns',
        artist: 'Kite',
        album: 'Slow Light',
        duration: Duration(minutes: 2),
        uri: 'content://media/external/audio/media/3',
        genre: 'Folk',
        albumId: 101,
      ),
      WavelySong(
        id: '4',
        title: 'Dust and Gold',
        artist: 'Kite',
        album: 'Slow Light',
        duration: Duration(minutes: 5),
        uri: 'content://media/external/audio/media/4',
        genre: 'Folk',
        albumId: 101,
      ),
    ];