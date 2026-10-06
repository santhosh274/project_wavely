import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/audio_player_service.dart' show RepeatBehaviour;
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'package:wavely/core/widgets/ambient_background.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/widgets/glass_button.dart';
import 'package:wavely/core/widgets/glass_slider.dart';
import 'package:wavely/core/widgets/name_prompt_dialog.dart';
import 'package:wavely/core/utils/formatters.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/player/presentation/widgets/lyrics_sheet.dart';

/// The expanded player: the second tab of the shell.
///
/// This is a tab rather than a pushed route, so the back control switches back to
/// the home tab instead of popping. Everything on it drives the same
/// [PlayerController] the mini player does -- there is no second player state to
/// fall out of sync.
class NowPlayingExpandedScreen extends StatelessWidget {
  const NowPlayingExpandedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final song = playerCtrl.currentSong;

    // Apple Music style: the backdrop IS the cover, heavily blurred and
    // darkened -- not a palette swatch mixed toward black. A single dominant
    // colour can never reproduce a red cover with yellow text and blue light,
    // which is why the plum wash never looked like Starboy. The blurred bitmap
    // carries every hue in place, so backdrop and artwork match by
    // construction.
    final wash = IOS27Colors.liftedForGlow(playerCtrl.ambientPrimary);
    final fallback = Color.lerp(const Color(0xFF05060B), wash, 0.20)!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: song == null
          ? AmbientBackground(
              color: fallback,
              washPrimary: null,
              washSecondary: null,
              child: const SafeArea(child: _NothingPlaying()),
            )
          : _ArtworkBackdrop(
              song: song,
              fallback: fallback,
              child: const SafeArea(child: _Player()),
            ),
    );
  }
}

/// Full-bleed blurred copy of the playing cover behind the player.
///
/// Apple Music does not tint with a palette swatch: it stretches the artwork
/// itself across the screen, blurs it hard, and lays a dark scrim over it for
/// legibility. Every hue then sits in the backdrop exactly where it sits in
/// the cover, so the two cannot mismatch.
class _ArtworkBackdrop extends StatefulWidget {
  final WavelySong song;
  final Color fallback;
  final Widget child;

  const _ArtworkBackdrop({
    required this.song,
    required this.fallback,
    required this.child,
  });

  @override
  State<_ArtworkBackdrop> createState() => _ArtworkBackdropState();
}

class _ArtworkBackdropState extends State<_ArtworkBackdrop> {
  Future<Uint8List?>? _future;
  String? _songId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshIfNeeded();
  }

  @override
  void didUpdateWidget(_ArtworkBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshIfNeeded();
  }

  void _refreshIfNeeded() {
    // Cached per track: building a new future inside `build` refires the
    // lookup (and its setState) on every parent rebuild, which is a fetch
    // loop that keeps this whole screen rebuilding.
    if (_songId == widget.song.id) return;
    _songId = widget.song.id;
    // The service caches per album, so revisits resolve without re-querying
    // the media store.
    _future = ArtworkScope.of(context).artworkFor(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF05060B),
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            // Still loading, or the device has no cover: the flat tint keeps
            // the screen from flashing black in the meantime.
            return AmbientBackground(
              color: widget.fallback,
              washPrimary: null,
              washSecondary: null,
              child: widget.child,
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // Decoded tiny and scaled up: a 64px cover stretched full-screen
              // and blurred looks identical to a blurred 512px one, for a
              // fraction of the decode memory and GPU blur cost. Scaled past
              // the edges so the blur has no visible rim, repaint-isolated so
              // it only rebuilds on track change, never with the playhead.
              RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: 40.0,
                    sigmaY: 40.0,
                  ),
                  child: Transform.scale(
                    scale: 1.35,
                    child: Image.memory(
                      bytes,
                      cacheWidth: 64,
                      filterQuality: FilterQuality.low,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              // Bright legibility scrim: just enough black for white text
              // to read, lighter in the middle where the cover sits so the
              // artwork hues stay vivid Apple-Music style.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x7A000000),
                      Color(0x33000000),
                      Color(0x33000000),
                      Color(0x99000000),
                    ],
                    stops: [0.0, 0.35, 0.62, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player();

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final song = playerCtrl.currentSong!;

    final duration = playerCtrl.duration;

    // One seamless scroll: cover, title, completion line, transport,
    // volume/actions, then Up Next below the players. The transport used to
    // sit pinned outside the scroll while Up Next lived inside it, so the
    // queue scrolled between the progress line and its own controls --
    // the split the screenshot calls out. Everything now flows in one
    // column with no fixed seam mid-screen.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          _TopBar(song: song),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8.0),
                  _AlbumArt(song: song),
                  const SizedBox(height: 28.0),
                  _TrackHeading(song: song),
                  const SizedBox(height: 20.0),
                  // Only the seek bar and the time labels move with the
                  // playhead, so only they listen to the position ticks -- the
                  // rest of this column used to rebuild several times a
                  // second for a number that moves once a second.
                  _SeekSection(playerCtrl: playerCtrl, duration: duration),
                  const SizedBox(height: 16.0),
                  _TransportControls(),
                  _BottomActions(song: song),
                  const SizedBox(height: 28.0),
                  // What plays after this one, below the players instead of
                  // wedged between the progress line and the transport.
                  const _UpNext(),
                  // Clearance for the docked navigation bar below (the
                  // SafeArea above already clears the gesture bar itself).
                  const SizedBox(height: 76.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The seek bar and its time labels.
///
/// While the user is dragging, the thumb and the elapsed label follow the
/// finger and the playhead stream is ignored -- a seek committed on every drag
/// pixel made the bar fight the audio engine and the thumb jump backwards
/// between reports. The seek lands once, on release.
class _SeekSection extends StatefulWidget {
  final PlayerController playerCtrl;
  final Duration duration;

  const _SeekSection({required this.playerCtrl, required this.duration});

  @override
  State<_SeekSection> createState() => _SeekSectionState();
}

class _SeekSectionState extends State<_SeekSection> {
  /// The dragged fraction, or null when the bar is not being touched.
  double? _dragValue;

  Duration _shownPosition(Duration playhead) {
    final duration = widget.duration;
    final drag = _dragValue;
    if (drag == null || duration.inMilliseconds <= 0) return playhead;
    return Duration(milliseconds: (duration.inMilliseconds * drag).round());
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;

    return ValueListenableBuilder<Duration>(
      valueListenable: widget.playerCtrl.positionListenable,
      builder: (context, position, _) {
        final shown = _shownPosition(position);
        final fraction = duration.inMilliseconds > 0
            ? (shown.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Column(
          children: [
            GlassSlider(
              value: fraction,
              onChanged: (value) => setState(() => _dragValue = value),
              onChangeEnd: (value) {
                widget.playerCtrl.seek(
                  Duration(
                    milliseconds: (duration.inMilliseconds * value).round(),
                  ),
                );
                setState(() => _dragValue = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatDuration(shown),
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    formatDuration(duration),
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The queue that follows the playing track, shown below the controls.
///
/// Rows are deliberately plain tiles rather than [SongTile]: this section can
/// list dozens of tracks and the glass chrome is already paid for at the top
/// of the screen. Capped so a thousand-song queue does not build a thousand
/// rows inside a scroll view; the full list stays one tab away on Home.
/// How many upcoming rows the player previews before pointing at Home.
const int _upNextPreviewLimit = 20;

class _UpNext extends StatelessWidget {
  const _UpNext();

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final queue = playerCtrl.queue;
    final currentIndex = playerCtrl.currentIndex;

    final upcoming = <int>[
      for (var i = currentIndex + 1; i < queue.length; i++) i,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'UP NEXT',
                style: TextStyle(
                  fontSize: 11.0,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white54,
                ),
              ),
            ),
            Text(
              upcoming.isEmpty
                  ? 'End of queue'
                  : '${upcoming.length} ${upcoming.length == 1 ? 'track' : 'tracks'}',
              style: TextStyle(
                fontSize: 12.0,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6.0),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'Nothing queued after this one.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14.0,
              ),
            ),
          )
        else ...[
          for (final index in upcoming.take(_upNextPreviewLimit))
            _UpNextRow(
              song: queue[index],
              onTap: () => playerCtrl.playIndex(index),
            ),
          if (upcoming.length > _upNextPreviewLimit)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Text(
                'See all ${upcoming.length} on the Home tab.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13.0,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _UpNextRow extends StatelessWidget {
  final WavelySong song;
  final VoidCallback onTap;

  const _UpNextRow({required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          children: [
            ArtworkImage(
              song: song,
              size: 40.0,
              borderRadius: BorderRadius.circular(10.0),
              placeholder: const Icon(
                CupertinoIcons.music_note,
                color: Colors.white,
                size: 18.0,
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12.0,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              song.durationFormatted,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final WavelySong song;

  const _TopBar({required this.song});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            CupertinoIcons.chevron_down,
            color: Colors.white,
            size: 26.0,
          ),
          tooltip: 'Collapse player',
          // The player is a tab, so "back" means going to the home tab rather
          // than popping a route that was never pushed.
          onPressed: () => context.read<ShellController>().selectTab(0),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                'PLAYING FROM',
                style: TextStyle(
                  fontSize: 10.0,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Text(
                song.album.isEmpty ? 'Library' : song.album,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        _TrackMenu(song: song),
      ],
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final WavelySong song;

  const _AlbumArt({required this.song});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.78;

    return Hero(
      tag: 'album_art_${song.id}',
      // No shadow container at all: the previous BoxShadow (black 45%,
      // blur 40, offset down 18) painted a solid rounded-rect slab behind
      // the cover, and its downward offset is exactly the shade box hanging
      // below the artwork in the screenshot. The blurred backdrop already
      // gives depth, so the cover sits directly on it with no slab behind.
      child: RepaintBoundary(
        // Expand transition on every new song: the incoming cover grows from
        // 88% with a fade, so tapping a track visibly blooms into the full
        // player size instead of snapping. Keyed by track, one-shot per
        // change, settled otherwise.
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.center,
            children: [...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('cover_${song.id}'),
            child: ArtworkImage(
              song: song,
              size: size,
              borderRadius:
                  BorderRadius.circular(IOS27GlassTheme.radiusLarge),
              placeholder: const Center(
                child: Icon(
                  CupertinoIcons.music_note_2,
                  size: 72.0,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackHeading extends StatelessWidget {
  final WavelySong song;

  const _TrackHeading({required this.song});

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.read<LibraryController>();
    final playerCtrl = context.read<PlayerController>();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4.0),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16.0,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            song.isFavorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
            color: song.isFavorite
                ? IOS27Colors.sunsetCoral
                : Colors.white,
            size: 26.0,
          ),
          tooltip: song.isFavorite
              ? 'Remove from favourites'
              : 'Add to favourites',
          onPressed: () {
            // The library owns the flag, so write it there first and then mirror
            // it onto the loaded queue. Without the second step the heart would
            // snap back, because the player keeps its own copy of the track.
            final next = !song.isFavorite;
            libraryCtrl.toggleFavorite(song.id);
            playerCtrl.applyFavorite(song.id, isFavorite: next);
          },
        ),
      ],
    );
  }
}

class _TransportControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(
            CupertinoIcons.shuffle,
            color: playerCtrl.isShuffle
                ? Theme.of(context).colorScheme.primary
                : Colors.white.withValues(alpha: 0.5),
            // Soft drop shadow so bare glyphs stay legible on bright covers.
            shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 8.0),
            ],
          ),
          tooltip: playerCtrl.isShuffle ? 'Shuffle on' : 'Shuffle off',
          onPressed: () => playerCtrl.toggleShuffle(),
        ),
        GlassButton.icon(
          icon: CupertinoIcons.backward_fill,
          size: 52.0,
          iconSize: 24.0,
          onTap: () => playerCtrl.skipPrevious(),
        ),
        // Breathing primary: a touch larger while paused, settling back on
        // play -- the button visibly invites the tap that resumes the music.
        // The button is built inside `builder`, not passed as `child`: the
        // cached child of a TweenAnimationBuilder never rebuilds, which froze
        // the glyph on whatever it was at first paint (play) while only the
        // scale animated underneath it.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: 1.0,
            end: playerCtrl.isPlaying ? 1.0 : 1.12,
          ),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (context, scale, _) => Transform.scale(
            scale: scale,
            child: GlassButton.icon(
              icon: playerCtrl.isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              size: 72.0,
              iconSize: 34.0,
              isPrimary: true,
              accentColor: Theme.of(context).colorScheme.primary,
              onTap: () => playerCtrl.togglePlayPause(),
            ),
          ),
        ),
        GlassButton.icon(
          icon: CupertinoIcons.forward_fill,
          size: 52.0,
          iconSize: 24.0,
          onTap: () => playerCtrl.skipNext(),
        ),
        // Repeat has three states, so the icon itself has to distinguish
        // "repeat the queue" from "repeat this song".
        IconButton(
          icon: Icon(
            playerCtrl.repeatMode == RepeatBehaviour.one
                ? CupertinoIcons.repeat_1
                : CupertinoIcons.repeat,
            color: playerCtrl.repeatMode == RepeatBehaviour.off
                ? Colors.white.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.primary,
            shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 8.0),
            ],
          ),
          tooltip: switch (playerCtrl.repeatMode) {
            RepeatBehaviour.off => 'Repeat off',
            RepeatBehaviour.all => 'Repeat queue',
            RepeatBehaviour.one => 'Repeat this song',
          },
          onPressed: () => playerCtrl.toggleRepeat(),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  final WavelySong song;

  const _BottomActions({required this.song});

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();

    return Row(
      children: [
        IconButton(
          icon: const Icon(CupertinoIcons.text_quote, color: Colors.white),
          tooltip: 'Lyrics',
          onPressed: () {
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LyricsSheet(song: song),
            );
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.volume_down,
                  size: 18.0,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                Expanded(
                  child: GlassSlider(
                    value: playerCtrl.volume,
                    onChanged: playerCtrl.setVolume,
                  ),
                ),
                Icon(
                  CupertinoIcons.volume_up,
                  size: 18.0,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(CupertinoIcons.share, color: Colors.white),
          tooltip: 'Share',
          onPressed: () => _shareTrack(context, song),
        ),
      ],
    );
  }
}

/// The overflow menu for the current track.
class _TrackMenu extends StatelessWidget {
  final WavelySong song;

  const _TrackMenu({required this.song});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TrackMenuAction>(
      icon: const Icon(CupertinoIcons.ellipsis, color: Colors.white),
      tooltip: 'More actions',
      color: const Color(0xFF1C1C1E),
      onSelected: (action) => _handleMenuAction(context, action, song),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _TrackMenuAction.favourite,
          child: Row(
            children: [
              Icon(
                song.isFavorite
                    ? CupertinoIcons.heart_fill
                    : CupertinoIcons.heart,
                size: 18.0,
                color: song.isFavorite ? IOS27Colors.sunsetCoral : Colors.white,
              ),
              const SizedBox(width: 12.0),
              Text(
                song.isFavorite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TrackMenuAction.addToPlaylist,
          child: Row(
            children: [
              Icon(
                CupertinoIcons.text_badge_plus,
                size: 18.0,
                color: Colors.white,
              ),
              SizedBox(width: 12.0),
              Text('Add to playlist', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TrackMenuAction.queue,
          child: Row(
            children: [
              Icon(CupertinoIcons.list_bullet, size: 18.0, color: Colors.white),
              SizedBox(width: 12.0),
              Text('Playing next', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: _TrackMenuAction.details,
          child: Row(
            children: [
              Icon(
                CupertinoIcons.info_circle,
                size: 18.0,
                color: Colors.white,
              ),
              SizedBox(width: 12.0),
              Text('Track details', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _TrackMenuAction.copy,
          child: Row(
            children: [
              Icon(
                CupertinoIcons.doc_on_clipboard,
                size: 18.0,
                color: Colors.white,
              ),
              SizedBox(width: 12.0),
              Text('Copy details', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shown when nothing is loaded.
///
/// Offers the nearest real thing to do -- start something from the library --
/// rather than being a dead end.
class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying();

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final libraryCtrl = context.watch<LibraryController>();
    final message = playerCtrl.playbackError;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.music_note_2,
              size: 64.0,
              color: Colors.white24,
            ),
            const SizedBox(height: 16.0),
            Text(
              message ?? 'Nothing playing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16.0,
              ),
            ),
            if (libraryCtrl.allSongs.isNotEmpty) ...[
              const SizedBox(height: 20.0),
              FilledButton.icon(
                onPressed: () {
                  final first = libraryCtrl.allSongs.first;
                  playerCtrl.playTrack(
                    first,
                    queueContext: libraryCtrl.allSongs,
                    queueTitle: 'All Songs',
                  );
                },
                icon: const Icon(CupertinoIcons.play_fill, size: 16.0),
                label: const Text('Play from library'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Actions offered by the now playing overflow menu.
enum _TrackMenuAction { favourite, addToPlaylist, queue, details, copy }

Future<void> _handleMenuAction(
  BuildContext context,
  _TrackMenuAction action,
  WavelySong song,
) async {
  final libraryCtrl = context.read<LibraryController>();
  final playerCtrl = context.read<PlayerController>();
  final messenger = ScaffoldMessenger.of(context);

  switch (action) {
    case _TrackMenuAction.favourite:
      final next = !song.isFavorite;
      libraryCtrl.toggleFavorite(song.id);
      playerCtrl.applyFavorite(song.id, isFavorite: next);

    case _TrackMenuAction.addToPlaylist:
      await _showAddToPlaylist(context, song);

    case _TrackMenuAction.queue:
      await _showQueue(context, playerCtrl);

    case _TrackMenuAction.details:
      await _showTrackDetails(context, song);

    case _TrackMenuAction.copy:
      await Clipboard.setData(ClipboardData(text: describeSong(song)));
      messenger.showSnackBar(
        const SnackBar(content: Text('Track details copied.')),
      );
  }
}

Future<void> _showAddToPlaylist(BuildContext context, WavelySong song) async {
  final libraryCtrl = context.read<LibraryController>();
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 8.0),
            child: Text(
              'Add "${song.title}" to',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final playlist in libraryCtrl.playlists)
                  ListTile(
                    leading: Icon(
                      libraryCtrl.playlistContains(playlist.id, song.id)
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.music_note_2,
                      color: Colors.white,
                    ),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${playlist.songCount} '
                      'song${playlist.songCount == 1 ? '' : 's'}'
                      '${playlist.isAutoGenerated ? ' • auto' : ''}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    onTap: () {
                      final already =
                          libraryCtrl.playlistContains(playlist.id, song.id);
                      if (!already) {
                        libraryCtrl.addToPlaylist(
                          playlistId: playlist.id,
                          songId: song.id,
                        );
                      }
                      Navigator.of(sheetContext).pop();
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
                  ),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.add_circled,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'New playlist',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () async {
                    final name = await showNamePromptDialog(sheetContext);
                    if (name == null) return;
                    libraryCtrl.createPlaylistWithSong(name, song.id);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                    messenger.showSnackBar(
                      SnackBar(content: Text('Created "$name"')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
        ],
      ),
    ),
  );
}

/// The queue currently loaded in the player.
Future<void> _showQueue(BuildContext context, PlayerController playerCtrl) {
  final queue = playerCtrl.queue;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 20.0, 20.0, 8.0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Up next',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${queue.length} '
                    '${queue.length == 1 ? 'track' : 'tracks'}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13.0,
                    ),
                  ),
                ],
              ),
            ),
            if (queue.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Nothing queued.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: queue.length,
                  itemBuilder: (context, index) {
                    final queued = queue[index];
                    final isCurrent = queued.id == playerCtrl.currentSong?.id;

                    return ListTile(
                      leading: Icon(
                        isCurrent
                            ? CupertinoIcons.waveform
                            : CupertinoIcons.music_note,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white70,
                      ),
                      title: Text(
                        queued.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      subtitle: Text(
                        queued.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: Text(
                        queued.durationFormatted,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12.0,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        // The queue is already loaded, so this moves within it
                        // instead of reloading every source from disk.
                        playerCtrl.playIndex(index);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showTrackDetails(BuildContext context, WavelySong song) {
  final rows = <(String, String)>[
    ('Title', song.title),
    ('Artist', song.artist),
    if (song.album.isNotEmpty) ('Album', song.album),
    if (song.genre != null && song.genre!.isNotEmpty) ('Genre', song.genre!),
    if (song.trackNumber != null) ('Track', '${song.trackNumber}'),
    ('Duration', formatDuration(song.duration)),
    if (song.uri.isNotEmpty) ('Location', song.uri),
  ];

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: Text(
        song.title,
        style: const TextStyle(color: Colors.white, fontSize: 18.0),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in rows)
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

Future<void> _shareTrack(BuildContext context, WavelySong song) async {
  final messenger = ScaffoldMessenger.of(context);
  // Share is unavailable in some contexts (no share sheet, headless session).
  // Say so rather than appearing to do nothing.
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: describeSong(song),
        subject: song.title,
      ),
    );
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text('Sharing is not available here.')),
    );
  }
}

/// Plain-text summary of a track, used by share and copy.
String describeSong(WavelySong song) {
  final parts = <String>[song.title, song.artist];
  if (song.album.isNotEmpty && song.album != song.artist) {
    parts.add(song.album);
  }
  return parts.join(' - ');
}