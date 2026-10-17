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

/// The transport actions a listening room has to be able to take over.
///
/// Deliberately coarse: the room does not care *what* was asked for, only that
/// the request came from this device's own controls rather than from the host.
enum PlayerIntent { togglePlayPause, playTrack, playIndex, next, previous, seek }

/// Decides whether a transport call belongs to the room instead of this device.
///
/// Returning true consumes the call. A guest installs one so its own buttons
/// cannot fight the host: the room is the single writer, and a local tap would be
/// corrected away a moment later anyway, which reads as the controls being
/// broken.
typedef PlayerIntentInterceptor = bool Function(PlayerIntent intent);

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

  /// Consulted before every transport call. See [PlayerIntentInterceptor].
  PlayerIntentInterceptor? intentInterceptor;

  /// Called with the new position whenever the playhead is moved, so a room can
  /// tell its guests where the host jumped to.
  void Function(Duration position)? onSeeked;

  /// True while the room is driving playback. This is what lets the room past
  /// the very interceptor it installed.
  bool _applyingRemote = false;

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

  /// Width the cover is decoded to before its colours are quantized.
  ///
  /// Kept in step with the backdrop's `cacheWidth` so the two share one decoded
  /// image: a colour histogram over a 64px thumbnail is identical to one over
  /// the full cover but costs a thousandth of the work.
  static const double _paletteSampleSize = 64.0;

  /// Albums whose palette is being extracted right now.
  ///
  /// A track change and the explicit play that follows it both ask for the same
  /// album's colours a frame apart; without this, both would decode and quantize
  /// the cover.
  final _paletteInFlight = <int>{};

  /// Where the session's playback is written so the next launch can pick it up.
  final PlaybackStateStore _stateStore;

  /// A snapshot read before the player existed, so the stored session is in
  /// hand the moment it is asked to restore it.
  ///
  /// The read is file I/O, and it used to be the first thing a restore did --
  /// on the path that decides what the very first frame shows. Reading it on the
  /// startup path, alongside the audio-session setup, takes that wait off the
  /// restore.
  PlaybackSnapshot? _preloadedSnapshot;

  /// The position the store currently holds, used to keep the write rate down.
  Duration _persistedPosition = Duration.zero;

  /// Writes are chained rather than fired off, so two saves can never race each
  /// other to the same file.
  Future<void> _writeChain = Future<void>.value();

  /// Whether [restorePlayback] has already answered for this launch.
  ///
  /// Restoring is a one-off: a later media scan must not cut into music that is
  /// already playing.
  bool _hasRestoredState = false;

  /// The restore this launch is still running, if any.
  ///
  /// The two things that ask for it -- the app opening, and the media scan
  /// finishing -- can arrive moments apart, and only one of them may build the
  /// queue; the second waits for the first rather than racing it.
  Future<void>? _restoreInFlight;

  /// Set while a restore is in flight, so its own intermediate state -- a queue
  /// that has just been loaded, a playhead on its way back to the stored
  /// position -- cannot be written over the session being restored.
  bool _isRestoring = false;

  /// Track recent seek targets to prevent stale position stream reports from
  /// springing the slider back right after a seek.
  Duration? _lastSeekTarget;
  DateTime? _lastSeekTime;

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
    PlaybackSnapshot? preloadedSnapshot,
  }) : _audioService = audioService ?? AudioPlayerService(),
       _artworkService = artworkService ?? ArtworkService(),
       _stateStore = stateStore ?? FilePlaybackStateStore() {
    _preloadedSnapshot = preloadedSnapshot;
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
      final seekTarget = _lastSeekTarget;
      final seekTime = _lastSeekTime;
      if (seekTarget != null && seekTime != null) {
        final elapsed = DateTime.now().difference(seekTime);
        if (elapsed < const Duration(milliseconds: 500)) {
          final diff = (pos - seekTarget).abs();
          if (diff > const Duration(seconds: 2)) {
            // Ignore stale position stream updates right after seek.
            return;
          }
        }
        _lastSeekTarget = null;
        _lastSeekTime = null;
      }

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
    if (_intercepted(PlayerIntent.playTrack)) return;

    final list = queueContext ?? [song];
    final index = list.indexWhere((s) => s.id == song.id);

    final start = index >= 0 ? index : 0;
    await _audioService.setQueue(list, initialIndex: start);
    _songId = _audioService.currentSong?.id;
    _queueTitle = queueTitle;

    // Warm the covers for the list that was just queued, from the track being
    // played onwards. The library scan only warms the first few albums it finds
    // in scan order, which are rarely the ones actually played -- so without
    // this, the first visit to any album outside that head has to cross the
    // media store before its cover, and the palette taken from it, can appear.
    // Fire and forget: a slow media store must never delay the first frame of
    // playback. Only on an explicit queue load, never on background
    // auto-advance, where the queries would be spent with the screen off.
    _warmQueueArtwork(list, start);

    // Make the slider reflect the volume the player is actually using, instead
    // of a default it was never told about.
    await _audioService.setVolume(_volume);

    // Announced *before* the engine is asked to play, and without waiting on
    // it. just_audio's `play()` future does not complete until playback
    // *stops*, so awaiting it here used to hold this whole method -- the
    // transport glyph, the palette extraction and the state save -- until the
    // end of the song.
    _isPlaying = true;
    notifyListeners();
    unawaited(_audioService.play());
    unawaited(_extractAmbientColors());
    await _persist();
  }

  Future<void> togglePlayPause() async {
    if (_intercepted(PlayerIntent.togglePlayPause)) return;

    final next = !_isPlaying;
    _isPlaying = next;

    // Announced before the engine call, and play() is not awaited. The engine's
    // `play()` future does not complete until playback stops, so awaiting it
    // here meant the notify below never ran on a real device: the audio started
    // but the glyph stayed on "play" until the song ended or was paused. The
    // state stream could not cover for it either, because the field had already
    // been moved to the new value and the stream's own change check therefore
    // found nothing to announce.
    notifyListeners();

    if (next) {
      unawaited(_audioService.play());
    } else {
      // pause() completes as soon as the player has paused, so this one can be
      // waited on.
      await _audioService.pause();
    }

    // Whether the app should come back playing is decided here, so it has to be
    // recorded at the moment it changes rather than on some later tick.
    await _persist();
  }

  Future<void> skipNext() async {
    if (_intercepted(PlayerIntent.next)) return;
    await _audioService.skipToNext();
  }

  Future<void> skipPrevious() async {
    if (_intercepted(PlayerIntent.previous)) return;
    await _audioService.skipToPrevious();
  }

  /// Play the queue entry at [index].
  ///
  /// Moves inside the playlist that is already loaded rather than loading a new
  /// one, so tapping a row in the home queue keeps everything else queued behind
  /// it, shuffle order included, and does not re-read the media store.
  Future<void> playIndex(int index) async {
    if (_intercepted(PlayerIntent.playIndex)) return;
    if (index < 0 || index >= queue.length) return;

    await _audioService.jumpToIndex(index);
    // Jumping to a track is a request to hear it, so this resumes a paused
    // player as well as moving the current track along.
    _isPlaying = true;
    notifyListeners();
    // Not awaited for the same reason as [togglePlayPause]: the engine's
    // play() only completes when playback stops.
    unawaited(_audioService.play());
    await _persist();
  }

  Future<void> seek(Duration pos) {
    if (_intercepted(PlayerIntent.seek)) return Future<void>.value();

    // Reflect the jump immediately rather than waiting for the stream to catch
    // up, or the slider visibly springs back before it moves on.
    _position = pos;
    _positionNotifier.value = pos;
    _lastSeekTarget = pos;
    _lastSeekTime = DateTime.now();
    // Announced only for a seek this device made. One the room applied is the
    // room's own news, and reporting it back would be a loop.
    if (!_applyingRemote) onSeeked?.call(pos);
    return _audioService.seek(pos);
  }

  /// Run [action] as the room, past [intentInterceptor].
  ///
  /// The room installs the interceptor to keep a guest's own controls from
  /// fighting the host, and then has to be able to drive playback itself. Rather
  /// than keep a second set of methods that would drift from the first, every
  /// action takes the same path and the interceptor is merely stood down for the
  /// duration.
  Future<void> applyRemote(Future<void> Function() action) async {
    _applyingRemote = true;
    try {
      await action();
    } finally {
      _applyingRemote = false;
    }
  }

  /// Whether a transport call is the room's business rather than this device's.
  bool _intercepted(PlayerIntent intent) =>
      !_applyingRemote && (intentInterceptor?.call(intent) ?? false);

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
  /// Called twice in a launch, and either call is enough. The first comes the
  /// moment the player exists, with no arguments: the stored session carries the
  /// queue itself, so the last song and the list around it are on screen as soon
  /// as the app has opened, instead of after the media store has been read. The
  /// second comes when a scan finishes and hands over the library, and is then
  /// only a chance to refresh the queue's copies of its tracks from it.
  ///
  /// A session written by an older build holds ids only, and there is nothing to
  /// build a queue out of until the library has been read: that call is the one
  /// that answers for it, matching the ids against the songs the scan found. A
  /// track that has since been deleted, or that the scan cannot see (the media
  /// permission was refused), is dropped and the rest of the queue keeps its
  /// order, so resuming still lands on the stored song even if tracks before it
  /// went missing.
  ///
  /// Does nothing once a session is already loaded, so a later scan cannot cut
  /// into music the user has started since the app opened.
  Future<void> restorePlayback({List<WavelySong>? songs}) {
    // Waits rather than returning, and then asks again: the scan's call is the
    // one that finds out whether the restore it interrupted left anything for
    // it to do -- which is exactly the case for a session stored as ids, whose
    // first call had no library to match them against.
    final inFlight = _restoreInFlight;
    if (inFlight != null) {
      return inFlight.then((_) => restorePlayback(songs: songs));
    }

    if (_hasRestoredState) {
      if (songs != null) _refreshQueueFromLibrary(songs);
      return Future<void>.value();
    }

    // Cleared once it settles, so a restore that declined to claim the launch
    // -- a session of ids with no library yet -- leaves the way open for the
    // library's call to do it instead.
    final restore = _restore(songs);
    final tracked = restore.whenComplete(() => _restoreInFlight = null);
    _restoreInFlight = tracked;
    return tracked;
  }

  Future<void> _restore(List<WavelySong>? library) async {
    // The user has already started something between the two calls.
    if (_audioService.queue.isNotEmpty) {
      _hasRestoredState = true;
      return;
    }

    final snapshot = _preloadedSnapshot ?? await _stateStore.read();
    if (snapshot == null) {
      // Nothing has ever been played on this device: there is no session, and
      // waiting for the scan to say so again would be pointless.
      _hasRestoredState = true;
      return;
    }

    final queue = _resolvedQueue(snapshot, library);
    // A session of ids with no library to match them against yet. Deliberately
    // left unclaimed -- and the preloaded copy kept -- so the scan's call comes
    // back for it rather than reading the store over again.
    if (queue == null || queue.isEmpty) return;

    _preloadedSnapshot = null;
    _hasRestoredState = true;
    await _applySnapshot(snapshot, queue: queue);
  }

  /// The queue [snapshot] stands for, or null while it cannot be built yet.
  List<WavelySong>? _resolvedQueue(
    PlaybackSnapshot snapshot,
    List<WavelySong>? library,
  ) {
    // The stored songs are the queue: they were written by the player itself,
    // and they are what makes the restore independent of the media scan.
    if (snapshot.songs.isNotEmpty) return List.of(snapshot.songs);

    if (library == null || library.isEmpty) return null;

    final byId = <String, WavelySong>{for (final song in library) song.id: song};
    final matched = <WavelySong>[];
    for (final id in snapshot.songIds) {
      final song = byId[id];
      if (song != null) matched.add(song);
    }
    return matched.isEmpty ? null : matched;
  }

  /// Load a stored session and take the player to where it was.
  Future<void> _applySnapshot(
    PlaybackSnapshot snapshot, {
    required List<WavelySong> queue,
  }) async {
    // The stored index addresses the stored queue; the queue actually built can
    // be shorter (a session of ids whose tracks have since gone), so the current
    // track is located by id rather than assumed to still be at that offset.
    final wantedId = snapshot.index >= 0 && snapshot.index < snapshot.songIds.length
        ? snapshot.songIds[snapshot.index]
        : null;
    final located = wantedId == null
        ? -1
        : queue.indexWhere((song) => song.id == wantedId);
    final startIndex = located >= 0 ? located : 0;

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

      // Started but deliberately *not* awaited. The engine publishes the queue
      // and the current track synchronously, before it opens the source, so the
      // stored session can be announced now -- while the first track is still
      // being opened -- rather than after. That wait is the difference between
      // the last session being on screen at launch and "Nothing playing" for as
      // long as a media-store query takes.
      final loading = _audioService.setQueue(queue, initialIndex: startIndex);

      _songId = queue[startIndex].id;
      _position = storedPosition;
      _positionNotifier.value = storedPosition;
      _isPlaying = snapshot.wasPlaying;
      _useDefaultColors();
      notifyListeners();

      await loading;

      // The user may have started something else while the source was opening,
      // and laying the stored playhead over it would cut into what they chose.
      // Only a restore that still owns the player goes on to seek and play.
      if (_audioService.currentSong?.id != queue[startIndex].id) return;

      await _audioService.seek(storedPosition);
      if (snapshot.wasPlaying) {
        _isPlaying = true;
        // Not awaited: play() does not complete until playback stops, and the
        // restore still has to read the opened track back and announce the
        // session rather than waiting out the first song.
        unawaited(_audioService.play());
      }

      // Read back after the load so it matches what the engine actually opened: a
      // source that failed to load leaves the player showing nothing rather than
      // a track that is not there.
      _songId = _audioService.currentSong?.id;
      _position = storedPosition;
      _positionNotifier.value = storedPosition;
      _isPlaying = snapshot.wasPlaying;
      notifyListeners();
    } finally {
      _isRestoring = false;
    }

    // The covers are looked up after the session has been announced: the point
    // of the whole exercise is that the player draws the restored session now,
    // not after the artwork resolves.
    unawaited(_extractAmbientColors());
  }

  /// Point the live queue at the library's own copies of its tracks.
  ///
  /// A queue restored from disk holds the tracks as they were when the session
  /// was saved; the scan that has just finished is the better copy of them.
  /// Entries the scan did not return -- a track hidden by a library filter, on a
  /// device whose media permission was refused, or deleted since -- are left
  /// alone rather than dropped, because emptying part of a queue the user can see
  /// is a far worse outcome than playing a copy that is a few edits old.
  void _refreshQueueFromLibrary(List<WavelySong> library) {
    if (library.isEmpty || _audioService.queue.isEmpty) return;

    final byId = <String, WavelySong>{for (final song in library) song.id: song};
    var changed = false;
    for (final queued in _audioService.queue) {
      final fresh = byId[queued.id];
      if (fresh == null || fresh == queued) continue;
      _audioService.updateSong(fresh);
      changed = true;
    }

    if (changed) notifyListeners();
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

  /// Warm the covers of the queue, starting at [start].
  ///
  /// Reordered rather than handed over as-is, because [ArtworkService] warms
  /// front to back up to its own limit: passing the queue in its natural order
  /// would spend the whole budget on albums the user may never reach. Starting
  /// at the playing track means the covers that are one skip away are the ones
  /// already decoded.
  void _warmQueueArtwork(List<WavelySong> queue, int start) {
    unawaited(
      _artworkService.prefetchAlbums([
        for (var i = start; i < queue.length; i++) queue[i],
        for (var i = 0; i < start; i++) queue[i],
      ]),
    );
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

    final snapshot = PlaybackSnapshot.of(
      // The songs themselves, so the next launch can put the session back
      // without waiting for a media scan of the whole device.
      songs: _audioService.queue,
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
  /// The cover is decoded down to 64px before it is quantized, through a
  /// [ResizeImage] rather than by passing a target [Size]. Palette's `size:`
  /// only scales a *region*; a bare [MemoryImage] still decodes the cover at
  /// its full 512px and quantizes all ~262k pixels, on this isolate, and its
  /// `toByteData()` readback stalls the raster thread. That is the hitch that
  /// used to land exactly as the artwork and backdrop changed. At 64px the
  /// quantization is ~4k pixels and the readback a few kilobytes.
  ///
  /// The resize key is deliberately the same one the backdrop's
  /// `Image.memory(..., cacheWidth: 64)` uses, so both read one shared decode
  /// out of the image cache instead of decoding the same cover twice. Results
  /// are cached per album, so the cost is paid once per album per session.
  Future<void> _extractAmbientColors() async {
    final song = currentSong;
    if (song == null) return;

    final albumId = song.albumId;

    final cached = albumId == null ? null : _paletteCache[albumId];
    if (cached != null) {
      _applyPalette(cached);
      return;
    }

    // One extraction per album at a time: the sequence change and the explicit
    // play both ask for the new track's colours, and quantizing the same cover
    // twice is pure wasted work. A later request for the same album rides on the
    // cache the in-flight one fills in.
    if (albumId != null && !_paletteInFlight.add(albumId)) return;

    try {
      final bytes = song.artworkBytes ?? await _artworkService.artworkFor(song);
      if (bytes == null) {
        if (currentSong?.albumId == albumId) _useDefaultColors();
        return;
      }

      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(MemoryImage(bytes), width: _paletteSampleSize.round()),
        size: const Size(_paletteSampleSize, _paletteSampleSize),
      );

      if (albumId != null) {
        _paletteCache[albumId] = palette;
        _evictPalettesIfNeeded();
      }

      // Applied only while this album is still the one playing: the queue may
      // have rolled on, and colours from a track that is gone would tint the
      // screen wrong. Matching the *album* rather than the track keeps a track
      // change within one album from discarding colours that still apply.
      if (currentSong?.albumId != albumId) return;
      _applyPalette(palette);
    } on Object {
      if (currentSong?.albumId == albumId) _useDefaultColors();
    } finally {
      if (albumId != null) _paletteInFlight.remove(albumId);
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
