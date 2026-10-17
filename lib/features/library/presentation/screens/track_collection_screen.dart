import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/library/presentation/widgets/song_context_menu.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// What a [TrackCollectionScreen] is showing.
enum CollectionKind { playlist, album, artist }

/// Lists the tracks behind one playlist, album or artist.
///
/// All three are the same thing once resolved -- a list of songs that can be
/// played as a queue -- so they share a screen instead of three near-copies that
/// would drift apart. The caller resolves the songs and hands them over, which
/// also means this screen never has to guess what a missing id means.
class TrackCollectionScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Resolves the current songs. Called on every build so the list stays live
  /// when a track is added to or removed from the collection.
  final List<WavelySong> Function(LibraryController library) songsOf;

  /// Offered in the overflow menu. Null for collections that cannot be changed.
  final List<CollectionAction> Function(LibraryController library)? actionsOf;

  final CollectionKind kind;

  const TrackCollectionScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.songsOf,
    required this.kind,
    this.actionsOf,
  });

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    final playerCtrl = context.watch<PlayerController>();
    final songs = songsOf(libraryCtrl);

    return Scaffold(
      backgroundColor: Colors.black,
      // Plain black backdrop: the artwork wash is the expanded player's.
      body: SafeArea(
        child: songs.isEmpty
            ? Column(
                children: [
                  _Header(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    onBack: () => Navigator.of(context).maybePop(),
                    actions: actionsOf?.call(libraryCtrl) ?? const [],
                    songCount: songs.length,
                    totalDuration: libraryCtrl.totalDurationOf(songs),
                    onPlayAll: null,
                    onShuffleAll: null,
                  ),
                  Expanded(
                    child: _EmptyCollection(
                      icon: icon,
                      kind: kind,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              )
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      title: title,
                      subtitle: subtitle,
                      icon: icon,
                      onBack: () => Navigator.of(context).maybePop(),
                      actions: actionsOf?.call(libraryCtrl) ?? const [],
                      songCount: songs.length,
                      totalDuration: libraryCtrl.totalDurationOf(songs),
                      onPlayAll: () => playerCtrl.playTrack(
                        songs.first,
                        queueContext: songs,
                        queueTitle: title,
                      ),
                      onShuffleAll: songs.length < 2
                          ? null
                          : () => _shuffleAndPlay(context, playerCtrl, songs),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 32.0),
                    sliver: SliverFixedExtentList(
                      itemExtent: 68.0,
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = songs[index];
                          return SongTile(
                            key: ValueKey(song.id),
                            song: song,
                            isCurrent: playerCtrl.currentSong?.id == song.id,
                            isPlaying: playerCtrl.isPlaying,
                            onTap: () => playerCtrl.playTrack(
                              song,
                              queueContext: songs,
                              queueTitle: title,
                            ),
                            onLongPress: () => showSongContextMenu(
                              context,
                              song: song,
                              queueContext: songs,
                              queueTitle: title,
                            ),
                            onFavoriteToggle: () {
                              libraryCtrl.toggleFavorite(song.id);
                              playerCtrl.applyFavorite(
                                song.id,
                                isFavorite: !song.isFavorite,
                              );
                            },
                          );
                        },
                        childCount: songs.length,
                        addAutomaticKeepAlives: false,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Play the collection from a shuffled copy of the queue.
  ///
  /// The shuffled list is passed as the queue context rather than just flipping
  /// the player's shuffle flag: that way the order the user sees in the list is
  /// the order they hear, and pressing next walks the same sequence.
  Future<void> _shuffleAndPlay(
    BuildContext context,
    PlayerController playerCtrl,
    List<WavelySong> songs,
  ) async {
    final shuffled = List<WavelySong>.of(songs)..shuffle();
    if (shuffled.isEmpty) return;
    await playerCtrl.playTrack(
      shuffled.first,
      queueContext: shuffled,
      queueTitle: title,
    );
  }
}

/// A destructive or state-changing action offered on a collection header.
class CollectionAction {
  final IconData icon;
  final String label;

  /// Red for anything that removes something.
  final bool isDestructive;

  final VoidCallback onPressed;

  const CollectionAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
  });
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;
  final List<CollectionAction> actions;
  final int songCount;
  final Duration totalDuration;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
    required this.actions,
    required this.songCount,
    required this.totalDuration,
    this.onPlayAll,
    this.onShuffleAll,
  });

  @override
  Widget build(BuildContext context) {
    final runtime = totalDuration.inMinutes < 1
        ? 'under a minute'
        : '${totalDuration.inHours > 0 ? '${totalDuration.inHours} hr ' : ''}'
            '${totalDuration.inMinutes.remainder(60)} min';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  CupertinoIcons.chevron_left,
                  color: Colors.white,
                  size: 28.0,
                ),
                onPressed: onBack,
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 44.0,
                child: actions.isEmpty
                    ? null
                    : PopupMenuButton<int>(
                        icon: const Icon(
                          CupertinoIcons.ellipsis_circle,
                          color: Colors.white,
                        ),
                        color: const Color(0xFF1E1B4B),
                        onSelected: (index) => actions[index].onPressed(),
                        itemBuilder: (context) => [
                          for (var i = 0; i < actions.length; i++)
                            PopupMenuItem<int>(
                              value: i,
                              child: Row(
                                children: [
                                  Icon(
                                    actions[i].icon,
                                    size: 18.0,
                                    color: actions[i].isDestructive
                                        ? IOS27Colors.sunsetCoral
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 10.0),
                                  Text(
                                    actions[i].label,
                                    style: TextStyle(
                                      color: actions[i].isDestructive
                                          ? IOS27Colors.sunsetCoral
                                          : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Container(
                  width: 96.0,
                  height: 96.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18.0),
                    gradient: const LinearGradient(
                      colors: [
                        IOS27Colors.electricIndigo,
                        IOS27Colors.neonCyan,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 40.0),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20.0,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13.0,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        songCount == 1 ? '1 song • $runtime' : '$songCount songs • $runtime',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPlayAll,
                    icon: const Icon(CupertinoIcons.play_fill, size: 16.0),
                    label: const Text('Play'),
                  ),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onShuffleAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.shuffle, size: 16.0),
                    label: const Text('Shuffle'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  final IconData icon;
  final CollectionKind kind;
  final VoidCallback onBack;

  const _EmptyCollection({
    required this.icon,
    required this.kind,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (kind) {
      CollectionKind.playlist => (
          'This playlist has no tracks yet. Add one from the '
              'menu on any song.',
          'Go back and add a song',
        ),
      CollectionKind.album => (
          'None of the songs on this device report this album.',
          'Go back',
        ),
      CollectionKind.artist => (
          'None of the songs on this device are credited to this artist.',
          'Go back',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 44.0),
            const SizedBox(height: 12.0),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14.0,
              ),
            ),
            const SizedBox(height: 12.0),
            TextButton(onPressed: onBack, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
