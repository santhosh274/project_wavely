import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/artwork_service.dart';

/// Answers [OnAudioQueryPlatform.queryArtwork] from a script instead of the
/// platform channel, and counts what it was asked for.
///
/// Carries [MockPlatformInterfaceMixin] so it can be installed as
/// [OnAudioQueryPlatform.instance]; the platform interface checks the token
/// before accepting an implementation and rejects anything that does not know it.
class FakeOnAudioQueryPlatform extends OnAudioQueryPlatform
    with MockPlatformInterfaceMixin {
  /// Album ids that have artwork. Anything else has none.
  final covers = <int, Uint8List>{};

  /// Album ids that never answer, to stand in for a wedged media provider.
  final hung = <int>{};

  /// Every album id asked about, in order.
  final requested = <int>[];

  @override
  Future<Uint8List?> queryArtwork(
    int id,
    ArtworkType type, {
    ArtworkFormat? format,
    int? size,
    int? quality,
  }) {
    requested.add(id);
    if (hung.contains(id)) return Completer<Uint8List?>().future;
    return Future.value(covers[id]);
  }
}

WavelySong _song({int? albumId}) => WavelySong(
  id: 'track-$albumId',
  title: 'Track',
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  uri: 'content://media/external/audio/media/1',
  albumId: albumId,
);

/// The platform instance is global, so it is put back the way it was found.
void main() {
  late OnAudioQueryPlatform original;
  late FakeOnAudioQueryPlatform platform;
  late ArtworkService service;

  setUpAll(() => original = OnAudioQueryPlatform.instance);

  setUp(() {
    platform = FakeOnAudioQueryPlatform();
    OnAudioQueryPlatform.instance = platform;
    service = ArtworkService();
  });

  tearDown(() => OnAudioQueryPlatform.instance = original);

  group('loading', () {
    test('returns the cover the media store holds', () async {
      final cover = Uint8List.fromList([1, 2, 3]);
      platform.covers[42] = cover;

      expect(await service.artworkFor(_song(albumId: 42)), cover);
      expect(platform.requested, [42]);
    });

    test('a track with no album is not looked up at all', () async {
      // Album-less tracks have nothing to key a query on; asking anyway would
      // be a wasted round trip per visible row.
      expect(await service.artworkFor(_song()), isNull);
      expect(platform.requested, isEmpty);
      expect(service.isCached(_song()), isFalse);
    });

    test('a missing cover is a result, not an error', () async {
      expect(await service.artworkFor(_song(albumId: 7)), isNull);
    });

    test('a query that never answers resolves to no cover', () async {
      platform.hung.add(9);
      // A short timeout keeps the test quick; the point is that one exists.
      final service = ArtworkService(queryTimeout: const Duration(seconds: 1));

      final bytes = await service
          .artworkFor(_song(albumId: 9))
          .timeout(const Duration(seconds: 5));

      // Without the timeout in the service this would hang the caller forever
      // and leave the artwork placeholder up for the life of the screen.
      expect(bytes, isNull);
    });

    test('a settled query does not wait on itself', () async {
      platform.covers[1] = Uint8List.fromList([4]);

      // The shared-request bookkeeping used to chain the in-flight cleanup onto
      // the future it was stored as, so the request could only ever complete by
      // waiting for the very callback that was waiting for it. Nothing timeouts
      // here on purpose: a hang is the bug, not a slow query.
      final bytes = await service
          .artworkFor(_song(albumId: 1))
          .timeout(const Duration(seconds: 5));

      expect(bytes, hasLength(1));

      // And the entry is released, so the next album is not served the old one.
      platform.covers[2] = Uint8List.fromList([5, 6]);
      expect(await service.artworkFor(_song(albumId: 2)), hasLength(2));
      expect(platform.requested, [1, 2]);
    });
  });

  group('caching', () {
    test('one query covers every track on the album', () async {
      platform.covers[5] = Uint8List.fromList([9]);

      await service.artworkFor(_song(albumId: 5));
      await service.artworkFor(_song(albumId: 5));
      await service.artworkFor(_song(albumId: 5));

      expect(platform.requested, [5]);
    });

    test('a missing cover is remembered too', () async {
      await service.artworkFor(_song(albumId: 5));
      await service.artworkFor(_song(albumId: 5));

      // Otherwise every scroll back over a coverless row re-queries the store.
      expect(platform.requested, [5]);
      expect(service.isCached(_song(albumId: 5)), isTrue);
    });

    test('simultaneous requests share one query', () async {
      final first = service.artworkFor(_song(albumId: 3));
      final second = service.artworkFor(_song(albumId: 3));

      expect(await Future.wait([first, second]), hasLength(2));

      // A list building itself asks for the same cover several times before the
      // first reply lands.
      expect(platform.requested, [3]);
    });

    test(
      'a finished query does not block the next one for another album',
      () async {
        await service.artworkFor(_song(albumId: 1));
        await service.artworkFor(_song(albumId: 2));

        expect(platform.requested, [1, 2]);
      },
    );

    test('clearing makes the next request ask again', () async {
      await service.artworkFor(_song(albumId: 5));
      expect(service.isCached(_song(albumId: 5)), isTrue);

      service.clear();
      expect(service.isCached(_song(albumId: 5)), isFalse);

      await service.artworkFor(_song(albumId: 5));
      expect(platform.requested, [5, 5]);
    });
  });

  group('eviction', () {
    test(
      'the cache is bounded so a long session cannot grow without limit',
      () async {
        // More albums than the cache holds, so the oldest have to go.
        for (var albumId = 0; albumId < 200; albumId++) {
          platform.covers[albumId] = Uint8List.fromList([albumId]);
          await service.artworkFor(_song(albumId: albumId));
        }

        expect(service.isCached(_song(albumId: 199)), isTrue);
        expect(service.isCached(_song(albumId: 0)), isFalse);
      },
    );
  });
}
