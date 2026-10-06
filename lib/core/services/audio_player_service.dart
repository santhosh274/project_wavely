import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../models/song_model.dart';
import 'audio_engine.dart';
import 'media_item_mapper.dart';

/// Repeat behaviour, mirroring the three states of a typical repeat button.
///
/// Named `RepeatBehaviour` rather than `RepeatMode` because Flutter's
/// material.dart already exports a `RepeatMode` from repeating_animation_builder.
enum RepeatBehaviour { off, all, one }

/// Audio Player Service Wrapper around JustAudio.
///
/// The queue is loaded as one [ConcatenatingAudioSource] so that just_audio owns
/// the sequence. That is what makes a track roll into the next one, and what
/// gives the loop and shuffle buttons something to act on. Loading a single track
/// at a time with `setFilePath` left playback dead at the end of every song, with
/// the index tracked in two places that could drift apart.
///
/// Each source is tagged with a [MediaItem] (see `mediaItemFor`) because the
/// player is run through just_audio_background: that is what lets the music keep
/// playing with the app minimised and fills the media notification and lock
/// screen controls.
class AudioPlayerService implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  List<WavelySong> _queue = const [];
  Map<String, WavelySong> _byId = const {};
  WavelySong? _currentSong;
  String? _errorMessage;

  StreamSubscription<SequenceState?>? _sequenceSub;

  AudioPlayerService() {
    // The playing track is resolved from the sequence state's source tag rather
    // than from an index into _queue. Those differ as soon as shuffle is on,
    // because just_audio reorders playback internally while _queue keeps its
    // original order -- indexing _queue would then show the wrong song.
    _sequenceSub = _player.sequenceStateStream.listen((state) {
      final song = _songForTag(state?.currentSource?.tag);
      if (song != null) _currentSong = song;
    });
  }

  /// The song a source tag stands for, or null when the tag is unknown.
  WavelySong? _songForTag(Object? tag) {
    final id = songIdOf(tag);
    return id == null ? null : _byId[id];
  }

  AudioPlayer get player => _player;

  @override
  List<WavelySong> get queue => List.unmodifiable(_queue);
  @override
  String? get errorMessage => _errorMessage;

  /// The track actually playing right now, as reported by the player.
  @override
  WavelySong? get currentSong => _currentSong;

  /// Position of [currentSong] within [queue], or -1 when nothing is loaded.
  @override
  int get currentIndex => _currentSong == null
      ? -1
      : _queue.indexWhere((s) => s.id == _currentSong!.id);

  /// Whether just_audio currently knows of a following / preceding item.
  @override
  bool get hasNext => _player.hasNext;
  @override
  bool get hasPrevious => _player.hasPrevious;

  @override
  RepeatBehaviour get repeatMode => switch (_player.loopMode) {
    LoopMode.off => RepeatBehaviour.off,
    LoopMode.all => RepeatBehaviour.all,
    LoopMode.one => RepeatBehaviour.one,
  };

  @override
  bool get isShuffleEnabled => _player.shuffleModeEnabled;

  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  /// Fires whenever the sequence changes, including when a track finishes and
  /// playback advances on its own.
  @override
  Stream<SequenceState?> get sequenceStateStream => _player.sequenceStateStream;

  /// Load [songs] as a playlist and position it at [initialIndex].
  @override
  Future<void> setQueue(List<WavelySong> songs, {int initialIndex = 0}) async {
    _queue = List<WavelySong>.from(songs);
    _byId = {for (final song in _queue) song.id: song};
    _errorMessage = null;

    if (_queue.isEmpty) {
      _currentSong = null;
      await _player.stop();
      return;
    }

    final safeIndex = initialIndex.clamp(0, _queue.length - 1);

    // Lazy preparation keeps a large library from being buffered up front and
    // means one unreadable file only breaks that track rather than the queue.
    final playlist = ConcatenatingAudioSource(
      children: _queue.map(_toAudioSource).toList(),
      useLazyPreparation: true,
    );

    try {
      await _player.setAudioSource(
        playlist,
        initialIndex: safeIndex,
        initialPosition: Duration.zero,
      );
      // setAudioSource does not emit a sequence state on every platform, so seed
      // the current track from the requested index rather than trusting it to.
      _currentSong = _queue[safeIndex];
    } on Exception catch (e) {
      _errorMessage = 'Could not open this track: $e';
      _currentSong = null;
      await _player.stop();
    }
  }

  /// Resolve a song into something just_audio can open.
  ///
  /// Local device tracks prefer their `content://` URI: under Android 10+
  /// scoped storage a raw shared-storage path can be unreadable even when the
  /// media permission has been granted.
  ///
  /// Every source carries a [MediaItem] tag because that is what the background
  /// media notification reads its title and cover from.
  AudioSource _toAudioSource(WavelySong song) {
    final tag = mediaItemFor(song);

    final contentUri = song.contentUri;
    if (contentUri != null && contentUri.startsWith('content://')) {
      return AudioSource.uri(Uri.parse(contentUri), tag: tag);
    }

    final uri = song.uri;
    if (uri.startsWith('http://') ||
        uri.startsWith('https://') ||
        uri.startsWith('file://')) {
      return AudioSource.uri(Uri.parse(uri), tag: tag);
    }

    return AudioSource.file(uri, tag: tag);
  }

  /// Store an edited copy of a track, matched by id.
  ///
  /// Needed because the queue is held here and not in the controller, so a
  /// favourite toggled in the library would otherwise leave the player showing
  /// the stale copy.
  @override
  void updateSong(WavelySong song) {
    final index = _queue.indexWhere((s) => s.id == song.id);
    if (index < 0) return;
    _queue[index] = song;
    _byId[song.id] = song;
    if (_currentSong?.id == song.id) _currentSong = song;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> setShuffle(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);

  @override
  Future<void> setRepeatMode(RepeatBehaviour mode) async {
    final loopMode = switch (mode) {
      RepeatBehaviour.off => LoopMode.off,
      RepeatBehaviour.all => LoopMode.all,
      RepeatBehaviour.one => LoopMode.one,
    };
    await _player.setLoopMode(loopMode);
  }

  /// Advance one track.
  ///
  /// just_audio only advances within the sequence, so wrapping past the last
  /// item is handled here and only when the queue is set to repeat.
  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;

    if (_player.hasNext) {
      await _player.seekToNext();
      return;
    }

    if (repeatMode == RepeatBehaviour.all) {
      await _player.seek(Duration.zero, index: 0);
    }
  }

  /// Go back one track, or restart the current one when it is already playing.
  ///
  /// Matches the behaviour of physical transport controls: after a few seconds
  /// into a song, "previous" means "start this one over".
  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;

    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }

    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      return;
    }

    if (repeatMode == RepeatBehaviour.all) {
      await _player.seek(Duration.zero, index: _queue.length - 1);
    }
  }

  /// Make the track at [index] current, keeping the loaded source list.
  ///
  /// Reloading the queue would also work, but it throws away the shuffle order
  /// just_audio is holding and rebuilds every source, which is audible on a long
  /// queue. Shuffle reorders the sequence internally while [_queue] keeps the
  /// order the caller gave us, so the index has to be translated through the
  /// effective sequence before seeking.
  @override
  Future<void> jumpToIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final sequence = _player.sequenceState?.sequence;
    if (sequence != null) {
      final wanted = _queue[index].id;
      for (var i = 0; i < sequence.length; i++) {
        if (songIdOf(sequence[i].tag) == wanted) {
          await _player.seek(Duration.zero, index: i);
          return;
        }
      }
    }

    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> dispose() async {
    await _sequenceSub?.cancel();
    await _player.dispose();
  }
}
