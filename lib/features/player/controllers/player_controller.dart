import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../../../core/models/song_model.dart';
import '../../../core/services/audio_engine.dart';
import '../../../core/services/audio_player_service.dart';
import '../../../core/services/artwork_service.dart';
import '../../../core/services/playback_state_store.dart';

import 'package:just_audio/just_audio.dart' show PlayerState, SequenceState;

/// Called with the id of each track as it becomes current, so the library can
/// keep a real play history. See [PlayerController.onTrackStarted].
typedef TrackStartedCallback = void Function(String songId);

/// State Controller for Audio Playback & Artwork Derived Colors
class PlayerController extends ChangeNotifier {
  final AudioEngine _audioService;

  /// Shared with [ArtworkImage] so the cover and the colours derived from it are
  /// only read from the media store once per album.
  final ArtworkService _artworkService;

  /// Notified whenever a different track becomes current.
  ///
  /// This fires for auto-advance too, not just explicit taps, so a history
  /// driven from it records what was actually heard. Injected rather than
  /// reached for through a provider because the player has no business knowing
  /// that a library exists.
  TrackStartedCallback? _onTrackStarted;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 0.8;
  bool _isShuffle = false;
  RepeatBehaviour _repeatMode = RepeatBehaviour.off;
  String? _songId;
  String? _queueTitle;

  /// Playhead updates, published separately from [notifyListeners].
  ///
  /// The position stream fires several times a second for the whole session,
  /// and announcing every tick through [notifyListeners] rebuilt *everything*
  /// watching the player -- the whole queue list, the mini player, the shell --
  /// many times a second just to move a slider. Only the playhead UI (the
  /// seek bar, the time labels, the mini player's progress line, lyric
  /// highlighting) listens here, via [positionListenable]; everything else
  /// rebuilds only when something meaningful changes.
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);

  /// The live playhead, for widgets that move with it every tick.
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  /// Palettes already extracted, keyed by album id.
  ///
  /// Quantizing a cover is the expensive half of the colour extraction, and a
  /// queue spends whole albums on the same cover -- caching by album means
  /// skipping back a track re-colours the screen instantly instead of decoding
  /// the same image again.
  final Map<int, PaletteGenerator> _paletteCache = <int, PaletteGenerator>{};

  /// A few dozen albums cover any queue the user can build in a session.
  static const int _maxPaletteEntries = 48;

  /// Where the session's playback is written so the next launch can pick it up.
  final PlaybackStateStore _stateStore;

  /// The position the store currently holds, used to keep the write rate down.
  Duration _persistedPosition = Duration.zero;

  /// Writes are chained rather than fired off, so two saves can never race each
  /// other to the same file.
  Future<void> _writeChain = Future<void>.value();

  /// Whether [restorePlayback] has already run for this launch.
  ///
  /// Restoring is a one-off: a later media scan must not cut into music that is
  /// already playing.
  bool _hasRestoredState = false;

  /// Set while a restore is in flight, so its own intermediate state -- a queue
  /// that has just been loaded, a playhead on its way back to the stored
  /// position -- cannot be written over the session being restored.
  bool _isRestoring = false;

  // Dynamic colors derived from album art
  Color _ambientPrimary = const Color(0xFF6366F1);
  Color _ambientSecondary = const Color(0xFF06B6D4);

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<SequenceState?>? _sequenceSub;

  PlayerController({
    TrackStartedCallback? onTrackStarted,
    AudioEngine? audioService,
    ArtworkService? artworkService,
    PlaybackStateStore? stateStore,
  }) : _audioService = audioService ?? AudioPlayerService(),
       _artworkService = artworkService ?? ArtworkService(),
       _stateStore = stateStore ?? FilePlaybackStateStore() {
    _onTrackStarted = onTrackStarted;
    _initListeners();
  }

  /// Register or replace the track-changed listener.
  ///
  /// The library controller is created after the player, so the wiring is done
  /// once both exist rather than in the player's constructor.
  set onTrackStarted(TrackStartedCallback? callback) =>
      _onTrackStarted = callback;

  AudioEngine get audioService => _audioService;

  /// The artwork cache backing the album cover widgets.
  ArtworkService get artworkService => _artworkService;

  /// The loaded playlist. Held by the service, which owns the queue, so that
  /// shuffle reordering and the current track can never disagree with it.
  List<WavelySong> get queue => _audioService.queue;

  int get currentIndex => _audioService.currentIndex;

  /// What the loaded queue came from -- the playlist, album or list the user
  /// started it from.
  ///
  /// The queue is shared, so this is what lets the home screen say *why* these
  /// songs are lined up instead of showing an anonymous list.
  String? get queueTitle => _queueTitle;

  WavelySong? get currentSong => _audioService.currentSong;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  bool get isShuffle => _isShuffle;
  RepeatBehaviour get repeatMode => _repeatMode;

  /// Set when the player could not open or play the current source.
  String? get playbackError => _audioService.errorMessage;

  bool get hasNext => _audioService.hasNext;
  bool get hasPrevious => _audioService.hasPrevious;

  Color get ambientPrimary => _ambientPrimary;
  Color get ambientSecondary => _ambientSecondary;

  void _initListeners() {
    _stateSub = _audioService.playerStateStream.listen((state) {
      // Guarded: this stream fires on every buffering/ready transition, and an
      // unconditional notify rebuilds the whole shell each time. Only announce
      // when something the UI shows actually changed.
      var changed = false;
      if (state.playing != _isPlaying) {
        _isPlaying = state.playing;
        changed = true;
      }

      // The player's own shuffle/loop state is authoritative, since it can be
      // changed from anywhere and just_audio reports it back to us.
      final shuffle = _audioService.isShuffleEnabled;
      final repeat = _audioService.repeatMode;
      if (shuffle != _isShuffle) {
        _isShuffle = shuffle;
        changed = true;
      }
      if (repeat != _repeatMode) {
        _repeatMode = repeat;
        changed = true;
      }

      if (changed) notifyListeners();
    });

    _posSub = _audioService.positionStream.listen((pos) {
      _position = pos;
      // Published to the narrow audience rather than through notifyListeners:
      // see [_positionNotifier].
      _positionNotifier.value = pos;
      _persistPositionIfMoved();
    });

    _durSub = _audioService.durationStream.listen((dur) {
      final next = dur ?? Duration.zero;
      if (next == _duration) return;
      _duration = next;
      notifyListeners();
    });

    // A track change resets the timeline and the derived artwork colours. This
    // is what fires when a song ends and the queue rolls into the next one,
    // which is why the now playing screen updates without anyone pressing next.
    _sequenceSub = _audioService.sequenceStateStream.listen((_) {
      final id = _audioService.currentSong?.id;
      if (id == _songId) return;

      _songId = id;
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _duration = Duration.zero;
      _extractAmbientColors();
      if (id != null) _onTrackStarted?.call(id);
      // The queue rolled on by itself, so the stored session is out of date.
      unawaited(_persist());
      notifyListeners();
    });
  }

  /// Play [song], optionally within a larger [queueContext] so that the rest of
  /// that list becomes the playlist.
  ///
  /// [queueTitle] names where the list came from; it is shown by the home screen
  /// as the heading above the queue.
  Future<void> playTrack(
    WavelySong song, {
    List<WavelySong>? queueContext,
    String? queueTitle,
  }) async {
    final list = queueContext ?? [song];
    final index = list.indexWhere((s) => s.id == song.id);

    await _audioService.setQueue(list, initialIndex: index >= 0 ? index : 0);
    _songId = _audioService.currentSong?.id;
    _queueTitle = queueTitle;

    // Make the slider reflect the volume the player is actually using, instead
    // of a default it was never told about.
    await _audioService.setVolume(_volume);

    await _audioService.play();
    await _extractAmbientColors();
    notifyListeners();
    await _persist();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      _isPlaying = false;
      await _audioService.pause();
    } else {
      _isPlaying = true;
      await _audioService.play();
    }
    notifyListeners();
    // Whether the app should come back playing is decided here, so it has to be
    // recorded at the moment it changes rather than on some later tick.
    await _persist();
  }

  Future<void> skipNext() => _audioService.skipToNext();

  Future<void> skipPrevious() => _audioService.skipToPrevious();

  /// Play the queue entry at [index].
  ///
  /// Moves inside the playlist that is already loaded rather than loading a new
  /// one, so tapping a row in the home queue keeps everything else queued behind
  /// it, shuffle order included, and does not re-read the media store.
  Future<void> playIndex(int index) async {
    if (index < 0 || index >= queue.length) return;

    await _audioService.jumpToIndex(index);
    // Jumping to a track is a request to hear it, so this resumes a paused
    // player as well as moving the current track along.
    _isPlaying = true;
    await _audioService.play();
    notifyListeners();
    await _persist();
  }

  Future<void> seek(Duration pos) {
    // Reflect the jump immediately rather than waiting for the stream to catch
    // up, or the slider visibly springs back before it moves on.
    _position = pos;
    _positionNotifier.value = pos;
    return _audioService.seek(pos);
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    await _audioService.setVolume(_volume);
    notifyListeners();
    // Not persisted here: the slider emits continuously, so this would rewrite
    // the whole snapshot on every pixel of a drag. It is picked up by the next
    // position update and by [flushState] instead.
  }

  /// Toggle shuffle.
  ///
  /// just_audio reorders the already-loaded playlist itself, so this takes
  /// effect straight away and keeps applying across track changes.
  Future<void> toggleShuffle() async {
    await _audioService.setShuffle(!_isShuffle);
    _isShuffle = _audioService.isShuffleEnabled;
    notifyListeners();
    await _persist();
  }

  /// Cycle repeat: off -> all -> one -> off.
  Future<void> toggleRepeat() async {
    final next = switch (_repeatMode) {
      RepeatBehaviour.off => RepeatBehaviour.all,
      RepeatBehaviour.all => RepeatBehaviour.one,
      RepeatBehaviour.one => RepeatBehaviour.off,
    };
    await setRepeatMode(next);
  }

  Future<void> setRepeatMode(RepeatBehaviour mode) async {
    await _audioService.setRepeatMode(mode);
    _repeatMode = _audioService.repeatMode;
    notifyListeners();
    await _persist();
  }

  /// Reflect a favourite toggle made in the library onto the loaded queue.
  ///
  /// The library owns its own song list, so without this the heart on the now
  /// playing screen would keep showing the value it had when the queue was
  /// loaded.
  void applyFavorite(String songId, {required bool isFavorite}) {
    final song = currentSong;
    if (song == null || song.id != songId) return;

    _audioService.updateSong(song.copyWith(isFavorite: isFavorite));
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Surviving a restart
  // ---------------------------------------------------------------------

  /// How far the playhead has to travel before the stored position is worth
  /// rewriting.
  ///
  /// Just_audio reports position several times a second, and the snapshot holds
  /// the whole queue, so saving every update would spend most of the battery on
  /// disk writes to keep a number a few seconds fresher.
  static const Duration _positionSaveInterval = Duration(seconds: 5);

  /// Put the session back the way the last launch left it.
  ///
  /// Called with the songs a fresh library scan found, because the stored
  /// session only holds ids: a track that has since been deleted, or that is
  /// simply not visible to the scan (the media permission was refused), is
  /// dropped and the rest of the queue keeps its order. Ids that survive are
  /// matched back to the current track by position in the queue, so resuming
  /// lands on the same song even if tracks before it went missing.
  ///
  /// Does nothing once a session is already loaded, so this cannot cut into
  /// music the user has started since the app opened.
  Future<void> restorePlayback({required List<WavelySong> songs}) async {
    if (_hasRestoredState) return;
    _hasRestoredState = true;

    if (_audioService.queue.isNotEmpty) return;

    final snapshot = await _stateStore.read();
    if (snapshot == null) return;

    final byId = <String, WavelySong>{for (final song in songs) song.id: song};
    final byOriginalIndex = <int, WavelySong>{};
    for (var i = 0; i < snapshot.songIds.length; i++) {
      final song = byId[snapshot.songIds[i]];
      if (song != null) byOriginalIndex[i] = song;
    }
    if (byOriginalIndex.isEmpty) return;

    final originalIndexes = byOriginalIndex.keys.toList()..sort();
    final queue = originalIndexes
        .map((index) => byOriginalIndex[index]!)
        .toList();
    final wanted = originalIndexes.indexOf(snapshot.index);
    final startIndex = wanted >= 0 ? wanted : 0;

    // Held in locals for the whole restore. The player state listener re-reads
    // these from the engine every time the engine reports anything, and it does
    // so during the awaits below -- so reading the fields as they stand now
    // would apply whatever the last event left behind instead of what was
    // stored.
    final storedShuffle = snapshot.shuffle;
    final storedRepeat = snapshot.repeatMode;
    final storedVolume = snapshot.volume;
    final storedPosition = _clampToTrack(snapshot.position);

    _isRestoring = true;
    try {
      _queueTitle = snapshot.queueTitle;
      _isShuffle = storedShuffle;
      _repeatMode = storedRepeat;
      _volume = storedVolume;
      _persistedPosition = storedPosition;
      // Claimed before the queue is loaded. Loading it reports a track change,
      // and the handler for that resets the playhead, fires the play-history
      // callback and rewrites the stored session -- none of which should happen
      // for a session that is only being picked up again.
      _songId = queue[startIndex].id;

      // The modes go in before the queue is loaded, so the sequence is built
      // already shuffled and looped instead of being rearranged underneath the
      // first track change.
      await _audioService.setShuffle(storedShuffle);
      await _audioService.setRepeatMode(storedRepeat);
      await _audioService.setVolume(storedVolume);
      await _audioService.setQueue(queue, initialIndex: startIndex);
      await _audioService.seek(storedPosition);
      if (snapshot.wasPlaying) {
        _isPlaying = true;
        await _audioService.play();
      }

      // Read back after the load so it matches what the engine actually opened: a
      // source that failed to load leaves the player showing nothing rather than
      // a track that is not there.
      _songId = _audioService.currentSong?.id;
      _position = storedPosition;
      _positionNotifier.value = storedPosition;
    } finally {
      _isRestoring = false;
    }

    _useDefaultColors();
    notifyListeners();
    unawaited(_extractAmbientColors());
  }

  /// Write the session out right now, bypassing the position throttle.
  ///
  /// Called when the app is about to leave the foreground: that is the last
  /// moment a save can be guaranteed before Android may kill the process, and it
  /// is what makes closing the app from the recents switch lose nothing.
  Future<void> flushState() => _persist();

  /// Start warming the artwork cache for [songs] without waiting for it.
  ///
  /// Called with a fresh scan's songs so the covers the user is about to see
  /// are already cached before their rows build. Fire and forget: a slow media
  /// store must never hold the library in its loading state.
  void warmArtworkCache(List<WavelySong> songs) {
    unawaited(_artworkService.prefetchAlbums(songs));
  }

  /// Keep the stored position close to the playhead without writing on every
  /// position update.
  void _persistPositionIfMoved() {
    if ((_position - _persistedPosition).abs() < _positionSaveInterval) return;
    unawaited(_persist());
  }

  /// Save the current session.
  ///
  /// Awaits the write so a caller that is about to change something significant
  /// -- or leave the app -- can be sure the file is current when it returns.
  Future<void> _persist() {
    // Nothing has ever been played, so there is nothing to restore and no reason
    // to create the file. And nothing is written mid-restore, or the session
    // being loaded would be overwritten by the state it is being loaded from.
    if (_isRestoring || _audioService.queue.isEmpty) {
      return Future<void>.value();
    }

    final snapshot = PlaybackSnapshot(
      songIds: [for (final song in _audioService.queue) song.id],
      index: _audioService.currentIndex < 0 ? 0 : _audioService.currentIndex,
      position: _position,
      wasPlaying: _isPlaying,
      shuffle: _isShuffle,
      repeatMode: _repeatMode,
      volume: _volume,
      queueTitle: _queueTitle,
      savedAt: DateTime.now(),
    );
    _persistedPosition = snapshot.position;

    // Chained so a slow write cannot be overtaken by the next one and leave the
    // file holding the older of the two. The error handler keeps a failed write
    // from poisoning every save that follows it.
    _writeChain = _writeChain
        .then((_) => _stateStore.write(snapshot))
        .catchError((Object _) {});
    return _writeChain;
  }

  /// Keep a restored position inside the track it belongs to.
  ///
  /// A position past the end would make the player finish the track immediately
  /// on launch and move on, which reads as the restore having failed.
  Duration _clampToTrack(Duration position) {
    if (position <= Duration.zero) return Duration.zero;
    if (_duration > Duration.zero && position >= _duration) {
      final shortened = _duration - const Duration(seconds: 2);
      return shortened > Duration.zero ? shortened : Duration.zero;
    }
    return position;
  }

  /// Extracts dominant palette colors from current track artwork
  ///
  /// The bytes come from [ArtworkService] rather than being carried on the
  /// song, so the colours are real even for tracks the library scan never
  /// decoded an image for. Tracks with no cover on the device keep the default
  /// palette.
  ///
  /// The generator is handed a 64×64 target: quantizing a full-res cover and
  /// quantizing a thumbnail answer "what are this album's colours?" identically,
  /// and the thumbnail costs a fraction of the work. Results are cached per
  /// album, so the cost is paid once per album per session.
  Future<void> _extractAmbientColors() async {
    final song = currentSong;
    if (song == null) return;

    final songId = song.id;
    final albumId = song.albumId;

    final cached = albumId == null ? null : _paletteCache[albumId];
    if (cached != null) {
      _applyPalette(cached);
      return;
    }

    final bytes = song.artworkBytes ?? await _artworkService.artworkFor(song);
    if (bytes == null) {
      _useDefaultColors();
      return;
    }

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        size: const Size(64, 64),
      );
      // The queue may have moved on while the palette was being generated.
      if (currentSong?.id != songId) return;

      if (albumId != null) {
        _paletteCache[albumId] = palette;
        _evictPalettesIfNeeded();
      }
      _applyPalette(palette);
    } on Object {
      _useDefaultColors();
    }
  }

  void _applyPalette(PaletteGenerator palette) {
    final dominant = palette.dominantColor?.color ?? const Color(0xFF6366F1);
    // Falling back to the dominant rather than a fixed cyan keeps monochrome
    // covers from being paired with an unrelated accent colour.
    final secondary = palette.vibrantColor?.color ?? dominant;
    // Guarded: re-selecting the same album (or an identical palette) must not
    // rebuild the whole app through the theme watch in [WavelyApp].
    if (dominant == _ambientPrimary && secondary == _ambientSecondary) return;
    _ambientPrimary = dominant;
    _ambientSecondary = secondary;
    notifyListeners();
  }

  /// Drop the oldest palettes once the cache is over its limit.
  void _evictPalettesIfNeeded() {
    while (_paletteCache.length > _maxPaletteEntries) {
      _paletteCache.remove(_paletteCache.keys.first);
    }
  }

  void _useDefaultColors() {
    _ambientPrimary = const Color(0xFF6366F1);
    _ambientSecondary = const Color(0xFF06B6D4);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _sequenceSub?.cancel();
    _positionNotifier.dispose();
    // Fire and forget: ChangeNotifier.dispose is synchronous, and the player is
    // torn down asynchronously either way. Written on the way out so a teardown
    // cannot lose the session.
    unawaited(_persist());
    _audioService.dispose();
    super.dispose();
  }
}
