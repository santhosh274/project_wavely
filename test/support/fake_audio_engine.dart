import 'dart:async';

import 'package:just_audio/just_audio.dart'
    show PlayerState, ProcessingState, SequenceState;
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/audio_engine.dart';
import 'package:wavely/core/services/audio_player_service.dart' show RepeatBehaviour;

/// An [AudioEngine] that reports whatever the test sets up.
///
/// just_audio needs a platform decoder, so the real service cannot be used to
/// exercise the controller's own behaviour -- which track is current, what the
/// queue holds, when the history should be recorded. This fake keeps that state in
/// plain Dart and emits on the same streams the controller listens to, so the
/// controller under test is the real one.
class FakeAudioEngine implements AudioEngine {
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _sequenceController = StreamController<SequenceState?>.broadcast();

  List<WavelySong> _queue = const [];
  WavelySong? _currentSong;

  @override
  List<WavelySong> get queue => List.unmodifiable(_queue);

  @override
  WavelySong? get currentSong => _currentSong;

  @override
  int get currentIndex =>
      _currentSong == null ? -1 : _queue.indexWhere((s) => s.id == _currentSong!.id);

  @override
  bool get hasNext => currentIndex >= 0 && currentIndex < _queue.length - 1;

  @override
  bool get hasPrevious => currentIndex > 0;

  @override
  bool isShuffleEnabled = false;

  @override
  RepeatBehaviour repeatMode = RepeatBehaviour.off;

  @override
  String? errorMessage;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<SequenceState?> get sequenceStateStream => _sequenceController.stream;

  /// Every queue the controller loaded, in order.
  final List<List<WavelySong>> setQueueCalls = [];

  /// Whether [setQueue] should stay open after publishing the queue.
  ///
  /// The real engine sets the queue and the current track synchronously and only
  /// then opens the source, so a restore can draw the session before that
  /// finishes. Holding the future open stands in for a slow open and lets a test
  /// assert the session was announced while the load was still pending.
  bool holdSetQueue = false;

  Completer<void>? _setQueueCompleter;

  /// Whether a [setQueue] future is still open, i.e. the source is still being
  /// opened.
  bool get isSetQueuePending => _setQueueCompleter != null;

  /// Let a held [setQueue] finish.
  void releaseSetQueue() {
    _setQueueCompleter?.complete();
    _setQueueCompleter = null;
  }

  @override
  Future<void> setQueue(List<WavelySong> songs, {int initialIndex = 0}) async {
    setQueueCalls.add(List.of(songs));
    _queue = List.of(songs);
    errorMessage = null;
    if (_queue.isEmpty) {
      _currentSong = null;
      return;
    }
    _currentSong = _queue[initialIndex.clamp(0, _queue.length - 1)];
    _sequenceController.add(null);

    if (holdSetQueue) {
      final completer = Completer<void>();
      _setQueueCompleter = completer;
      await completer.future;
    }
  }

  /// Whether [play] behaves like the real player, whose future stays open for
  /// as long as the music plays.
  ///
  /// just_audio's `play()` does not complete until playback stops, pauses or
  /// errors; a fake that returns instantly hides any code that wrongly awaits
  /// it. Turn this on for tests about what the controller announces while
  /// playing.
  bool playCompletesOnStop = false;

  Completer<void>? _playCompleter;

  /// Whether a [play] future is still open, i.e. the engine considers itself
  /// mid-song. Lets a test prove the controller did not wait for it.
  bool get isPlayPending => _playCompleter != null;

  @override
  Future<void> play() async {
    _playerStateController.add(
      PlayerState(true, ProcessingState.ready),
    );
    if (!playCompletesOnStop) return;
    final completer = Completer<void>();
    _playCompleter = completer;
    await completer.future;
  }

  @override
  Future<void> pause() async {
    _playerStateController.add(
      PlayerState(false, ProcessingState.ready),
    );
    _finishPlay();
  }

  @override
  Future<void> stop() async {
    _playerStateController.add(
      PlayerState(false, ProcessingState.idle),
    );
    _finishPlay();
  }

  /// Closes the open [play] future, the way the real player does when playback
  /// ends.
  void _finishPlay() {
    _playCompleter?.complete();
    _playCompleter = null;
  }

  /// Every seek asked for, in order. The room corrects a guest by seeking or by
  /// changing the rate, and a test has to be able to tell which of the two it
  /// chose.
  final List<Duration> seekCalls = [];

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {}

  /// The last rate asked for, so a room test can see the nudge it applied.
  double speed = 1.0;

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    isShuffleEnabled = enabled;
    _playerStateController.add(
      PlayerState(false, ProcessingState.idle),
    );
  }

  @override
  Future<void> setRepeatMode(RepeatBehaviour mode) async {
    repeatMode = mode;
    _playerStateController.add(
      PlayerState(false, ProcessingState.idle),
    );
  }

  @override
  Future<void> skipToNext() async {
    if (hasNext) await setQueue(_queue, initialIndex: currentIndex + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (hasPrevious) await setQueue(_queue, initialIndex: currentIndex - 1);
  }

  @override
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentSong = _queue[index];
    _sequenceController.add(null);
  }

  @override
  void updateSong(WavelySong song) {
    final index = _queue.indexWhere((s) => s.id == song.id);
    if (index < 0) return;
    _queue = List.of(_queue)..[index] = song;
    if (_currentSong?.id == song.id) _currentSong = song;
  }

  /// Move to [song] the way a finished track rolling into the next one would.
  ///
  /// Only the sequence event fires: that is what the controller uses to detect a
  /// track change, and it is the path that has to record play history.
  Future<void> advanceTo(WavelySong song) async {
    _currentSong = song;
    _sequenceController.add(null);
  }

  /// Report the position and length of the current track.
  void reportTimeline({required Duration position, required Duration duration}) {
    _durationController.add(duration);
    _positionController.add(position);
  }

  @override
  Future<void> dispose() async {
    await _playerStateController.close();
    await _positionController.close();
    await _durationController.close();
    await _sequenceController.close();
  }
}