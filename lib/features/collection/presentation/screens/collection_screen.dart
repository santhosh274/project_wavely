import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/playlist_model.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/local_media_service.dart';
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/widgets/name_prompt_dialog.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/library/presentation/screens/track_collection_screen.dart';
import 'package:wavely/features/library/presentation/widgets/album_card.dart';
import 'package:wavely/features/library/presentation/widgets/artist_tile.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// The library tab: every way to get at the music on the device.
///
/// This tab absorbed the old Browse screen, so albums, artists and the
/// genre-generated playlists live here alongside the five original sections --
/// one tab for the whole library instead of two that overlapped. Every section
/// reads from real state: "Recently Played" is the actual play history rather
/// than the first N songs, and "Recently Added" relies on the media query's
/// DATE_ADDED ordering, so neither can quietly render the same tracks under a
/// different name.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<String> _titles = [
    'All Songs',
    'Albums',
    'Artists',
    'Favourites',
    'Recently Played',
    'Recently Added',
    'Playlists',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _titles.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();

    return Scaffold(
      backgroundColor: Colors.black,
      // Plain black backdrop: the artwork wash is the expanded player's.
      body: SafeArea(
          child: Column(
            children: [
              Padding(
                // No top margin: the title continues the status inset directly.
              padding: const EdgeInsets.fromLTRB(20.0, 4.0, 8.0, 0.0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Library',
                        style: TextStyle(
                          fontSize: 28.0,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.add, color: Colors.white),
                      tooltip: 'New playlist',
                      // showCreatePlaylistDialog is async, but the button only
                      // needs to open it: the dialog resolves the name itself.
                      onPressed: () => showCreatePlaylistDialog(context),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.refresh, color: Colors.white),
                      tooltip: 'Rescan device',
                      onPressed: libraryCtrl.isLoading
                          ? null
                          : () => libraryCtrl.loadLibrary(),
                    ),
                  ],
                ),
              ),
              // The gate is what the user needs to see before anything else:
              // without it every section below would just report
              // "nothing found", which reads as a broken app rather than a
              // blocked one. It came over from the removed Browse screen.
              Expanded(child: _buildBody(context, libraryCtrl)),
            ],
          ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LibraryController libraryCtrl) {
    if (libraryCtrl.isLoading) {
      return const Center(child: CupertinoActivityIndicator(color: Colors.white));
    }

    switch (libraryCtrl.status) {
      case LibraryLoadStatus.permissionDenied:
        return _MessageState(
          icon: CupertinoIcons.lock_shield,
          title: 'Permission needed',
          message: libraryCtrl.statusMessage,
          actionLabel: 'Grant access',
          onAction: libraryCtrl.loadLibrary,
        );
      case LibraryLoadStatus.error:
        return _MessageState(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: 'Could not read your library',
          message: libraryCtrl.statusMessage,
          actionLabel: 'Try again',
          onAction: libraryCtrl.loadLibrary,
        );
      case LibraryLoadStatus.empty:
      case LibraryLoadStatus.success:
        break;
    }

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          // Apple Music-style section tabs: plain labels, no underline.
          indicatorColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
          labelStyle: const TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
          dividerColor: Colors.transparent,
          tabs: _titles.map((title) => Tab(text: title)).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _AllSongsTab(),
              _AlbumsTab(),
              _ArtistsTab(),
              _FavouritesTab(),
              _RecentlyPlayedTab(),
              _RecentlyAddedTab(),
              _PlaylistsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens the "new playlist" dialog.
///
/// Shared so the header button, the empty playlists tab and the track menu all
/// create playlists the same way instead of three copies drifting apart.
Future<void> showCreatePlaylistDialog(BuildContext context) async {
  final libraryCtrl = context.read<LibraryController>();
  final name = await showNamePromptDialog(
    context,
    title: 'New Playlist',
    maxLength: 60,
  );

  if (name == null) return;
  libraryCtrl.createPlaylist(name);
}

class _AllSongsTab extends StatelessWidget {
  const _AllSongsTab();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    return _SongListTab(
      title: 'All Songs',
      subtitle: 'Every track on this device',
      songs: libraryCtrl.allSongs,
      emptyIcon: CupertinoIcons.music_note,
      emptyTitle: 'No songs on this device',
      emptyMessage: 'Add some music and rescan to find it.',
    );
  }
}

/// Every album the scan found, as a grid of covers.
class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();

  @override
  Widget build(BuildContext context) {
    final albums = context.watch<LibraryController>().albums;

    if (albums.isEmpty) {
      return const _EmptyMessage(
        icon: CupertinoIcons.music_albums,
        title: 'No albums',
        message: 'Albums will appear here once your library loads.',
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 1.0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      itemCount: albums.length,
      // Rows here hold no state worth keeping alive, and the grid builder's
      // default keep-alive wrappers cost a widget each per card.
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final album = albums[index];
        return AlbumCard(
          album: album,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TrackCollectionScreen(
                title: album.albumName,
                subtitle: album.artist,
                icon: CupertinoIcons.music_albums,
                kind: CollectionKind.album,
                songsOf: (library) => library.songsInAlbum(album.id),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Every artist the scan found.
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  @override
  Widget build(BuildContext context) {
    final artists = context.watch<LibraryController>().artists;

    if (artists.isEmpty) {
      return const _EmptyMessage(
        icon: CupertinoIcons.person_2,
        title: 'No artists',
        message: 'Artists will appear here once your library loads.',
      );
    }

    return ListView.builder(
      itemCount: artists.length,
      padding: const EdgeInsets.only(top: 8.0, bottom: 150.0),
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ArtistTile(
          artist: artist,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TrackCollectionScreen(
                title: artist.artistName,
                subtitle:
                    '${artist.numberOfAlbums} albums • ${artist.numberOfTracks} tracks',
                icon: CupertinoIcons.person_2_fill,
                kind: CollectionKind.artist,
                songsOf: (library) => library.songsByArtist(artist.id),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FavouritesTab extends StatelessWidget {
  const _FavouritesTab();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    return _SongListTab(
      title: 'Favourites',
      subtitle: 'Tracks you have hearted',
      songs: libraryCtrl.favorites,
      emptyIcon: CupertinoIcons.heart,
      emptyTitle: 'No favourites yet',
      emptyMessage: 'Tap the heart on any track to keep it here.',
    );
  }
}

class _RecentlyPlayedTab extends StatelessWidget {
  const _RecentlyPlayedTab();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    return _SongListTab(
      title: 'Recently Played',
      subtitle: 'Where you have been listening',
      songs: libraryCtrl.recentlyPlayed,
      emptyIcon: CupertinoIcons.clock,
      emptyTitle: 'Nothing played yet',
      // Deliberately not backfilled with library songs: showing tracks as
      // "recently played" that were never played would be a lie.
      emptyMessage: 'Start a track and it will show up here.',
    );
  }
}

class _RecentlyAddedTab extends StatelessWidget {
  const _RecentlyAddedTab();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    return _SongListTab(
      title: 'Recently Added',
      subtitle: 'Newest first',
      // The media query already sorts by DATE_ADDED descending.
      songs: libraryCtrl.recentlyAdded(),
      emptyIcon: CupertinoIcons.arrow_down_to_line,
      emptyTitle: 'Nothing added yet',
      emptyMessage: 'Tracks copied onto this device appear here first.',
    );
  }
}

/// A titled list of songs with a play-all header.
class _SongListTab extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<WavelySong> songs;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  const _SongListTab({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final libraryCtrl = context.watch<LibraryController>();

    if (songs.isEmpty) {
      return _EmptyMessage(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    final runtime = libraryCtrl.totalDurationOf(songs);

    return ListView.builder(
      itemCount: songs.length + 1,
      padding: const EdgeInsets.only(top: 12.0, bottom: 150.0),
      addAutomaticKeepAlives: false,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ListHeader(
            title: title,
            subtitle: subtitle,
            count: songs.length,
            runtime: runtime,
            onPlayAll: () => playerCtrl.playTrack(
              songs.first,
              queueContext: songs,
              queueTitle: title,
            ),
            onShuffleAll: songs.length < 2
                ? null
                : () async {
                    final shuffled = List<WavelySong>.of(songs)..shuffle();
                    if (shuffled.isEmpty) return;
                    await playerCtrl.playTrack(
                      shuffled.first,
                      queueContext: shuffled,
                      queueTitle: title,
                    );
                  },
          );
        }

        final song = songs[index - 1];
        return SongTile(
          song: song,
          isCurrent: playerCtrl.currentSong?.id == song.id,
          isPlaying: playerCtrl.isPlaying,
          onTap: () => playerCtrl.playTrack(
            song,
            queueContext: songs,
            queueTitle: title,
          ),
          onFavoriteToggle: () {
            libraryCtrl.toggleFavorite(song.id);
            playerCtrl.applyFavorite(song.id, isFavorite: !song.isFavorite);
          },
        );
      },
    );
  }
}

/// Playlists the user made, plus the genre playlists generated from the
/// device's own tags.
///
/// The generated ones moved over from the removed Browse screen. They are
/// read-only: they are rebuilt from the media store on every scan, so they
/// cannot be renamed, reordered or deleted, and pretending otherwise would
/// only last until the next rescan.
class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    final owned = libraryCtrl.userPlaylists;
    final generated = libraryCtrl.playlists
        .where((p) => p.isAutoGenerated)
        .toList();

    return ListView(
      padding: const EdgeInsets.only(top: 12.0, bottom: 150.0),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Text(
            owned.isEmpty
                ? 'Playlists you create live here.'
                : '${owned.length} '
                    '${owned.length == 1 ? 'playlist' : 'playlists'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13.0,
            ),
          ),
        ),
        const SizedBox(height: 12.0),
        if (owned.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: FilledButton.icon(
              onPressed: () => showCreatePlaylistDialog(context),
              icon: const Icon(CupertinoIcons.add, size: 16.0),
              label: const Text('New playlist'),
            ),
          )
        else
          for (final playlist in owned)
            _PlaylistRow(
              playlist: playlist,
              onTap: () => _openPlaylist(context, playlist),
              onDelete: () => _confirmDelete(context, libraryCtrl, playlist),
            ),
        if (generated.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 8.0),
            child: Text(
              'FROM YOUR LIBRARY',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          for (final playlist in generated)
            _PlaylistRow(
              playlist: playlist,
              onTap: () => _openPlaylist(context, playlist),
            ),
        ],
      ],
    );
  }

  void _openPlaylist(BuildContext context, WavelyPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackCollectionScreen(
          title: playlist.name,
          subtitle:
              playlist.isAutoGenerated ? 'Genre playlist' : 'Your playlist',
          icon: CupertinoIcons.music_note_list,
          kind: CollectionKind.playlist,
          songsOf: (library) => library.songsInPlaylist(playlist.id),
          actionsOf: (library) => [
            CollectionAction(
              icon: CupertinoIcons.play_fill,
              label: 'Play this playlist',
              onPressed: () {
                final songs = library.songsInPlaylist(playlist.id);
                if (songs.isEmpty) return;
                Navigator.of(context).pop();
                context.read<PlayerController>().playTrack(
                      songs.first,
                      queueContext: songs,
                      queueTitle: playlist.name,
                    );
              },
            ),
            // Only user playlists can be deleted from here; generated ones are
            // rebuilt on every scan, so their row carries no delete action.
            if (!playlist.isAutoGenerated)
              CollectionAction(
                icon: CupertinoIcons.trash,
                label: 'Delete playlist',
                isDestructive: true,
                onPressed: () {
                  if (library.deletePlaylist(playlist.id)) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LibraryController libraryCtrl,
    WavelyPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        title: const Text(
          'Delete playlist?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '"${playlist.name}" will be removed. The tracks stay on this device.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: IOS27Colors.sunsetCoral,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) libraryCtrl.deletePlaylist(playlist.id);
  }
}

class _PlaylistRow extends StatelessWidget {
  final WavelyPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PlaylistRow({
    required this.playlist,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.0),
          color: Colors.white.withValues(alpha: 0.08),
        ),
        child: Row(
          children: [
            Container(
              width: 48.0,
              height: 48.0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                gradient: const LinearGradient(
                  colors: [IOS27Colors.electricIndigo, IOS27Colors.glowingPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                CupertinoIcons.music_note_list,
                color: Colors.white,
                size: 22.0,
              ),
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15.0,
                    ),
                  ),
                  const SizedBox(height: 3.0),
                  Text(
                    '${playlist.isAutoGenerated ? 'auto • ' : ''}'
                    '${playlist.songCount == 1 ? '1 song' : '${playlist.songCount} songs'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.0,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: Icon(
                  CupertinoIcons.trash,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 20.0,
                ),
                tooltip: 'Delete playlist',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final Duration runtime;
  final VoidCallback onPlayAll;
  final VoidCallback? onShuffleAll;

  const _ListHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.runtime,
    required this.onPlayAll,
    this.onShuffleAll,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = runtime.inMinutes;
    final runtimeLabel = minutes < 1
        ? 'under a minute'
        : '${runtime.inHours > 0 ? '${runtime.inHours} hr ' : ''}'
            '${minutes.remainder(60)} min';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            '$count ${count == 1 ? 'song' : 'songs'} • $runtimeLabel • $subtitle',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.0,
            ),
          ),
          const SizedBox(height: 12.0),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlayAll,
                  icon: const Icon(CupertinoIcons.play_fill, size: 16.0),
                  label: const Text('Play all'),
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
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 44.0),
            const SizedBox(height: 14.0),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8.0),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The permission and error states, shown in place of the sections.
///
/// Both offer the nearest real way out -- re-requesting, or trying the scan
/// again -- rather than a dead end.
class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 44.0),
            const SizedBox(height: 16.0),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18.0,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8.0),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20.0),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
