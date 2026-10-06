import 'dart:typed_data';

import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/artwork_service.dart';

/// An [ArtworkService] that answers without touching the platform.
///
/// The real one crosses a method channel, which never replies inside the widget
/// test harness. Widget tests are about navigation and layout, not image decoding,
/// so they get a device with no covers -- which is a state the app has to render
/// correctly anyway.
class FakeArtworkService extends ArtworkService {
  FakeArtworkService({this.artwork}) : super(queryTimeout: Duration.zero);

  /// Returned for every track. Null mimics a device with no embedded art.
  final Uint8List? artwork;

  /// Every album id that was asked about, in order.
  final requestedAlbumIds = <int>[];

  @override
  Future<Uint8List?> artworkFor(WavelySong song) async {
    final albumId = song.albumId;
    if (albumId != null) requestedAlbumIds.add(albumId);
    return artwork;
  }
}