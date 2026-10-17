import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/features/library/presentation/widgets/song_tile.dart'
    show kCurrentTrackColor;
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/player/presentation/widgets/artwork_flight.dart';

/// Glass Mini Player, floating above the navigation bar.
///
/// Apple-Music style: a rounded glass card holding the sharp cover fill behind
/// its blur, the track's identity, and the transport. Tapping anywhere lifts
/// the cover into the expanded player ([ArtworkFlight.expand]) while the tab
/// switches underneath it.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  @override
  void initState() {
    super.initState();
    // Report where the artwork sits once it has been laid out. The expanded
    // player hides this widget, so by the time its collapse control runs there
    // is nothing here to measure -- the flight aims at the rect recorded here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportArtRect());
  }

  void _reportArtRect() {
    final box = ArtworkFlight.miniArt.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    ArtworkFlight.rememberMiniArt(box.localToGlobal(Offset.zero) & box.size);
  }

  /// How far the card has to be pushed up before the swipe counts as an open.
  static const double _openPullDistance = 40.0;

  /// How fast an upward flick has to be to open on velocity alone, so a quick
  /// gesture does not have to travel the full distance to feel answered.
  static const double _openPullVelocity = 600.0;

  /// Upward travel accumulated over the current gesture.
  double _pullUp = 0.0;

  void _onDragStart(DragStartDetails details) => _pullUp = 0.0;

  void _onDragUpdate(DragUpdateDetails details) {
    // Upward is negative in screen coordinates, so flipping the sign makes the
    // accumulator read as "how far the card has been lifted".
    _pullUp += -details.delta.dy;
  }

  void _onDragEnd(DragEndDetails details, WavelySong song) {
    // primaryVelocity is the vertical velocity in logical pixels per second,
    // positive downward. A null means the recognizer could not estimate one,
    // in which case only the distance decides.
    final upward = -(details.primaryVelocity ?? 0.0);
    final open = _pullUp >= _openPullDistance || upward >= _openPullVelocity;
    _pullUp = 0.0;
    if (open) _openPlayer(song);
  }

  /// Opens the expanded player, lifting the cover into it.
  ///
  /// The tab switches and the player starts fading in on the same frame the
  /// cover sets off, so the backdrop and controls arrive *with* the expanding
  /// artwork instead of after it. `onStart` also fires when there is no cover
  /// to fly, so the player always opens.
  void _openPlayer(WavelySong song) {
    final shell = context.read<ShellController>();
    ArtworkFlight.expand(
      context,
      song: song,
      onStart: () => shell.selectTab(kPlayerTabIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final song = playerCtrl.currentSong;

    if (song == null) return const SizedBox.shrink();

    final fallbackTint = playerCtrl.ambientPrimary.withValues(alpha: 0.30);

    // Floats with a margin and rounded corners instead of joining the nav bar
    // edge to edge: the Apple/Google player look, where the mini player is a
    // card hovering over the UI rather than a docked strip. The margin matches
    // the navigation capsule below so the two read as one floating dock, and
    // the bottom gap keeps the capsule's own rim visible under this card.
    return Padding(
      padding: const EdgeInsets.fromLTRB(18.0, 8.0, 18.0, 8.0),
      // The bar rises into place the first time it appears. TweenAnimation
      // rather than a controller: it runs once on mount and stops, so there is
      // no idle animation ticking away behind the UI.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.9, end: 1.0),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        // Sharp cover fill behind the glass: the blur turns it into the
        // artwork-coloured wash, so the tint is the track's own hues even
        // on the flat-black Home tab. The glass tint itself stays a neutral
        // dark scrim for legibility. Only the fill is clipped to the card's
        // corners -- the glass draws its own radius and floating shadow.
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: _MiniArtFill(song: song, fallback: fallbackTint),
              ),
            ),
            GlassContainer(
              padding: EdgeInsets.zero,
              borderRadius: 24.0,
              blurSigma: IOS27GlassTheme.blurHeavy,
              tintColor: Colors.black.withValues(alpha: 0.45),
              onTap: () => _openPlayer(song),
              // Swiping the card up opens the player too, so the gesture that
              // closes it (pulling the expanded player down) has an exact
              // mirror on the way in.
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: (details) => _onDragEnd(details, song),
              semanticLabel: 'Open the expanded player',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mini Track Progress Line. Listens to the playhead
                  // directly, so the tick stream no longer rebuilds the
                  // whole bar -- only this 2px line repaints as the song
                  // plays. Wears the light-white the selected row wears.
                  SizedBox(
                    height: 2.0,
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: playerCtrl.positionListenable,
                      builder: (context, position, _) {
                        final progress = playerCtrl.duration.inMilliseconds > 0
                            ? (position.inMilliseconds /
                                      playerCtrl.duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                            : 0.0;
                        return LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            kCurrentTrackColor,
                          ),
                        );
                      },
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      children: [
                        // Album Art Thumb -- the flight's source rect. The
                        // key is shared through [ArtworkFlight] so the
                        // expanded player can aim at it without knowing
                        // this tree.
                        KeyedSubtree(
                          key: ArtworkFlight.miniArt,
                          child: ArtworkImage(
                            song: song,
                            size: 44.0,
                            borderRadius: BorderRadius.circular(12.0),
                            placeholder: const Icon(
                              CupertinoIcons.music_note,
                              color: Colors.white,
                              size: 20.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12.0),

                        // Title & Artist
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.0,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2.0),
                              Text(
                                song.artist,
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

                        // Controls
                        IconButton(
                          icon: Icon(
                            playerCtrl.isPlaying
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 26.0,
                          ),
                          onPressed: () => playerCtrl.togglePlayPause(),
                        ),

                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.forward_fill,
                            color: Colors.white,
                            size: 22.0,
                          ),
                          onPressed: () => playerCtrl.skipNext(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sharp cover fill behind the mini player's glass.
///
/// The glass blur above it does the softening, exactly like the expanded
/// backdrop: hues match the artwork by construction. Falls back to the
/// palette tint while loading or when the device has no cover.
class _MiniArtFill extends StatefulWidget {
  final WavelySong song;
  final Color fallback;

  const _MiniArtFill({required this.song, required this.fallback});

  @override
  State<_MiniArtFill> createState() => _MiniArtFillState();
}

class _MiniArtFillState extends State<_MiniArtFill> {
  Future<Uint8List?>? _future;
  String? _songId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshIfNeeded();
  }

  @override
  void didUpdateWidget(_MiniArtFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshIfNeeded();
  }

  void _refreshIfNeeded() {
    // Same loop guard as the expanded backdrop: a future built in `build`
    // refires on every mini-player rebuild (play/pause included).
    if (_songId == widget.song.id) return;
    _songId = widget.song.id;
    _future = ArtworkScope.of(context).artworkFor(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return ColoredBox(color: widget.fallback);
        // Tiny decode: the glass blur above melts detail anyway.
        return Image.memory(
          bytes,
          cacheWidth: 96,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      },
    );
  }
}
