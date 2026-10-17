import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/library/presentation/widgets/song_context_menu.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// The home tab: the playlist the player is running on.
///
/// The queue is shared state owned by [PlayerController], so whatever list the
/// user started playback from -- the library, an album, a playlist, an artist or
/// a search -- this is that list, with the playing track marked. Tapping a row
/// moves the current track inside the queue rather than loading a new one, so the
/// list on screen keeps matching what will play next.
///
/// The mini player stays docked at the bottom as the handle to the full player.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final songs = playerCtrl.queue;

    // The mini player lives in the shell dock, not here, and the queue scrolls
    // *underneath* it: the clearance is padding at the end of the list rather
    // than an empty gap in the column, so the rows pass behind the glass dock
    // and the last track can still be scrolled clear of it. A blank strip below
    // the list would read as a black band behind the dock instead.
    final dockClearance = playerCtrl.currentSong != null ? 196.0 : 112.0;

    return Scaffold(
      backgroundColor: Colors.black,
      // Flat black: the artwork wash lives only on the expanded player. The
      // queue rows and the nav bar stay on plain black.
      body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _HomeHeader(
                title: playerCtrl.queueTitle ?? 'Now Playing',
                subtitle: songs.isEmpty
                    ? 'Nothing playing'
                    : '${songs.length} '
                          '${songs.length == 1 ? 'track' : 'tracks'} queued',
                playingLabel: _playingLabel(playerCtrl, songs.length),
                onShuffle: songs.length < 2
                    ? null
                    : () => _shuffleAndPlay(context),
              ),
              Expanded(
                child: songs.isEmpty
                    ? const _NothingPlaying()
                    : _QueueList(songs: songs, bottomPadding: dockClearance),
              ),
            ],
          ),
      ),
    );
  }

  /// `3 of 12`, or null when the current track is not in the queue.
  static String? _playingLabel(PlayerController playerCtrl, int count) {
    final index = playerCtrl.currentIndex;
    if (index < 0 || count == 0) return null;
    return '${index + 1} of $count';
  }

  /// Start the same list from a random track.
  ///
  /// The queue is replaced by the shuffled copy, so the home list reorders to
  /// match what is being played -- the same reason a playlist's own shuffle
  /// button hands the shuffled order over as the queue.
  Future<void> _shuffleAndPlay(BuildContext context) async {
    final playerCtrl = context.read<PlayerController>();
    final songs = playerCtrl.queue;
    if (songs.length < 2) return;

    final shuffled = List<WavelySong>.of(songs)..shuffle();
    await playerCtrl.playTrack(
      shuffled.first,
      queueContext: shuffled,
      queueTitle: playerCtrl.queueTitle,
    );
  }
}

/// Profile entry point plus a heading for the queue below it.
class _HomeHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  /// Position within the queue, e.g. `3 of 12`. Null when nothing is current.
  final String? playingLabel;

  /// Null when the queue is too short to shuffle.
  final VoidCallback? onShuffle;

  const _HomeHeader({
    required this.title,
    required this.subtitle,
    this.playingLabel,
    this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    // Flush against the status inset with no extra top margin: the header is
    // part of the same surface as the list, not a card floating above it.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 2.0, 12.0, 0.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              CupertinoIcons.person_crop_circle,
              color: Colors.white,
              size: 28.0,
            ),
            tooltip: 'Profile, settings and stats',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          const SizedBox(width: 4.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26.0,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  playingLabel == null
                      ? subtitle
                      : '$subtitle • playing $playingLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.0,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (onShuffle != null)
            TextButton.icon(
              onPressed: onShuffle,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(CupertinoIcons.shuffle, size: 16.0),
              label: const Text('Shuffle'),
            ),
        ],
      ),
    );
  }
}

/// Every song in the loaded queue, in the order it will be played.
class _QueueList extends StatelessWidget {
  final List<WavelySong> songs;

  /// Room at the end of the list for the floating dock, so the last row can be
  /// scrolled up out from behind it.
  final double bottomPadding;

  const _QueueList({required this.songs, required this.bottomPadding});

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final libraryCtrl = context.watch<LibraryController>();
    final currentIndex = playerCtrl.currentIndex;

    return ListView.builder(
      itemCount: songs.length,
      itemExtent: 68.0,
      padding: EdgeInsets.only(top: 6.0, bottom: bottomPadding + 24.0),
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final song = songs[index];

        return SongTile(
          // Keyed by song: reordering the queue (shuffle, jumps) moves the
          // row's element instead of rebuilding it, so the artwork keeps its
          // decoded state and never flashes its placeholder mid-list.
          key: ValueKey(song.id),
          song: song,
          isCurrent: index == currentIndex,
          isPlaying: playerCtrl.isPlaying,
          onTap: () => playerCtrl.playIndex(index),
          onLongPress: () => showSongContextMenu(
            context,
            song: song,
            queueContext: songs,
            queueTitle: playerCtrl.queueTitle,
          ),
          onFavoriteToggle: () {
            libraryCtrl.toggleFavorite(song.id);
            // The queue holds its own copies, so the library's toggle has to be
            // mirrored onto it or the heart on the row would be a lie.
            playerCtrl.applyFavorite(song.id, isFavorite: !song.isFavorite);
          },
        );
      },
    );
  }
}

/// Nothing is loaded yet.
///
/// Rather than a dead end, this plays whatever is first in the library -- the
/// same thing the expanded player offers.
class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final libraryCtrl = context.watch<LibraryController>();
    final songs = libraryCtrl.allSongs;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.music_note_2,
              size: 72.0,
              color: Colors.white24,
            ),
            const SizedBox(height: 16.0),
            Text(
              playerCtrl.playbackError ?? 'No music playing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 17.0,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              libraryCtrl.needsPermission
                  ? 'Allow access to the music on this device to start listening.'
                  : libraryCtrl.isLoading
                  ? 'Reading your library...'
                  : 'Pick a song and the whole list it belongs to shows up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13.0,
              ),
            ),
            if (songs.isNotEmpty && !libraryCtrl.isLoading) ...[
              const SizedBox(height: 20.0),
              FilledButton.icon(
                onPressed: () => playerCtrl.playTrack(
                  songs.first,
                  queueContext: songs,
                  queueTitle: 'All Songs',
                ),
                icon: const Icon(CupertinoIcons.play_fill, size: 16.0),
                label: const Text('Play from library'),
              ),
            ] else if (libraryCtrl.needsPermission) ...[
              const SizedBox(height: 20.0),
              FilledButton.icon(
                onPressed: libraryCtrl.loadLibrary,
                icon: const Icon(CupertinoIcons.lock_open, size: 16.0),
                label: const Text('Grant access'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
