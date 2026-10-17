import 'dart:convert';
import 'dart:typed_data';

import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/artwork_service.dart';

/// A single-pixel PNG that decodes for real, so tests that need an artwork
/// widget to reach its loaded state do not get away with an image the codec
/// would reject.
final Uint8List testArtworkPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// An [ArtworkService] that answers without touching the platform.
///
/// The real one crosses a method channel, which never replies inside the widget
/// test harness. Widget tests are about navigation and layout, not image decoding,
/// so by default they get a device with no covers -- which is a state the app has
/// to render correctly anyway. Pass [artwork] to model a device that *does* have
/// covers: every album then resolves to that cover, through the same synchronous
/// cache path the real service uses, which is what the cover-flight animation
/// needs before it will run.
class FakeArtworkService extends ArtworkService {
  FakeArtworkService({this.artwork}) : super(queryTimeout: Duration.zero);

  /// Returned for every track. Null mimics a device with no embedded art.
  final Uint8List? artwork;

  /// Every album id that was asked about, in order.
  final requestedAlbumIds = <int>[];

  @override
  bool isCached(WavelySong song) => artwork != null && song.albumId != null;

  @override
  Uint8List? cachedArtworkFor(WavelySong song) =>
      isCached(song) ? artwork : null;

  @override
  Future<Uint8List?> artworkFor(WavelySong song) async {
    final albumId = song.albumId;
    if (albumId != null) requestedAlbumIds.add(albumId);
    return artwork;
  }
}
