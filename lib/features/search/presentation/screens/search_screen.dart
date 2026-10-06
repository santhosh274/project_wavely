import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// Free-text search over the whole library, plus exact genre chips.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Mirror a filter cleared from outside the text field.
  ///
  /// The chip row and the field are two views of one filter. Without this,
  /// tapping "All" would empty the results while the field still showed the old
  /// query, which reads as the filter having failed.
  void _syncFieldTo(LibraryController library) {
    if (_queryController.text == library.searchQuery) return;
    _queryController.value = TextEditingValue(
      text: library.searchQuery,
      selection: TextSelection.collapsed(offset: library.searchQuery.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    final playerCtrl = context.watch<PlayerController>();
    final results = libraryCtrl.songs;

    _syncFieldTo(libraryCtrl);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              // No top margin: the title continues the status inset directly.
              padding: EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 8.0),
              child: Text(
                'Search',
                style: TextStyle(
                  fontSize: 32.0,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GlassContainer(
                borderRadius: 100.0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 4.0,
                ),
                child: TextField(
                  controller: _queryController,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: libraryCtrl.setSearchQuery,
                  onSubmitted: (_) => _focusNode.unfocus(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Title, artist, album or genre',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    icon: const Icon(
                      CupertinoIcons.search,
                      color: IOS27Colors.neonCyan,
                    ),
                    suffixIcon: _queryController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              CupertinoIcons.clear_circled_solid,
                              color: Colors.white38,
                              size: 18.0,
                            ),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _focusNode.unfocus();
                              libraryCtrl.clearSearchQuery();
                              _queryController.clear();
                            },
                          ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            if (libraryCtrl.genres.isNotEmpty) ...[
              const SizedBox(height: 12.0),
              SizedBox(
                height: 36.0,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    _Chip(
                      label: 'All',
                      isActive: !libraryCtrl.hasActiveFilter,
                      onTap: libraryCtrl.clearSearchQuery,
                    ),
                    // Chips come from the genres really on this device, so the row
                    // is never a list of filters that match nothing.
                    for (final genre in libraryCtrl.genres)
                      _Chip(
                        label: genre,
                        isActive: libraryCtrl.selectedGenre == genre,
                        onTap: () => libraryCtrl.setGenreFilter(
                          libraryCtrl.selectedGenre == genre ? null : genre,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12.0),
            Expanded(
              child: _Results(
                results: results,
                playerCtrl: playerCtrl,
                libraryCtrl: libraryCtrl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final List<WavelySong> results;
  final PlayerController playerCtrl;
  final LibraryController libraryCtrl;

  const _Results({
    required this.results,
    required this.playerCtrl,
    required this.libraryCtrl,
  });

  /// Name the queue the home screen shows once results are played from.
  ///
  /// Says what was searched for, falling back to the genre when the list came
  /// from a chip, and to the plain result count when neither is set.
  String _queueTitle() {
    final query = libraryCtrl.searchQuery.trim();
    if (query.isNotEmpty) return 'Results for "$query"';

    final genre = libraryCtrl.selectedGenre;
    if (genre != null) return genre;

    return '${results.length} '
        '${results.length == 1 ? 'result' : 'results'}';
  }

  @override
  Widget build(BuildContext context) {
    if (libraryCtrl.needsPermission) {
      return _Message(
        icon: CupertinoIcons.lock_shield,
        title: 'Permission needed',
        message: libraryCtrl.statusMessage ?? 'This device will not share its '
            'media store until the music permission is granted.',
        actionLabel: 'Grant access',
        onAction: libraryCtrl.loadLibrary,
      );
    }

    if (results.isEmpty) {
      // "Nothing here" and "you have not searched yet" are different problems
      // with different fixes, so they get different messages.
      if (!libraryCtrl.hasActiveFilter) {
        return _Message(
          icon: CupertinoIcons.search,
          title: libraryCtrl.allSongs.isEmpty
              ? 'No songs to search'
              : 'Search ${libraryCtrl.allSongs.length} tracks',
          message: libraryCtrl.allSongs.isEmpty
              ? 'Put some music on this device, then rescan it from the profile '
                  'page.'
              : 'Type part of a title, artist, album or genre, or pick a genre '
                  'below the field.',
        );
      }

      return _Message(
        icon: CupertinoIcons.search,
        title: 'No matches',
        message: libraryCtrl.selectedGenre != null
            ? 'No tracks are tagged "${libraryCtrl.selectedGenre}".'
            : 'Nothing matches "${libraryCtrl.searchQuery}".',
        actionLabel: 'Clear search',
        onAction: libraryCtrl.clearSearchQuery,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${results.length} '
                  '${results.length == 1 ? 'match' : 'matches'}'
                  '${libraryCtrl.selectedGenre != null ? ' in ${libraryCtrl.selectedGenre}' : ''}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12.0,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => playerCtrl.playTrack(
                  results.first,
                  queueContext: results,
                  queueTitle: _queueTitle(),
                ),
                icon: const Icon(CupertinoIcons.play_fill, size: 14.0),
                label: const Text('Play results'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            padding: const EdgeInsets.only(bottom: 150.0),
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              final song = results[index];
              return SongTile(
                song: song,
                isCurrent: playerCtrl.currentSong?.id == song.id,
                isPlaying: playerCtrl.isPlaying,
                onTap: () => playerCtrl.playTrack(
                  song,
                  queueContext: results,
                  queueTitle: _queueTitle(),
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
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100.0),
            // A plain fill rather than glass: the selected state has to read
            // clearly against the blurred chips sitting next to it.
            color: isActive
                ? IOS27Colors.neonCyan
                : Colors.white.withValues(alpha: 0.1),
            border: Border.all(
              color: isActive
                  ? IOS27Colors.neonCyan
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18.0),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}