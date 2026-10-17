import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wavely/app/wavely_providers.dart';
import 'package:wavely/core/services/audio_player_service.dart'
    show RepeatBehaviour;
import 'package:wavely/core/services/playback_state_store.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/features/navigation/presentation/screens/main_navigation_screen.dart'
    show ShellTabs;
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/player/presentation/screens/now_playing_expanded_screen.dart';
import 'package:wavely/features/player/presentation/widgets/artwork_flight.dart';
import 'package:wavely/features/player/presentation/widgets/mini_player.dart';
import 'package:wavely/main.dart';

import 'support/fake_artwork_service.dart';
import 'support/fake_audio_engine.dart';
import 'support/fake_media_service.dart';
import 'support/memory_playback_store.dart';

void main() {
  late FakeAudioEngine engine;
  late FakeLocalMediaService media;
  late FakeArtworkService artwork;
  late MemoryPlaybackStateStore store;

  // Live controllers, read back out of the provider tree once it is mounted.
  // The tree owns their lifetime, so nothing is disposed by hand here.
  late LibraryController library;
  late PlayerController player;
  late ShellController shell;

  setUp(() {
    engine = FakeAudioEngine();
    media = FakeLocalMediaService(libraryFixture());
    artwork = FakeArtworkService();
    store = MemoryPlaybackStateStore();
  });

  /// Mount the app on the *real* provider wiring -- the same function `main()`
  /// uses -- with the fakes substituted, so the test covers the wiring and not a
  /// hand-copied version of it.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: wavelyProviders(
          mediaService: media,
          audioService: engine,
          artworkService: artwork,
          stateStore: store,
        ),
        child: const WavelyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final root = tester.element(find.byType(WavelyApp));
    library = root.read<LibraryController>();
    player = root.read<PlayerController>();
    shell = root.read<ShellController>();
  }

  /// Mount the app and start the fixture's first track the way a list row does,
  /// so the queue and the play history are set up the way the UI sets them up.
  Future<void> playFirstTrack(WidgetTester tester) async {
    await pumpApp(tester);
    await player.playTrack(
      library.allSongs.first,
      queueContext: library.allSongs,
      queueTitle: 'All Songs',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The mini player's tap target, as a screen reader announces it.
  ///
  /// Matched on a prefix because the semantics label also carries the track name
  /// and artist, which is what someone using TalkBack would actually hear.
  Finder miniPlayerTap() =>
      find.bySemanticsLabel(RegExp('^Open the expanded player'));

  /// The navigation bar only labels the selected tab, so an unselected tab is
  /// found by its icon instead.
  Finder navIcon(IconData icon) => find.byIcon(icon).last;

  /// The fade the expanded player opens and closes with.
  ///
  /// Reached with `skipOffstage: false` on purpose: off its own tab the player
  /// is hidden from the default finders, and what this is asked about is the
  /// state it is left in *while* hidden -- which is what decides whether the
  /// next visit shows anything at all.
  FadeTransition revealFade(WidgetTester tester) =>
      tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(
                NowPlayingExpandedScreen,
                skipOffstage: false,
              ),
              matching: find.byType(FadeTransition, skipOffstage: false),
              skipOffstage: false,
            )
            .first,
      );

  /// Scroll a label into view and tap it.
  ///
  /// The section chips run off the edge of a phone-sized screen, so tapping one
  /// by its text alone would land outside the render tree.
  Future<void> tapLabel(WidgetTester tester, String label) async {
    final finder = find.text(label).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Runs [body] with the semantics tree switched on.
  ///
  /// Off by default in tests, and the mini player's tap target is identified by
  /// its accessibility label -- which is also how a screen reader reaches it, so
  /// finding it that way checks something real rather than a test-only handle.
  Future<void> withSemantics(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await body();
    } finally {
      handle.dispose();
    }
  }

  group('shell', () {
    testWidgets('opens on the home tab', (tester) async {
      await pumpApp(tester);

      expect(shell.currentIndex, ShellTabs.home);
      // The home tab is the main player, so it is what should be on screen.
      expect(find.text('No music playing'), findsOneWidget);
    });

    testWidgets('every tab in the bar switches the shell', (tester) async {
      await pumpApp(tester);

      for (final entry in <int, IconData>{
        ShellTabs.search: CupertinoIcons.search,
        ShellTabs.library: CupertinoIcons.list_bullet,
        ShellTabs.player: CupertinoIcons.music_note_2,
        ShellTabs.home: CupertinoIcons.house,
      }.entries) {
        await tester.tap(navIcon(entry.value));
        await tester.pumpAndSettle();
        expect(shell.currentIndex, entry.key);
      }
    });

    testWidgets(
      'an out-of-range tab is refused rather than crashing the stack',
      (tester) async {
        await pumpApp(tester);

        expect(() => shell.selectTab(ShellTabs.library + 1), throwsRangeError);
        expect(shell.currentIndex, ShellTabs.home);
      },
    );
  });

  group('mini player', () {
    testWidgets('is hidden until something is playing', (tester) async {
      await withSemantics(tester, () async {
        await pumpApp(tester);

        // The widget stays in the tree but renders nothing, so the assertion is
        // about the tappable surface rather than the widget's presence.
        expect(miniPlayerTap(), findsNothing);
      });
    });

    testWidgets('tapping it opens the expanded player tab', (tester) async {
      await withSemantics(tester, () async {
        await playFirstTrack(tester);

        expect(miniPlayerTap(), findsOneWidget);
        expect(shell.currentIndex, ShellTabs.home);

        await tester.tap(miniPlayerTap());
        await tester.pumpAndSettle();

        // A tab switch, not a pushed route: the shell is still there underneath.
        expect(shell.currentIndex, ShellTabs.player);
        expect(shell.currentIndex, kPlayerTabIndex);
        expect(find.byTooltip('Collapse player'), findsOneWidget);
      });
    });

    testWidgets('its play/pause glyph follows the player state', (tester) async {
      await playFirstTrack(tester);

      final mini = find.byType(MiniPlayer);
      // Playing: the mini player has to offer pause, not the play it opened on.
      expect(
        find.descendant(
          of: mini,
          matching: find.byIcon(CupertinoIcons.pause_fill),
        ),
        findsOneWidget,
      );

      await player.togglePlayPause();
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: mini,
          matching: find.byIcon(CupertinoIcons.play_fill),
        ),
        findsOneWidget,
      );
    });

    testWidgets('swiping it up opens the expanded player', (tester) async {
      await withSemantics(tester, () async {
        // Real covers: the flight only runs when it has pixels to carry.
        artwork = FakeArtworkService(artwork: testArtworkPng);
        await playFirstTrack(tester);
        expect(shell.currentIndex, ShellTabs.home);

        // The mirror of pulling the expanded player down: an upward flick on
        // the mini player should send its cover up into the player.
        await tester.dragFrom(
          tester.getCenter(miniPlayerTap()),
          const Offset(0, -120),
        );
        await tester.pump();

        expect(ArtworkFlight.inFlight, isTrue);
        expect(shell.currentIndex, ShellTabs.player);

        await tester.pumpAndSettle();
        expect(ArtworkFlight.inFlight, isFalse);

        await tester.pump(const Duration(seconds: 16));
      });
    });

    testWidgets('the expanded player goes back to the home tab, not a pop', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        await playFirstTrack(tester);

        await tester.tap(miniPlayerTap());
        await tester.pumpAndSettle();
        expect(shell.currentIndex, ShellTabs.player);

        await tester.tap(find.byTooltip('Collapse player'));
        await tester.pumpAndSettle();

        expect(shell.currentIndex, ShellTabs.home);
      });
    });

    testWidgets(
      'the expanded cover is laid out before its tab opens, so the flight has '
      'a real destination to aim at',
      (tester) async {
        await playFirstTrack(tester);

        // Still on the home tab, and yet the destination cover already has a
        // laid-out rect. The shell keeps every tab laid out, which is the whole
        // reason the flight can land exactly on it rather than guessing a size.
        expect(shell.currentIndex, ShellTabs.home);
        final box = ArtworkFlight.expandedArt.currentContext
            ?.findRenderObject() as RenderBox?;
        expect(box, isNotNull);
        expect(box!.hasSize, isTrue);
        expect(box.size.width, greaterThan(100.0));
      },
    );

    testWidgets('the cover flies from the mini player into the expanded player',
        (tester) async {
      await withSemantics(tester, () async {
        // A device with real covers: the flight only runs when it has pixels to
        // carry, and the point is to prove it does carry them.
        artwork = FakeArtworkService(artwork: testArtworkPng);
        await playFirstTrack(tester);

        await tester.tap(miniPlayerTap());
        await tester.pump();

        // Mid-flight the cover is in the overlay, above both screens.
        expect(ArtworkFlight.inFlight, isTrue);

        await tester.pumpAndSettle();

        expect(ArtworkFlight.inFlight, isFalse);
        expect(shell.currentIndex, ShellTabs.player);

        // The palette read is fire-and-forget and only reaches its own timeout
        // in this harness, so the clock is advanced past it rather than leaving
        // a timer pending at teardown.
        await tester.pump(const Duration(seconds: 16));
      });
    });

    testWidgets('a track started from a list is remembered as played', (
      tester,
    ) async {
      await playFirstTrack(tester);

      // "Recently Played" has to reflect what was heard, not the newest tracks
      // on disk. This only passes if the provider wiring really does forward
      // track changes to the library.
      expect(library.recentlyPlayed.map((s) => s.id), [
        library.allSongs.first.id,
      ]);
    });
  });

  group('home', () {
    testWidgets('offers to start the library when nothing is playing', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.text('Play from library'), findsOneWidget);
      // No queue yet, so the heading falls back to something honest.
      expect(find.text('Now Playing'), findsOneWidget);

      await tester.tap(find.text('Play from library'));
      await tester.pumpAndSettle();

      expect(player.currentSong, isNotNull);
      expect(shell.currentIndex, ShellTabs.home);
      // Named after where the list came from, so home can say why these songs
      // are lined up.
      expect(player.queueTitle, 'All Songs');
      expect(find.text('All Songs'), findsOneWidget);
    });

    testWidgets('lists the whole queue with the playing track marked', (
      tester,
    ) async {
      await playFirstTrack(tester);

      // The heading names the playlist, and every track in it is on screen.
      expect(find.text('All Songs'), findsOneWidget);
      for (final song in library.allSongs) {
        expect(find.text(song.title), findsWidgets);
      }

      final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
      expect(tiles, hasLength(library.allSongs.length));
      expect(tiles.first.isCurrent, isTrue);
      // Exactly one row is marked, so "what is playing" is unambiguous.
      expect(tiles.where((tile) => tile.isCurrent), hasLength(1));
      expect(find.textContaining('playing 1 of 4'), findsOneWidget);
    });

    testWidgets('tapping a row plays that track from the same queue', (
      tester,
    ) async {
      await playFirstTrack(tester);
      final loadsBefore = engine.setQueueCalls.length;

      await tester.tap(find.byType(SongTile).at(2));
      await tester.pumpAndSettle();

      expect(player.currentSong?.id, library.allSongs[2].id);
      expect(player.currentIndex, 2);
      expect(find.textContaining('playing 3 of 4'), findsOneWidget);

      // The queue is moved within, not rebuilt: the rest of the playlist stays
      // queued behind the new track and no source is read again.
      expect(player.queue, hasLength(library.allSongs.length));
      expect(engine.setQueueCalls, hasLength(loadsBefore));

      final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
      expect(tiles[2].isCurrent, isTrue);
      expect(tiles.first.isCurrent, isFalse);
    });

    testWidgets('the shuffle button replays the same list in a new order', (
      tester,
    ) async {
      await playFirstTrack(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Shuffle'));
      await tester.pumpAndSettle();

      // Shuffling a four track list is not guaranteed to reorder it, so what is
      // checked is that the same tracks are still queued under the same name,
      // which is what the button promises.
      expect(
        player.queue.map((s) => s.id).toSet(),
        library.allSongs.map((s) => s.id).toSet(),
      );
      expect(player.queueTitle, 'All Songs');
      expect(find.byType(SongTile), findsNWidgets(library.allSongs.length));
    });
  });

  group('expanded player', () {
    testWidgets('the transport glyph follows play and pause', (tester) async {
      await playFirstTrack(tester);
      shell.selectTab(ShellTabs.player);
      await tester.pumpAndSettle();

      // Regression: the breathe-scale wrapper cached the button as a static
      // child, so the glyph froze on play while the state moved underneath.
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);

      await player.togglePlayPause();
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);

      await player.togglePlayPause();
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    });

    testWidgets('the repeat button cycles and says which state it is in', (
      tester,
    ) async {
      await playFirstTrack(tester);
      shell.selectTab(ShellTabs.player);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Repeat off'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Repeat queue'), findsOneWidget);

      await tester.tap(find.byTooltip('Repeat queue'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Repeat this song'), findsOneWidget);

      await tester.tap(find.byTooltip('Repeat this song'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Repeat off'), findsOneWidget);
    });

    testWidgets('the shuffle button turns shuffle on and off', (tester) async {
      await playFirstTrack(tester);
      shell.selectTab(ShellTabs.player);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Shuffle off'));
      await tester.pumpAndSettle();
      expect(player.isShuffle, isTrue);
      expect(find.byTooltip('Shuffle on'), findsOneWidget);

      await tester.tap(find.byTooltip('Shuffle on'));
      await tester.pumpAndSettle();
      expect(player.isShuffle, isFalse);
      expect(find.byTooltip('Shuffle off'), findsOneWidget);
    });
  });

  group('profile', () {
    testWidgets('the top-left icon opens the profile page', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Profile, settings and stats'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('YOUR LIBRARY'), findsOneWidget);
    });

    testWidgets('the profile page counts the real library', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Profile, settings and stats'));
      await tester.pumpAndSettle();

      // Counted from the library rather than written in, so it cannot drift.
      expect(find.text('${library.allSongs.length}'), findsWidgets);
      expect(find.text('Songs'), findsOneWidget);
    });

    testWidgets('the profile page goes back', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Profile, settings and stats'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsNothing);
      expect(shell.currentIndex, ShellTabs.home);
    });

    testWidgets('the profile page exposes the library filters', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip('Profile, settings and stats'));
      await tester.pumpAndSettle();

      // The section sits below the fold on a phone-sized screen.
      await tester.scrollUntilVisible(find.text('LIBRARY FILTERS'), 300.0);
      await tester.pumpAndSettle();

      expect(find.text('Hide short tracks'), findsOneWidget);
      expect(find.text('Excluded folders'), findsOneWidget);
      // The fixture's tracks are content:// URIs, so no folder can be derived --
      // the row says so rather than offering an empty picker.
      expect(find.text('No folders detected in this library'), findsOneWidget);
    });
  });

  group('library collections', () {
    testWidgets('lists songs, albums, artists and every playlist', (tester) async {
      await pumpApp(tester);
      // The old Browse tab folded into the library tab, so its collections
      // are sections here now.
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      // The first section is All Songs, listed by default.
      expect(find.text('Neon Tide'), findsOneWidget);

      await tapLabel(tester, 'Albums');
      expect(find.text('Harbour Lights'), findsWidgets);

      await tapLabel(tester, 'Artists');
      expect(find.text('Vela'), findsWidgets);

      // Genre-generated playlists ride along with the user's own.
      await tapLabel(tester, 'Playlists');
      expect(find.text('Ambient'), findsOneWidget);
    });

    testWidgets('opening an album lists its tracks', (tester) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Albums');
      await tester.tap(find.text('Harbour Lights').last);
      await tester.pumpAndSettle();

      // Both Harbour Lights tracks, so the album card is not a dead end.
      expect(find.text('Neon Tide'), findsOneWidget);
      expect(find.text('Aurora Fields'), findsOneWidget);
    });
  });

  group('collection', () {
    testWidgets('shows the seven library sections', (tester) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      for (final title in [
        'All Songs',
        'Albums',
        'Artists',
        'Favourites',
        'Recently Played',
        'Recently Added',
        'Playlists',
      ]) {
        expect(find.text(title), findsWidgets, reason: 'missing $title');
      }
    });

    testWidgets('recently played is empty until something has played', (
      tester,
    ) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Recently Played');

      expect(find.text('Nothing played yet'), findsOneWidget);
    });

    testWidgets('recently played fills in once a track has been played', (
      tester,
    ) async {
      await playFirstTrack(tester);
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Recently Played');

      expect(find.text(player.currentSong!.title), findsWidgets);
      expect(find.text('Nothing played yet'), findsNothing);
    });

    testWidgets('a new playlist can be created and then opened', (
      tester,
    ) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.library);
      await tester.pumpAndSettle();

      await tapLabel(tester, 'Playlists');
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Road Trip');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(library.userPlaylists.map((p) => p.name), ['Road Trip']);
      expect(find.text('Road Trip'), findsWidgets);
    });
  });

  group('search', () {
    testWidgets('typing narrows the results and clearing restores them', (
      tester,
    ) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.search);
      await tester.pumpAndSettle();

      // With nothing typed the whole library is listed, so the count is the
      // number of tracks rather than a "start searching" prompt.
      expect(find.text('${library.allSongs.length} matches'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'neon');
      await tester.pumpAndSettle();
      expect(find.text('1 match'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      // The field must not keep the old text after the filter is gone.
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller?.text, '');
      expect(find.text('${library.allSongs.length} matches'), findsOneWidget);
    });

    testWidgets('a genre chip filters on the genre itself', (tester) async {
      await pumpApp(tester);
      shell.selectTab(ShellTabs.search);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Folk').first);
      await tester.pumpAndSettle();

      expect(find.text('2 matches in Folk'), findsOneWidget);
    });
  });

  // Closing and reopening the app: what was playing has to still be there, or the
  // session looks lost every time the app is restarted.
  group('reopening the app', () {
    /// Tear the running app down and bring it back up, keeping only what a real
    /// restart leaves behind -- the stored session.
    ///
    /// The media service and the store survive because they are the "device";
    /// the engine does not, because a fresh app has a fresh player.
    Future<void> restartApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      engine = FakeAudioEngine();
      await pumpApp(tester);
      // The restore runs off the library scan's completion, which lands a few
      // frames after the first build.
      await tester.pumpAndSettle();
    }

    testWidgets('the song that was playing is playing again', (tester) async {
      await playFirstTrack(tester);
      final played = library.allSongs.first;

      await restartApp(tester);

      // The complaint this exists for: reopening showed an empty player even
      // though something had been playing.
      expect(find.text('No music playing'), findsNothing);
      expect(player.currentSong?.id, played.id);
      expect(player.isPlaying, isTrue);
      expect(player.queueTitle, 'All Songs');
      expect(find.text('All Songs'), findsOneWidget);
      expect(find.textContaining('playing 1 of 4'), findsOneWidget);

      // And the whole queue is back, not just the track.
      final tiles = tester.widgetList<SongTile>(find.byType(SongTile)).toList();
      expect(tiles, hasLength(library.allSongs.length));
      expect(tiles.first.isCurrent, isTrue);
    });

    testWidgets('a paused session comes back paused, where it was left', (
      tester,
    ) async {
      await playFirstTrack(tester);
      await player.playIndex(2);
      engine.reportTimeline(
        position: const Duration(seconds: 45),
        duration: library.allSongs[2].duration,
      );
      // A pump, not a delay: inside testWidgets the clock only moves when the
      // test moves it, so a real delay here would never finish.
      await tester.pump();
      await player.togglePlayPause();

      await restartApp(tester);

      expect(player.currentSong?.id, library.allSongs[2].id);
      expect(player.position, const Duration(seconds: 45));
      // Silent audio the moment the app opens would be the wrong kind of
      // helpful.
      expect(player.isPlaying, isFalse);
      expect(find.textContaining('playing 3 of 4'), findsOneWidget);
    });

    testWidgets('shuffle and repeat come back as they were', (tester) async {
      await playFirstTrack(tester);
      await player.toggleShuffle();
      await player.toggleRepeat();

      await restartApp(tester);

      expect(player.isShuffle, isTrue);
      expect(player.repeatMode, RepeatBehaviour.all);
    });

    testWidgets('the mini player is back, so the session is one tap away', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        await playFirstTrack(tester);

        await restartApp(tester);

        expect(miniPlayerTap(), findsOneWidget);
        await tester.tap(miniPlayerTap());
        await tester.pumpAndSettle();
        expect(shell.currentIndex, kPlayerTabIndex);
      });
    });
  });

  // Opening the app, before the library has been read at all. This is the window
  // the user actually sees on launch, and it used to show an empty player: the
  // stored session could only be rebuilt once the media store had answered.
  group('opening the app', () {
    testWidgets('the last session is on screen while the scan is still running', (
      tester,
    ) async {
      final songs = libraryFixture();
      store.snapshot = PlaybackSnapshot.of(
        songs: songs,
        index: 1,
        position: const Duration(seconds: 30),
        wasPlaying: true,
        shuffle: false,
        repeatMode: RepeatBehaviour.off,
        volume: 0.8,
        queueTitle: 'All Songs',
        savedAt: DateTime(2026, 1, 1),
      );
      // The media store has not answered, and will not until this test says so.
      final gate = Completer<void>();
      media.scanGate = gate;

      await pumpApp(tester);

      expect(player.currentSong?.id, songs[1].id);
      expect(player.isPlaying, isTrue);
      expect(find.text('No music playing'), findsNothing);
      // The whole list is there too, not just the one track.
      expect(find.text('Aurora Fields'), findsWidgets);
      expect(find.textContaining('playing 2 of 4'), findsOneWidget);

      gate.complete();
      media.scanGate = null;
      await tester.pumpAndSettle();

      // The scan landing changes nothing about what is playing.
      expect(player.currentSong?.id, songs[1].id);
      expect(player.queue, hasLength(songs.length));

      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('a session of ids is restored by the scan that can resolve it', (
      tester,
    ) async {
      final songs = libraryFixture();
      // What an older build stored: ids only, so there is nothing to build a
      // queue out of until the media store has answered. Waiting is the only
      // option for it -- the point is that it still lands.
      store.snapshot = PlaybackSnapshot(
        songIds: [songs[1].id, songs[0].id],
        index: 0,
        position: const Duration(seconds: 12),
        wasPlaying: false,
        shuffle: false,
        repeatMode: RepeatBehaviour.off,
        volume: 0.8,
        savedAt: DateTime(2026, 1, 1),
      );
      final gate = Completer<void>();
      media.scanGate = gate;

      await pumpApp(tester);
      expect(player.currentSong, isNull);

      gate.complete();
      media.scanGate = null;
      await tester.pumpAndSettle();

      expect(player.currentSong?.id, songs[1].id);
      expect(player.position, const Duration(seconds: 12));
      expect(player.isPlaying, isFalse);
      expect(find.text('No music playing'), findsNothing);
    });
  });

  group('song actions', () {
    testWidgets('holding a row opens its action sheet', (tester) async {
      await playFirstTrack(tester);

      await tester.longPress(find.byType(SongTile).first);
      await tester.pumpAndSettle();

      expect(find.text('Play now'), findsOneWidget);
      expect(find.text('Add to playlist'), findsOneWidget);
      expect(find.text('Track details'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('adding to a playlist from the sheet files the track there', (
      tester,
    ) async {
      await playFirstTrack(tester);

      await tester.longPress(find.byType(SongTile).first);
      await tester.pumpAndSettle();

      // The playlist list is folded away until it is asked for.
      expect(find.text('Folk'), findsNothing);

      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Folk'), findsOneWidget);

      await tester.ensureVisible(find.text('Folk'));
      await tester.tap(find.text('Folk'));
      await tester.pumpAndSettle();

      // The tapped row is Neon Tide, tagged Ambient, so adding it to Folk is a
      // real change to the library rather than a no-op.
      expect(library.playlistContains('genre-folk', '1'), isTrue);

      // Let the confirmation snackbar's timer fire rather than leaving it
      // pending at teardown.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a playlist can be created straight from the sheet', (
      tester,
    ) async {
      await playFirstTrack(tester);

      await tester.longPress(find.byType(SongTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Road Trip');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      final created = library.userPlaylists.single;
      expect(created.name, 'Road Trip');
      expect(created.songIds, contains('1'));

      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('cover flight', () {
    testWidgets(
      'the player is revealed as the cover travels, not after it lands',
      (tester) async {
        await withSemantics(tester, () async {
          // Real covers: the flight only runs when it has pixels to carry.
          artwork = FakeArtworkService(artwork: testArtworkPng);
          await playFirstTrack(tester);
          final revealsBefore = ArtworkFlight.revealTick.value;

          await tester.tap(miniPlayerTap());
          await tester.pump();

          // The reveal is signalled on the very first frame and the tab has
          // already switched, so the player starts fading in from the same
          // instant the cover sets off.
          expect(ArtworkFlight.revealTick.value, greaterThan(revealsBefore));
          expect(shell.currentIndex, ShellTabs.player);

          // Mid-travel the cover is still in the air, and the player is only
          // part-way through its fade: the expansion and the reveal are running
          // together, which is the whole point of the flow.
          await tester.pump(const Duration(milliseconds: 120));
          expect(ArtworkFlight.inFlight, isTrue);
          final fades = tester.widgetList<FadeTransition>(
            find.ancestor(
              of: find.byTooltip('Collapse player'),
              matching: find.byType(FadeTransition),
            ),
          );
          expect(
            fades.any(
              (fade) => fade.opacity.value > 0.0 && fade.opacity.value < 1.0,
            ),
            isTrue,
            reason: 'the expanded player should be fading in mid-flight',
          );

          await tester.pump(const Duration(milliseconds: 80));
          expect(ArtworkFlight.inFlight, isTrue);

          await tester.pumpAndSettle();
          expect(ArtworkFlight.inFlight, isFalse);

          await tester.pump(const Duration(seconds: 16));
        });
      },
    );

    testWidgets(
      'pulling the player down collapses the cover back to the mini player',
      (tester) async {
        await withSemantics(tester, () async {
          artwork = FakeArtworkService(artwork: testArtworkPng);
          await playFirstTrack(tester);

          await tester.tap(miniPlayerTap());
          await tester.pumpAndSettle();
          expect(shell.currentIndex, ShellTabs.player);

          // Pull down from the top of the screen: the reverse of the open, so
          // the artwork should fly back down as the home tab returns.
          await tester.dragFrom(
            const Offset(180.0, 250.0),
            const Offset(0, 240),
          );
          await tester.pump();
          expect(ArtworkFlight.inFlight, isTrue);

          await tester.pumpAndSettle();
          expect(ArtworkFlight.inFlight, isFalse);
          expect(shell.currentIndex, ShellTabs.home);

          await tester.pump(const Duration(seconds: 16));
        });
      },
    );

    testWidgets(
      'the player tab is left visible for the ways back that do not fly the '
      'cover',
      (tester) async {
        await withSemantics(tester, () async {
          artwork = FakeArtworkService(artwork: testArtworkPng);
          await playFirstTrack(tester);

          await tester.tap(miniPlayerTap());
          await tester.pumpAndSettle();
          expect(revealFade(tester).opacity.value, 1.0);

          // Collapse from the top bar: the cover flies back down and the screen
          // fades out on the way, which is the one moment it should be
          // transparent.
          await tester.tap(find.byTooltip('Collapse player'));
          await tester.pumpAndSettle();
          expect(shell.currentIndex, ShellTabs.home);

          // Regression: the fade was left at zero after the collapse, and the
          // navigation bar switches tabs without starting a flight to fade it
          // back in -- so the player came up as a fully transparent screen, and
          // only the mini player (which *does* start a reveal) could open it.
          expect(
            revealFade(tester).opacity.value,
            1.0,
            reason: 'the collapsed player must not be left faded out',
          );

          await tester.tap(navIcon(CupertinoIcons.music_note_2));
          await tester.pumpAndSettle();
          expect(shell.currentIndex, ShellTabs.player);
          expect(revealFade(tester).opacity.value, 1.0);
          expect(find.byTooltip('Collapse player'), findsOneWidget);
        });
      },
    );

    testWidgets('the controls fade out with the cover, not after it', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        artwork = FakeArtworkService(artwork: testArtworkPng);
        await playFirstTrack(tester);

        await tester.tap(miniPlayerTap());
        await tester.pumpAndSettle();
        expect(revealFade(tester).opacity.value, 1.0);

        await tester.tap(find.byTooltip('Collapse player'));
        // A frame for the flight to be set up in, then half of the cover's
        // travel: by now it is most of the way back down to the mini player.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));

        expect(ArtworkFlight.inFlight, isTrue);
        // Regression: the chrome faded on a clock of its own, eased in reverse,
        // which left the controls at ~0.97 opacity here -- fully drawn, while the
        // cover they belong to had already shrunk away underneath them.
        expect(
          revealFade(tester).opacity.value,
          lessThan(0.5),
          reason: 'the controls should fade out as the cover shrinks',
        );

        await tester.pumpAndSettle();
        expect(shell.currentIndex, ShellTabs.home);
        await tester.pump(const Duration(seconds: 16));
      });
    });

    testWidgets(
      'the expanded cover is hidden while its own flight is in the air',
      (tester) async {
        await withSemantics(tester, () async {
          artwork = FakeArtworkService(artwork: testArtworkPng);
          await playFirstTrack(tester);

          await tester.tap(miniPlayerTap());
          // One frame for the tab switch, one with the overlay inserted.
          await tester.pump();
          await tester.pump();

          expect(ArtworkFlight.inFlight, isTrue);

          // The real cover is transparent, so the only cover on screen is the
          // flying copy. Without this the destination would sit at full size
          // behind the small cover growing toward it, and the flight would read
          // as two covers rather than one.
          final coverOpacity = find.ancestor(
            of: find.byKey(ArtworkFlight.expandedArt),
            matching: find.byWidgetPredicate((widget) => widget is Opacity),
          );
          bool hidden() => tester
              .widgetList<Opacity>(coverOpacity)
              .any((widget) => widget.opacity == 0.0);

          expect(hidden(), isTrue);

          // And it is back the moment the flight lands.
          await tester.pumpAndSettle();
          expect(hidden(), isFalse);

          await tester.pump(const Duration(seconds: 16));
        });
      },
    );
  });
}
