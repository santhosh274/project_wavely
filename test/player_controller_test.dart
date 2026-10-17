import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/audio_player_service.dart'
    show RepeatBehaviour;
import 'package:wavely/core/services/playback_state_store.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

import 'support/fake_artwork_service.dart';
import 'support/fake_audio_engine.dart';
import 'support/memory_playback_store.dart';

const _aurora = WavelySong(
  id: '10',
  title: 'Aurora Fields',
  artist: 'Real Artist',
  album: 'Real Album',
  duration: Duration(minutes: 3, seconds: 20),
  uri: 'content://media/external/audio/media/10',
  genre: 'Ambient',
);

const _neon = WavelySong(
  id: '11',
  title: 'Neon Tide',
  artist: 'Another Artist',
  album: 'Real Album',
  duration: Duration(minutes: 4, seconds: 5),
  uri: 'content://media/external/audio/media/11',
  genre: 'Ambient',
);

/// The same three tracks, but with album ids, so the artwork warming has
/// something to key on.
const _auroraAlbum = WavelySong(
  id: '20',
  title: 'Aurora Fields',
  artist: 'Real Artist',
  album: 'First Album',
  albumId: 1,
  duration: Duration(minutes: 3, seconds: 20),
  uri: 'content://media/external/audio/media/20',
);

const _neonAlbum = WavelySong(
  id: '21',
  title: 'Neon Tide',
  artist: 'Another Artist',
  album: 'Second Album',
  albumId: 2,
  duration: Duration(minutes: 4, seconds: 5),
  uri: 'content://media/external/audio/media/21',
);

const _thicketAlbum = WavelySong(
  id: '22',
  title: 'Thicket',
  artist: 'Third Artist',
  album: 'Third Album',
  albumId: 3,
  duration: Duration(minutes: 2, seconds: 40),
  uri: 'content://media/external/audio/media/22',
);

void main() {
  late FakeAudioEngine engine;
  late List<String> started;
  late MemoryPlaybackStateStore store;
  late FakeArtworkService artwork;
  late PlayerController controller;

  setUp(() {
    engine = FakeAudioEngine();
    started = [];
    store = MemoryPlaybackStateStore();
    // A device with no covers by default: these tests are about the player's
    // own state, not about image decoding. The fake also records which albums
    // were asked about, which is how the warming test below observes its order.
    artwork = FakeArtworkService();
    controller = PlayerController(
      audioService: engine,
      artworkService: artwork,
      onTrackStarted: started.add,
      stateStore: store,
    );
  });

  tearDown(() => controller.dispose());

  test('playing a track loads the surrounding list as the queue', () async {
    await controller.playTrack(_neon, queueContext: const [_aurora, _neon]);

    expect(engine.setQueueCalls.single, const [_aurora, _neon]);
    expect(controller.currentSong?.id, '11');
    expect(controller.queue, hasLength(2));
  });

  test(
    'the queue context, not just the tapped track, becomes the playlist',
    () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

      // Without this the next button would stop at the end of a single file.
      expect(controller.hasNext, isTrue);
      expect(controller.currentIndex, 0);
    },
  );

  test('a track playing with no context still loads just itself', () async {
    await controller.playTrack(_aurora);

    expect(controller.queue, const [_aurora]);
    expect(controller.hasNext, isFalse);
    expect(controller.currentIndex, 0);
  });

  test('play history records the first track of a queue', () async {
    await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

    expect(started, ['10']);
  });

  test(
    'play history also records auto-advance, not just explicit taps',
    () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
      expect(started, ['10']);

      // The queue rolling on its own, with nobody calling the controller.
      await engine.advanceTo(_neon);
      await Future<void>.delayed(Duration.zero);

      expect(started, ['10', '11']);
      expect(controller.currentSong?.id, '11');
    },
  );

  test('replaying a track does not report it as a second play', () async {
    await controller.playTrack(_aurora);
    await controller.playTrack(_aurora);

    // _songId gates the report, so the same track twice reports once.
    expect(started, ['10']);
  });

  test('shuffle toggles the backend and is read back from it', () async {
    expect(controller.isShuffle, isFalse);

    await controller.toggleShuffle();
    expect(controller.isShuffle, isTrue);

    await controller.toggleShuffle();
    expect(controller.isShuffle, isFalse);
  });

  test('repeat cycles off, all, one and back to off', () async {
    expect(controller.repeatMode, RepeatBehaviour.off);

    await controller.toggleRepeat();
    expect(controller.repeatMode, RepeatBehaviour.all);

    await controller.toggleRepeat();
    expect(controller.repeatMode, RepeatBehaviour.one);

    await controller.toggleRepeat();
    expect(controller.repeatMode, RepeatBehaviour.off);
  });

  test('volume is clamped to the range the backend accepts', () async {
    await controller.setVolume(1.4);
    expect(controller.volume, 1.0);

    await controller.setVolume(-0.5);
    expect(controller.volume, 0.0);
  });

  test('favouriting the playing track updates the loaded queue', () async {
    await controller.playTrack(_aurora);
    expect(controller.currentSong!.isFavorite, isFalse);

    controller.applyFavorite('10', isFavorite: true);

    // Otherwise the heart on the player would snap back to unhearted.
    expect(controller.currentSong!.isFavorite, isTrue);
    expect(controller.queue.single.isFavorite, isTrue);
  });

  test(
    'favouriting a track that is not playing leaves the queue alone',
    () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

      controller.applyFavorite('11', isFavorite: true);

      expect(controller.currentSong!.isFavorite, isFalse);
      expect(controller.queue.last.isFavorite, isFalse);
    },
  );

  test('the queue remembers where it was started from', () async {
    expect(controller.queueTitle, isNull);

    await controller.playTrack(
      _aurora,
      queueContext: const [_aurora, _neon],
      queueTitle: 'Road Trip',
    );

    // Home shows this above the queue, so it has to survive the load.
    expect(controller.queueTitle, 'Road Trip');
  });

  test(
    'playing within the queue moves the current track without reloading',
    () async {
      await controller.playTrack(
        _aurora,
        queueContext: const [_aurora, _neon],
        queueTitle: 'Road Trip',
      );
      final loads = engine.setQueueCalls.length;

      await controller.playIndex(1);

      expect(controller.currentSong?.id, '11');
      expect(controller.currentIndex, 1);
      // Loading again would drop the shuffle order and re-read every source.
      expect(engine.setQueueCalls, hasLength(loads));
      expect(controller.queue, const [_aurora, _neon]);
      expect(controller.queueTitle, 'Road Trip');
    },
  );

  test('playing within the queue resumes a paused player', () async {
    await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
    await controller.togglePlayPause();
    expect(controller.isPlaying, isFalse);

    await controller.playIndex(1);

    // Choosing a track from the queue is a request to hear it.
    expect(controller.isPlaying, isTrue);
  });

  group('the transport never waits on the engine', () {
    // just_audio's play() future stays open for as long as the music plays, so
    // anything that awaits it only runs once the song is over. The fake can be
    // asked to behave the same way; with the awaiting bug these tests hang and
    // fail on the test timeout rather than on an assertion -- which is exactly
    // what the glyph did on a device: the audio started, the icon stayed on
    // play until the track ended.

    test('resuming announces playing without waiting out the song', () async {
      engine.playCompletesOnStop = true;
      await controller.playTrack(_aurora, queueContext: const [_aurora]);
      await controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);

      var notified = 0;
      controller.addListener(() => notified++);
      await controller.togglePlayPause();

      expect(controller.isPlaying, isTrue);
      // The announcement has to happen while the song is playing, not after it:
      // the engine's play() future is deliberately still open here, exactly as
      // it is for the whole of a real song.
      expect(engine.isPlayPending, isTrue);
      expect(notified, greaterThan(0));
    });

    test('starting a track announces it without waiting out the song', () async {
      engine.playCompletesOnStop = true;

      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

      expect(controller.isPlaying, isTrue);
      expect(controller.currentSong?.id, '10');
    });

    test('choosing a queue row announces it without waiting out the song',
        () async {
      engine.playCompletesOnStop = true;
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
      await controller.togglePlayPause();
      expect(controller.isPlaying, isFalse);

      await controller.playIndex(1);

      expect(controller.isPlaying, isTrue);
      expect(controller.currentSong?.id, '11');
    });
  });

  test('an index outside the queue is ignored rather than crashing', () async {
    await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

    await controller.playIndex(7);
    await controller.playIndex(-1);

    expect(controller.currentSong?.id, '10');
    expect(controller.currentIndex, 0);
  });

  test('moving within the queue is recorded as played', () async {
    await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
    expect(started, ['10']);

    await controller.playIndex(1);
    await Future<void>.delayed(Duration.zero);

    expect(started, ['10', '11']);
  });

  group('warming the covers of a new queue', () {
    // The queue is warmed front to back up to a fixed limit, so the order it is
    // handed over in decides which covers are ready when the user skips ahead.
    test('starts at the track being played, not the head of the list', () async {
      await controller.playTrack(_neonAlbum, queueContext: const [
        _auroraAlbum,
        _neonAlbum,
        _thicketAlbum,
      ]);

      // The head album is all the natural order would have warmed first; the one
      // that matters is the album of the track that is actually playing.
      expect(artwork.requestedAlbumIds.first, _neonAlbum.albumId);
      expect(artwork.requestedAlbumIds, contains(_auroraAlbum.albumId));
      expect(artwork.requestedAlbumIds, contains(_thicketAlbum.albumId));
    });

    test('a single track with no queue still warms its own cover', () async {
      await controller.playTrack(_auroraAlbum);

      expect(artwork.requestedAlbumIds, contains(_auroraAlbum.albumId));
    });

    test('albums without a cover are simply skipped', () async {
      // _aurora and _neon carry no album id at all.
      await controller.playTrack(_neon, queueContext: const [_aurora, _neon]);

      expect(artwork.requestedAlbumIds, isEmpty);
    });
  });

  // The whole point of the store: what the app was playing has to still be there
  // on the next launch, otherwise reopening it shows an empty player and the
  // session looks lost.
  group('remembering the session', () {
    test(
      'playing a track writes out the queue, its place and its name',
      () async {
        await controller.playTrack(
          _neon,
          queueContext: const [_aurora, _neon],
          queueTitle: 'Road Trip',
        );

        final saved = store.snapshot!;
        expect(saved.songIds, ['10', '11']);
        expect(saved.index, 1);
        expect(saved.queueTitle, 'Road Trip');
        expect(saved.wasPlaying, isTrue);
      },
    );

    test('nothing is written before anything has been played', () async {
      await Future<void>.delayed(Duration.zero);

      expect(store.writes, 0);
      expect(store.snapshot, isNull);
    });

    test(
      'pausing is written down, so a reopen does not claim to play',
      () async {
        await controller.playTrack(
          _aurora,
          queueContext: const [_aurora, _neon],
        );
        await controller.togglePlayPause();

        expect(store.snapshot!.wasPlaying, isFalse);
        expect(store.snapshot!.songIds, ['10', '11']);
      },
    );

    test('moving through the queue updates the stored place', () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
      await controller.playIndex(1);

      expect(store.snapshot!.index, 1);
      expect(store.snapshot!.wasPlaying, isTrue);
    });

    test(
      'the queue rolling into the next song updates the stored place',
      () async {
        await controller.playTrack(
          _aurora,
          queueContext: const [_aurora, _neon],
        );

        await engine.advanceTo(_neon);
        await Future<void>.delayed(Duration.zero);

        expect(store.snapshot!.index, 1);
      },
    );

    test('shuffle and repeat are remembered', () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);

      await controller.toggleShuffle();
      await controller.toggleRepeat();

      expect(store.snapshot!.shuffle, isTrue);
      expect(store.snapshot!.repeatMode, RepeatBehaviour.all);
    });

    test(
      'the saved position follows the playhead, but not on every tick',
      () async {
        await controller.playTrack(
          _aurora,
          queueContext: const [_aurora, _neon],
        );
        final writesAtStart = store.writes;

        // A couple of seconds of playing is not worth a rewrite of the whole
        // snapshot.
        engine.reportTimeline(
          position: const Duration(seconds: 2),
          duration: _aurora.duration,
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.writes, writesAtStart);

        engine.reportTimeline(
          position: const Duration(seconds: 30),
          duration: _aurora.duration,
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.writes, writesAtStart + 1);
        expect(store.snapshot!.position, const Duration(seconds: 30));
      },
    );

    test('leaving the app writes the position even if it has not moved', () async {
      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
      engine.reportTimeline(
        position: const Duration(seconds: 8),
        duration: _aurora.duration,
      );
      await Future<void>.delayed(Duration.zero);

      // Only a few seconds from the last save, so the throttle would skip it --
      // which is exactly why the app lifecycle forces a final write.
      await controller.flushState();

      expect(store.snapshot!.position, const Duration(seconds: 8));
    });

    test('a storage failure never interrupts playback', () async {
      store.failWith = const FileSystemException('device is full');

      await controller.playTrack(_aurora, queueContext: const [_aurora, _neon]);
      await controller.flushState();

      expect(controller.currentSong?.id, '10');
      expect(controller.isPlaying, isTrue);

      // And it does not poison later saves either.
      store.failWith = null;
      await controller.togglePlayPause();
      expect(store.snapshot!.wasPlaying, isFalse);
    });
  });

  group('restoring the session', () {
    test('a stored session comes back as it was', () async {
      store.snapshot = _snapshotOf(
        songIds: const ['10', '11'],
        index: 1,
        position: const Duration(seconds: 30),
        wasPlaying: true,
        repeatMode: RepeatBehaviour.one,
        volume: 0.5,
        queueTitle: 'Road Trip',
      );

      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(controller.queue, const [_aurora, _neon]);
      expect(controller.currentSong?.id, '11');
      expect(controller.position, const Duration(seconds: 30));
      expect(controller.isPlaying, isTrue);
      expect(controller.repeatMode, RepeatBehaviour.one);
      expect(controller.volume, 0.5);
      expect(controller.queueTitle, 'Road Trip');
    });

    test(
      'the shuffle order is restored before the queue can roll on',
      () async {
        store.snapshot = _snapshotOf(
          songIds: const ['10', '11'],
          shuffle: true,
        );

        await controller.restorePlayback(songs: const [_aurora, _neon]);

        expect(controller.isShuffle, isTrue);
        expect(engine.isShuffleEnabled, isTrue);
      },
    );

    test('a session that was paused comes back paused', () async {
      store.snapshot = _snapshotOf(songIds: const ['10'], wasPlaying: false);

      await controller.restorePlayback(songs: const [_aurora]);

      expect(controller.currentSong?.id, '10');
      // Silent audio the moment the app opens is not what "it was playing" means.
      expect(controller.isPlaying, isFalse);
    });

    test(
      'tracks that are gone are dropped and the rest keep their order',
      () async {
        store.snapshot = _snapshotOf(
          songIds: const ['deleted', '10', 'also deleted'],
          index: 1,
        );

        await controller.restorePlayback(songs: const [_aurora, _neon]);

        expect(controller.queue, const [_aurora]);
        expect(controller.currentSong?.id, '10');
      },
    );

    test(
      'a queue that lost tracks up front still resumes on the same song',
      () async {
        store.snapshot = _snapshotOf(
          songIds: const ['gone', '10', '11'],
          // The second track in the stored queue, which is _neon.
          index: 2,
        );

        await controller.restorePlayback(songs: const [_aurora, _neon]);

        expect(controller.currentSong?.id, '11');
        expect(controller.currentIndex, 1);
      },
    );

    test('a stored queue with nothing left to play is ignored', () async {
      store.snapshot = _snapshotOf(songIds: const ['deleted', 'gone']);

      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(controller.queue, isEmpty);
      expect(engine.setQueueCalls, isEmpty);
      expect(controller.isPlaying, isFalse);
    });

    test('nothing stored means nothing restored', () async {
      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(engine.setQueueCalls, isEmpty);
      expect(controller.queue, isEmpty);
    });

    test(
      'a scan after playback started leaves the running queue alone',
      () async {
        await controller.playTrack(
          _aurora,
          queueContext: const [_aurora, _neon],
        );
        store.snapshot = _snapshotOf(songIds: const ['11'], index: 0);

        // A rescan, or a slow first scan landing after the user got going.
        await controller.restorePlayback(songs: const [_aurora, _neon]);

        expect(controller.queue, const [_aurora, _neon]);
        expect(controller.currentSong?.id, '10');
      },
    );

    test('a later scan does not cut into the restored session', () async {
      store.snapshot = _snapshotOf(
        songIds: const ['10', '11'],
        index: 1,
        wasPlaying: true,
      );
      await controller.restorePlayback(songs: const [_aurora, _neon]);

      // The user's rescan from settings: same songs, nothing should change.
      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(controller.currentSong?.id, '11');
      expect(controller.isPlaying, isTrue);
      expect(engine.setQueueCalls, hasLength(1));
    });

    test('a position past the end of the track does not skip the song on', () async {
      engine.reportTimeline(
        position: Duration.zero,
        duration: _aurora.duration,
      );
      store.snapshot = _snapshotOf(
        songIds: const ['10'],
        // Far beyond the track: the stored duration was from a different file.
        position: const Duration(hours: 3),
      );

      await controller.restorePlayback(songs: const [_aurora]);

      expect(controller.position, lessThan(_aurora.duration));
      expect(controller.currentSong?.id, '10');
    });

    test('restoring does not overwrite what is stored', () async {
      final stored = _snapshotOf(songIds: const ['10'], index: 0);
      store.snapshot = stored;

      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(store.snapshot, stored);
    });
  });

  // A session saved by this build carries the songs themselves, so opening the
  // app no longer has to wait for a media scan of the whole device before it can
  // show what was playing.
  group('restoring without waiting for the library', () {
    PlaybackSnapshot storedQueue({
      List<WavelySong> songs = const [_aurora, _neon],
      int index = 1,
      Duration position = const Duration(seconds: 30),
      String? queueTitle = 'Road Trip',
    }) => PlaybackSnapshot.of(
      songs: songs,
      index: index,
      position: position,
      wasPlaying: true,
      shuffle: false,
      repeatMode: RepeatBehaviour.off,
      volume: 0.8,
      queueTitle: queueTitle,
      savedAt: DateTime(2026, 1, 1),
    );

    test('the session is loaded with no library in sight', () async {
      store.snapshot = storedQueue();

      // The call the app makes the moment the player exists: no songs, because
      // the media store has not answered yet.
      await controller.restorePlayback();

      expect(controller.queue, const [_aurora, _neon]);
      expect(controller.currentSong?.id, '11');
      expect(controller.position, const Duration(seconds: 30));
      expect(controller.isPlaying, isTrue);
      expect(controller.queueTitle, 'Road Trip');
    });

    test('the session is announced before the source finishes opening',
        () async {
      store.snapshot = storedQueue();
      engine.holdSetQueue = true;

      // What the UI was told the moment the restore first reported a song.
      String? announcedSongId;
      var pendingWhenAnnounced = false;
      controller.addListener(() {
        if (announcedSongId != null || controller.currentSong == null) return;
        announcedSongId = controller.currentSong!.id;
        pendingWhenAnnounced = engine.isSetQueuePending;
      });

      final restore = controller.restorePlayback();
      await pumpEventQueue();

      // The last session is on screen -- queue and all -- while the first track
      // is still being opened, instead of after the file open and the decoder.
      expect(announcedSongId, '11');
      expect(controller.currentSong?.id, '11');
      expect(controller.queue, const [_aurora, _neon]);
      expect(controller.position, const Duration(seconds: 30));
      expect(pendingWhenAnnounced, isTrue);
      expect(engine.isSetQueuePending, isTrue);

      // And the restore still finishes once the source is open.
      engine.releaseSetQueue();
      await restore;
      expect(controller.currentSong?.id, '11');
      expect(controller.position, const Duration(seconds: 30));
    });

    test('a snapshot read at startup is used without reading the store again',
        () async {
      // What the startup path hands over: the file was already read while the
      // audio session was being set up, so the restore has it in hand.
      final preloaded = PlaybackSnapshot.of(
        songs: const [_aurora, _neon],
        index: 1,
        position: const Duration(seconds: 12),
        wasPlaying: true,
        shuffle: false,
        repeatMode: RepeatBehaviour.off,
        volume: 0.8,
        queueTitle: 'Road Trip',
        savedAt: DateTime(2026, 1, 1),
      );
      // A different, stale session on disk: the preloaded one has to win.
      store.snapshot = _snapshotOf(
        songIds: const ['10'],
        position: const Duration(seconds: 90),
        queueTitle: 'Stale',
      );

      final earlyEngine = FakeAudioEngine();
      final early = PlayerController(
        audioService: earlyEngine,
        artworkService: FakeArtworkService(),
        stateStore: store,
        preloadedSnapshot: preloaded,
      );
      addTearDown(early.dispose);

      await early.restorePlayback();

      expect(store.reads, 0);
      expect(early.queue, const [_aurora, _neon]);
      expect(early.currentSong?.id, '11');
      expect(early.position, const Duration(seconds: 12));
      expect(early.queueTitle, 'Road Trip');
    });

    test('the scan that lands afterwards adopts the library copies', () async {
      store.snapshot = storedQueue(songs: const [_aurora]);
      await controller.restorePlayback();

      // The library is the better copy of the same track -- favourite flags
      // included -- so the queue is refreshed from it rather than rebuilt.
      final favourited = _aurora.copyWith(isFavorite: true);
      await controller.restorePlayback(songs: [favourited, _neon]);

      expect(engine.setQueueCalls, hasLength(1));
      expect(controller.queue, hasLength(1));
      expect(controller.currentSong?.isFavorite, isTrue);
    });

    test('a scan cannot restart a session the user has moved on from',
        () async {
      store.snapshot = storedQueue();
      await controller.restorePlayback();

      await controller.playTrack(
        _thicketAlbum,
        queueContext: const [_thicketAlbum],
      );
      await controller.restorePlayback(songs: const [_aurora, _neon]);

      expect(controller.currentSong?.id, _thicketAlbum.id);
      expect(engine.setQueueCalls.last, const [_thicketAlbum]);
    });

    test('a queue of ids is left for the scan that can resolve it', () async {
      // A session written by an older build: ids only, so nothing can be built
      // until the library arrives. It must not be written off as "nothing to
      // restore" by the startup call.
      store.snapshot = _snapshotOf(songIds: const ['10', '11'], index: 1);

      await controller.restorePlayback();
      expect(controller.queue, isEmpty);

      await controller.restorePlayback(songs: const [_aurora, _neon]);
      expect(controller.currentSong?.id, '11');
    });

    test('an empty store is settled immediately', () async {
      await controller.restorePlayback();
      await controller.restorePlayback(songs: const [_aurora, _neon]);

      // Nothing has ever been played, and a later scan does not conjure a
      // session out of the library.
      expect(controller.queue, isEmpty);
      expect(engine.setQueueCalls, isEmpty);
    });

    test('the two calls racing each other still build one queue', () async {
      store.snapshot = storedQueue();

      // The scan landing while the stored session is still being read.
      await Future.wait([
        controller.restorePlayback(),
        controller.restorePlayback(songs: const [_aurora, _neon]),
      ]);

      expect(engine.setQueueCalls, hasLength(1));
      expect(controller.queue, hasLength(2));
    });
  });
}

/// A stored session, with the fields that vary per test left at sane defaults.
PlaybackSnapshot _snapshotOf({
  required List<String> songIds,
  int index = 0,
  Duration position = Duration.zero,
  bool wasPlaying = true,
  bool shuffle = false,
  RepeatBehaviour repeatMode = RepeatBehaviour.off,
  double volume = 0.8,
  String? queueTitle,
}) {
  return PlaybackSnapshot(
    songIds: songIds,
    index: index,
    position: position,
    wasPlaying: wasPlaying,
    shuffle: shuffle,
    repeatMode: repeatMode,
    volume: volume,
    queueTitle: queueTitle,
    savedAt: DateTime(2026, 1, 1),
  );
}
