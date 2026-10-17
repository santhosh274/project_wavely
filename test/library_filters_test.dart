import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';

import 'support/fake_media_service.dart';
import 'support/memory_library_filter_store.dart';

/// Tracks with real file paths, so folder exclusion has something to key on.
/// A content:// URI deliberately cannot be attached to a folder.
List<WavelySong> folderFixture() => const [
  WavelySong(
    id: '1',
    title: 'Neon Tide',
    artist: 'Vela',
    album: 'Harbour Lights',
    duration: Duration(minutes: 3),
    uri: '/storage/emulated/0/Music/Rock/neon.mp3',
    genre: 'Ambient',
  ),
  WavelySong(
    id: '2',
    title: 'Short Intro',
    artist: 'Vela',
    album: 'Harbour Lights',
    duration: Duration(seconds: 20),
    uri: '/storage/emulated/0/Music/Rock/intro.mp3',
    genre: 'Ambient',
  ),
  WavelySong(
    id: '3',
    title: 'Episode One',
    artist: 'Kite',
    album: 'Slow Light',
    duration: Duration(minutes: 45),
    uri: '/storage/emulated/0/Podcasts/ep1.mp3',
    genre: 'Folk',
  ),
];

void main() {
  /// Mount a controller and let its deferred scan (and the preference read that
  /// follows it) finish.
  Future<LibraryController> load(
    WidgetTester tester, {
    List<WavelySong>? songs,
    MemoryLibraryFilterStore? filterStore,
  }) async {
    final controller = LibraryController(
      mediaService: FakeLocalMediaService(songs ?? folderFixture()),
      filterStore: filterStore ?? MemoryLibraryFilterStore(),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return controller;
  }

  group('duration exclusions', () {
    testWidgets('a minimum length hides short tracks from every surface', (
      tester,
    ) async {
      final library = await load(tester);
      expect(library.allSongs, hasLength(3));

      library.setMinimumDuration(const Duration(minutes: 1));

      // Gone from the library list and the filtered list used by search.
      expect(library.allSongs.map((s) => s.id), ['1', '3']);
      expect(library.songs.map((s) => s.id), ['1', '3']);
      // And from the collections built out of the library.
      expect(library.songsInAlbum('Harbour Lights').map((s) => s.id), ['1']);
      expect(library.favorites, isEmpty);

      // A hidden track cannot be found by searching for it either.
      library.setSearchQuery('intro');
      expect(library.songs, isEmpty);
      library.setSearchQuery('');

      expect(library.excludedSongCount, 1);
      expect(library.hasLibraryFilters, isTrue);
    });

    testWidgets('the rule is written back so it survives a relaunch', (
      tester,
    ) async {
      final store = MemoryLibraryFilterStore();
      final library = await load(tester, filterStore: store);

      library.setMinimumDuration(const Duration(minutes: 2));
      await tester.pump();

      expect(store.writes, greaterThan(0));
      expect(store.settings?.minimumDuration, const Duration(minutes: 2));

      // A fresh controller on the same store opens with the rule applied.
      final reopened = await load(tester, filterStore: store);
      expect(reopened.allSongs.map((s) => s.id), ['1', '3']);
      expect(reopened.minimumDuration, const Duration(minutes: 2));
    });
  });

  group('folder exclusions', () {
    testWidgets('excluding a folder hides its tracks but keeps it listable', (
      tester,
    ) async {
      final library = await load(tester);

      expect(library.folderOptions, [
        '/storage/emulated/0/Music/Rock',
        '/storage/emulated/0/Podcasts',
      ]);
      expect(library.folderSongCounts['/storage/emulated/0/Podcasts'], 1);

      library.setFolderExcluded('/storage/emulated/0/Podcasts', excluded: true);

      expect(library.allSongs.map((s) => s.id), ['1', '2']);
      expect(library.artists.map((a) => a.artistName), ['Vela']);
      expect(library.isFolderExcluded('/storage/emulated/0/Podcasts'), isTrue);
      // Still offered, so it can be switched back on.
      expect(library.folderOptions, contains('/storage/emulated/0/Podcasts'));

      library.setFolderExcluded('/storage/emulated/0/Podcasts', excluded: false);
      expect(library.allSongs, hasLength(3));
    });

    testWidgets('clearing every filter restores the whole scanned library', (
      tester,
    ) async {
      final library = await load(tester);

      library.setMinimumDuration(const Duration(minutes: 1));
      library.setFolderExcluded('/storage/emulated/0/Music/Rock', excluded: true);
      // Short Intro (duration) and Neon Tide (folder) are both hidden.
      expect(library.allSongs.map((s) => s.id), ['3']);

      library.clearLibraryFilters();

      expect(library.hasLibraryFilters, isFalse);
      expect(library.allSongs, hasLength(3));
    });
  });

  group('search', () {
    testWidgets('filters a large library quickly, with the same answers', (
      tester,
    ) async {
      final songs = List.generate(
        4000,
        (i) => WavelySong(
          id: '$i',
          title: 'Track $i',
          artist: 'Artist ${i % 200}',
          album: 'Album ${i % 50}',
          duration: Duration(minutes: 3, seconds: i % 60),
          uri: '/storage/emulated/0/Music/track$i.mp3',
          genre: const ['Rock', 'Jazz', 'Pop'][i % 3],
        ),
      );
      final library = await load(tester, songs: songs);
      expect(library.allSongs, hasLength(4000));

      // Correctness first: the same answers the old field-by-field scan gave,
      // checked query by query against a local copy of that scan.
      bool naiveMatch(WavelySong song, String query) {
        final q = query.trim().toLowerCase();
        return song.title.toLowerCase().contains(q) ||
            song.artist.toLowerCase().contains(q) ||
            song.album.toLowerCase().contains(q) ||
            (song.genre?.toLowerCase().contains(q) ?? false);
      }

      const queries = [
        'track 12',
        'artist 7',
        'jazz',
        'album 4',
        'pop',
        'neon',
        'track 30',
      ];

      for (final query in queries) {
        library.setSearchQuery(query);
        final expected = [
          for (final song in songs)
            if (naiveMatch(song, query)) song.id,
        ];
        expect(
          library.songs.map((s) => s.id).toList(),
          expected,
          reason: 'query "$query" disagreed with the field-by-field scan',
        );
      }

      // Then the reason the index exists: typing stays cheap at this size.
      final stopwatch = Stopwatch()..start();
      for (var round = 0; round < 30; round++) {
        for (final query in queries) {
          library.setSearchQuery(query);
        }
      }
      stopwatch.stop();

      // 210 searches over 4000 tracks. Generous by design: this guards against
      // an accidental quadratic, not against a slow machine.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
