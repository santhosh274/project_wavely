import 'package:wavely/core/services/playback_state_store.dart';

/// A [PlaybackStateStore] that lives in memory.
///
/// Stands in for the file on disk so the player's save-and-restore behaviour can
/// be tested directly -- including across a simulated restart, where the same
/// instance is handed to the next controller and its contents are what the new
/// launch has to pick up.
class MemoryPlaybackStateStore implements PlaybackStateStore {
  MemoryPlaybackStateStore([this.snapshot]);

  /// The stored session, i.e. what a launch would restore.
  PlaybackSnapshot? snapshot;

  /// How many times a snapshot was written, to check that saving is throttled
  /// rather than done on every playhead tick.
  int writes = 0;

  /// Set to make the next write throw, standing in for a device that cannot
  /// write its storage. Playback has to carry on regardless.
  Object? failWith;

  @override
  Future<PlaybackSnapshot?> read() async => snapshot;

  @override
  Future<void> write(PlaybackSnapshot next) async {
    writes++;
    final failure = failWith;
    if (failure != null) throw failure;
    snapshot = next;
  }

  @override
  Future<void> clear() async => snapshot = null;
}
