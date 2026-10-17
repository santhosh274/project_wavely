import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/artwork_service.dart';
import 'package:wavely/core/widgets/artwork_image.dart';

/// A single-pixel PNG, so the widget tests exercise real decoding rather than a
/// stub that would hide a malformed-image bug.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// An [ArtworkService] whose replies the test releases by hand.
///
/// The real one owns a cache the widget reads synchronously
/// ([ArtworkService.isCached] / [ArtworkService.cachedArtworkFor]), so a fake
/// that only overrode `artworkFor` could not exercise the cache-hit path at all.
/// This one models both halves: a cache to seed, and a completer per album to
/// hold a reply open while the test looks at the frame in between.
class _ScriptedArtworkService extends ArtworkService {
  _ScriptedArtworkService() : super(queryTimeout: Duration.zero);

  final cache = <int, Uint8List?>{};
  final _pending = <int, Completer<Uint8List?>>{};
  int queries = 0;

  @override
  bool isCached(WavelySong song) =>
      song.albumId != null && cache.containsKey(song.albumId);

  @override
  Uint8List? cachedArtworkFor(WavelySong song) =>
      song.albumId == null ? null : cache[song.albumId];

  @override
  Future<Uint8List?> artworkFor(WavelySong song) {
    final albumId = song.albumId;
    if (albumId == null) return Future.value(null);
    if (cache.containsKey(albumId)) return Future.value(cache[albumId]);
    queries++;
    return _pending.putIfAbsent(albumId, Completer.new).future.then((bytes) {
      cache[albumId] = bytes;
      return bytes;
    });
  }

  /// Release the held reply for [albumId].
  void complete(int albumId, Uint8List? bytes) {
    _pending.putIfAbsent(albumId, Completer.new).complete(bytes);
  }
}

WavelySong _song({required String id, int? albumId}) => WavelySong(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  uri: 'content://media/external/audio/media/$id',
  albumId: albumId,
);

void main() {
  late _ScriptedArtworkService service;

  setUp(() => service = _ScriptedArtworkService());

  Future<void> pumpArt(
    WidgetTester tester,
    WavelySong song, {
    double size = 120.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArtworkScope(
          service: service,
          child: Center(
            child: ArtworkImage(
              song: song,
              size: size,
              placeholder: const Text('placeholder'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a cached cover paints on the first frame, never the placeholder', (
    tester,
  ) async {
    service.cache[1] = _onePixelPng;

    await pumpArt(tester, _song(id: 'a', albumId: 1));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
  });

  testWidgets('an uncached cover shows the placeholder until its reply lands', (
    tester,
  ) async {
    await pumpArt(tester, _song(id: 'a', albumId: 1));

    expect(find.text('placeholder'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    service.complete(1, _onePixelPng);
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('placeholder'), findsNothing);
  });

  testWidgets('changing track keeps the old cover up instead of flashing back', (
    tester,
  ) async {
    service.cache[1] = _onePixelPng;

    await pumpArt(tester, _song(id: 'a', albumId: 1));
    expect(find.byType(Image), findsOneWidget);

    // The next track's album is cold, so its reply is still in flight. The
    // cover that was already on screen has to stay put: it collapsing to the
    // placeholder for a few frames is exactly the bug being guarded against.
    await pumpArt(tester, _song(id: 'b', albumId: 2));
    expect(find.text('placeholder'), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    service.complete(2, _onePixelPng);
    await tester.pumpAndSettle();

    expect(find.text('placeholder'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a coverless album settles on the placeholder without re-asking', (
    tester,
  ) async {
    await pumpArt(tester, _song(id: 'a', albumId: 1));
    service.complete(1, null);
    await tester.pumpAndSettle();

    expect(find.text('placeholder'), findsOneWidget);

    // A rebuild for any other reason must not re-query the media store for a
    // cover it has already learned does not exist.
    await tester.pump();
    await tester.pump();
    expect(service.queries, 1);
  });

  testWidgets('a cached album is served without a query', (tester) async {
    service.cache[7] = _onePixelPng;

    await pumpArt(tester, _song(id: 'a', albumId: 7));

    expect(service.queries, 0);
    expect(find.byType(Image), findsOneWidget);
  });
}
