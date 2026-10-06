import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';

/// Glass Mini Player forming the top half of the shell's bottom dock.
///
/// It sits flush above the navigation bar with no gap and square meeting
/// edges, so the two read as one docked window rather than floating pills.
/// The glass is tinted with the playing track's own colour and morphs to the
/// new hue when the track changes, so the bar reads as part of the same liquid
/// system as the expanded player's backdrop and glow.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final song = playerCtrl.currentSong;

    if (song == null) return const SizedBox.shrink();

    final fallbackTint = playerCtrl.ambientPrimary.withValues(alpha: 0.30);

    // Full-bleed and square: the bar is the dock's top edge, joining the
    // navigation bar below with no seam.
    // The bar rises into place the first time it appears. TweenAnimation
    // rather than a controller: it runs once on mount and stops, so there is
    // no idle animation ticking away behind the UI.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      // Same blurred-artwork treatment as the expanded backdrop, at bar
      // scale: the sharp cover fills the bar behind the glass, and the
      // glass blur turns it into the artwork-coloured wash -- so the tint
      // is the track's own hues even on the flat-black Home tab. The
      // glass tint itself stays a neutral dark scrim for legibility.
      child: Stack(
        children: [
          Positioned.fill(
            child: _MiniArtFill(song: song, fallback: fallbackTint),
          ),
          GlassContainer(
            padding: EdgeInsets.zero,
            borderRadius: 0,
            blurSigma: IOS27GlassTheme.blurHeavy,
              tintColor: Colors.black.withValues(alpha: 0.45),
              onTap: () =>
                  context.read<ShellController>().selectTab(kPlayerTabIndex),
              semanticLabel: 'Open the expanded player',
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mini Track Progress Line. Listens to the playhead directly, so
                // the tick stream no longer rebuilds the whole bar -- only this
                // 2px line repaints as the song plays.
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
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
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
                      // Album Art Thumb
                      ArtworkImage(
                        song: song,
                        size: 44.0,
                        borderRadius: BorderRadius.circular(12.0),
                        placeholder: const Icon(
                          CupertinoIcons.music_note,
                          color: Colors.white,
                          size: 20.0,
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
                                color:
                                    Colors.white.withValues(alpha: 0.6),
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
