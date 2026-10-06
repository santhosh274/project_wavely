import 'package:just_audio/just_audio.dart' show PlayerState, SequenceState;

import '../models/song_model.dart';
import 'audio_player_service.dart' show RepeatBehaviour;

/// The playback operations [PlayerController] needs from an audio backend.
///
/// Introduced as a seam so the player's own logic -- queue handling, track
/// changes, shuffle and repeat, play history -- can be exercised without a real
/// platform decoder. [AudioPlayerService] is the only production implementation;
/// tests supply a fake that reports whatever state they set up.
///
/// The interface is deliberately the *shape* of the service rather than a
/// re-declaration of just_audio: the controller thinks in songs and durations,
/// not in sources and processing states.
abstract interface class AudioEngine {
  /// The loaded playlist, in the order it was handed over.
  List<WavelySong> get queue;

  /// The track playing right now.
  WavelySong? get currentSong;

  /// Position of [currentSong] within [queue], or -1 when nothing is loaded.
  int get currentIndex;

  bool get hasNext;
  bool get hasPrevious;

  bool get isShuffleEnabled;
  RepeatBehaviour get repeatMode;

  /// Why the last open or play attempt failed, if it did.
  String? get errorMessage;

  Stream<PlayerState> get playerStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// Fires on every track change, including the queue rolling into the next song.
  Stream<SequenceState?> get sequenceStateStream;

  /// Load [songs] as a playlist and position it at [initialIndex].
  Future<void> setQueue(List<WavelySong> songs, {int initialIndex = 0});

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatBehaviour mode);
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  /// Make the track at [index] of [queue] current without reloading the queue.
  ///
  /// [index] addresses the queue in the order it was handed over, not the order
  /// it is being played in: implementations that reorder internally have to map
  /// it back themselves. Out of range indexes are ignored.
  Future<void> jumpToIndex(int index);

  /// Store an edited copy of a track, matched by id.
  void updateSong(WavelySong song);

  Future<void> dispose();
}
