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
  }

  @override
  Future<void> play() async {
    _playerStateController.add(
      PlayerState(true, ProcessingState.ready),
    );
  }

  @override
  Future<void> pause() async {
    _playerStateController.add(
      PlayerState(false, ProcessingState.ready),
    );
  }

  @override
  Future<void> stop() async {
    _playerStateController.add(
      PlayerState(false, ProcessingState.idle),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {}

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