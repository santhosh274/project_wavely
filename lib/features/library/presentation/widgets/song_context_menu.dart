import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavely/core/models/playlist_model.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/core/widgets/name_prompt_dialog.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// What a long-press on a song opens: the row's own action sheet.
///
/// A modal [showGeneralDialog] rather than a `showModalBottomSheet`, because the
/// sheet has to fly in with its own motion -- a fade, a small rise and a scale
/// from just-under-full -- instead of the platform's slide. The route owns that
/// animation, so it stays a single GPU-friendly transform for its short life
/// rather than a widget listening to a controller.
///
/// [queueContext] and [queueTitle] describe the list the row was part of, so
/// "play" keeps the surrounding list queued behind the tapped track the way
/// tapping the row does.
Future<void> showSongContextMenu(
  BuildContext context, {
  required WavelySong song,
  List<WavelySong>? queueContext,
  String? queueTitle,
}) {
  HapticFeedback.mediumImpact();

  return showGeneralDialog<void>(
    context: context,
    // Tapping the dimmed background dismisses, the way a native menu behaves.
    barrierDismissible: true,
    barrierLabel: 'Song actions',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: _menuTransition,
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: _SongContextMenu(
        song: song,
        queueContext: queueContext,
        queueTitle: queueTitle,
      ),
    ),
  );
}

/// The shared enter/exit motion for the menu.
///
/// Kept in one place so [showGeneralDialog] can hand it the route's animation:
/// the fade leads, the slide and scale follow on a decelerating curve, so the
/// panel reads as settling into place rather than appearing.
Widget _menuTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.0, 0.06),
        end: Offset.zero,
      ).animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
        child: child,
      ),
    ),
  );
}

class _SongContextMenu extends StatefulWidget {
  final WavelySong song;
  final List<WavelySong>? queueContext;
  final String? queueTitle;

  const _SongContextMenu({
    required this.song,
    this.queueContext,
    this.queueTitle,
  });

  @override
  State<_SongContextMenu> createState() => _SongContextMenuState();
}

class _SongContextMenuState extends State<_SongContextMenu> {
  /// Whether the "add to playlist" list is unfolded.
  bool _playlistsOpen = false;

  @override
  Widget build(BuildContext context) {
    // Watched so a playlist created from inside this sheet appears in the list
    // immediately, without the user having to reopen the menu.
    final library = context.watch<LibraryController>();
    final playlists = library.playlists;

    // A [showGeneralDialog] route paints no Material of its own, and every
    // [InkWell] below asserts on having one. A single transparent Material at
    // the root supplies that ink layer for the whole sheet -- one surface, so
    // the rows never each need their own.
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520.0,
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              borderRadius: 28.0,
              blurSigma: IOS27GlassTheme.blurHeavy,
              tintColor: Colors.black.withValues(alpha: 0.62),
              borderColor: Colors.white.withValues(alpha: 0.12),
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 40.0,
                  spreadRadius: -8.0,
                  offset: const Offset(0, 18),
                ),
              ],
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MenuHeader(song: widget.song),
                    const _MenuDivider(),
                    _MenuRow(
                      icon: CupertinoIcons.play_fill,
                      label: 'Play now',
                      onTap: () => _play(context),
                    ),
                    _MenuRow(
                      icon: widget.song.isFavorite
                          ? CupertinoIcons.heart_fill
                          : CupertinoIcons.heart,
                      iconColor: widget.song.isFavorite
                          ? IOS27Colors.sunsetCoral
                          : null,
                      label: widget.song.isFavorite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      onTap: () => _toggleFavorite(context),
                    ),
                    _MenuRow(
                      icon: CupertinoIcons.text_badge_plus,
                      label: 'Add to playlist',
                      // The chevron turns as the list unfolds rather than a second
                      // screen sliding in: one surface, one motion.
                      trailing: AnimatedRotation(
                        turns: _playlistsOpen ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          CupertinoIcons.chevron_down,
                          size: 16.0,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      onTap: () =>
                          setState(() => _playlistsOpen = !_playlistsOpen),
                    ),
                    // Unfolds in place, animated by its own size change, so the
                    // sheet grows to fit the playlists instead of jumping.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _playlistsOpen
                          ? _PlaylistList(
                              song: widget.song,
                              playlists: playlists,
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const _MenuDivider(),
                    _MenuRow(
                      icon: CupertinoIcons.info_circle,
                      label: 'Track details',
                      onTap: () => _showDetails(context),
                    ),
                    _MenuRow(
                      icon: CupertinoIcons.share,
                      label: 'Share',
                      onTap: () => _share(context),
                    ),
                    _MenuRow(
                      icon: CupertinoIcons.doc_on_clipboard,
                      label: 'Copy details',
                      onTap: () => _copy(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _play(BuildContext context) {
    final player = context.read<PlayerController>();
    Navigator.of(context).pop();
    player.playTrack(
      widget.song,
      queueContext: widget.queueContext,
      queueTitle: widget.queueTitle,
    );
  }

  void _toggleFavorite(BuildContext context) {
    final library = context.read<LibraryController>();
    final player = context.read<PlayerController>();
    final next = !widget.song.isFavorite;
    library.toggleFavorite(widget.song.id);
    // The queue holds its own copies, so the change is mirrored onto it too.
    player.applyFavorite(widget.song.id, isFavorite: next);
    Navigator.of(context).pop();
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await SharePlus.instance.share(
        ShareParams(text: _describe(widget.song), subject: widget.song.title),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sharing is not available here.')),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _describe(widget.song)));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Track details copied.')),
    );
  }

  void _showDetails(BuildContext context) {
    // Shown over the menu rather than after closing it: the dialog needs a live
    // context, and popping the menu first would leave only a defunct one.
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          widget.song.title,
          style: const TextStyle(color: Colors.white, fontSize: 18.0),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value) in _detailRows(widget.song))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11.0,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.0,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// The playlists a track can be dropped into.
///
/// User playlists first, then the genre-generated ones, with what is already in
/// the playlist check-marked rather than hidden -- so the list doubles as "where
/// is this song already?" instead of only "where can it go?".
class _PlaylistList extends StatelessWidget {
  final WavelySong song;
  final List<WavelyPlaylist> playlists;

  const _PlaylistList({required this.song, required this.playlists});

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryController>();
    final messenger = ScaffoldMessenger.of(context);

    final owned = <WavelyPlaylist>[
      for (final playlist in playlists)
        if (!playlist.isAutoGenerated) playlist,
    ];
    final generated = <WavelyPlaylist>[
      for (final playlist in playlists)
        if (playlist.isAutoGenerated) playlist,
    ];

    Widget entry(WavelyPlaylist playlist) {
      final already = library.playlistContains(playlist.id, song.id);
      return _MenuRow(
        icon: already
            ? CupertinoIcons.check_mark_circled_solid
            : CupertinoIcons.music_note_2,
        iconColor: already ? IOS27Colors.neonCyan : null,
        label: playlist.name,
        subtitle:
            '${playlist.songCount} '
            'song${playlist.songCount == 1 ? '' : 's'}'
            '${playlist.isAutoGenerated ? ' • auto' : ''}',
        dense: true,
        onTap: () {
          if (!already) {
            library.addToPlaylist(playlistId: playlist.id, songId: song.id);
          }
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                already
                    ? 'Already in ${playlist.name}'
                    : 'Added to ${playlist.name}',
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (owned.isNotEmpty) ...[
          const _SubHeader('Your playlists'),
          for (final playlist in owned) entry(playlist),
        ],
        if (generated.isNotEmpty) ...[
          const _SubHeader('From genres'),
          for (final playlist in generated) entry(playlist),
        ],
        _MenuRow(
          icon: CupertinoIcons.add_circled,
          label: 'New playlist',
          dense: true,
          onTap: () async {
            final name = await showNamePromptDialog(context);
            if (name == null) return;
            library.createPlaylistWithSong(name, song.id);
            if (!context.mounted) return;
            Navigator.of(context).pop();
            messenger.showSnackBar(SnackBar(content: Text('Created "$name"')));
          },
        ),
        const SizedBox(height: 4.0),
      ],
    );
  }
}

class _MenuHeader extends StatelessWidget {
  final WavelySong song;

  const _MenuHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 10.0),
      child: Row(
        children: [
          ArtworkImage(
            song: song,
            size: 46.0,
            borderRadius: BorderRadius.circular(12.0),
            placeholder: const Icon(
              CupertinoIcons.music_note,
              color: Colors.white,
              size: 20.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${song.artist} • ${song.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ),
          Text(
            song.durationFormatted,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool dense;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          dense ? 34.0 : 18.0,
          dense ? 9.0 : 12.0,
          18.0,
          dense ? 9.0 : 12.0,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: dense ? 17.0 : 19.0,
              color: iconColor ?? Colors.white,
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dense ? 14.0 : 15.0,
                      fontWeight: dense ? FontWeight.w500 : FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1.0),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  final String label;

  const _SubHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34.0, 8.0, 18.0, 4.0),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 10.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1.0,
      thickness: 1.0,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

/// Plain-text summary of a track, used by share and copy.
String _describe(WavelySong song) {
  final parts = <String>[song.title, song.artist];
  if (song.album.isNotEmpty && song.album != song.artist) {
    parts.add(song.album);
  }
  return parts.join(' - ');
}

List<(String, String)> _detailRows(WavelySong song) => [
  ('Title', song.title),
  ('Artist', song.artist),
  if (song.album.isNotEmpty) ('Album', song.album),
  if (song.genre != null && song.genre!.isNotEmpty) ('Genre', song.genre!),
  if (song.trackNumber != null) ('Track', '${song.trackNumber}'),
  ('Duration', song.durationFormatted),
  if (song.uri.isNotEmpty) ('Location', song.uri),
];
