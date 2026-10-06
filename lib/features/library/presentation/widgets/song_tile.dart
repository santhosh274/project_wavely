import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/widgets/glass_card.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// The light white the playing row glows and reads in, on every menu.
///
/// Deliberately not the artwork's palette colour: a dark or muddy cover made
/// the "what is playing" highlight hard to spot. A near-white reads as lit up
/// against every cover, and the mini player tints to match it.
const Color kCurrentTrackColor = Color(0xFFF2F4F8);

/// Glassmorphic Song Tile Item
class SongTile extends StatelessWidget {
  final WavelySong song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  /// Exposed so the mini player can tint to the same light white and the
  /// selection reads as one system across menus.
  static const Color currentTrackColor = kCurrentTrackColor;

  const SongTile({
    super.key,
    required this.song,
    this.isCurrent = false,
    this.isPlaying = false,
    required this.onTap,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      // Rows repaint in isolation: an animated neighbour (mini-player tint,
      // selection glow) no longer repaints every row on screen.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: GlassCard(
          onTap: onTap,
          padding: const EdgeInsets.all(10.0),
          isSelected: isCurrent,
          // The playing row reads as "lit up" rather than coloured: a light
          // white glow and border on every menu, so the selection never
          // depends on the artwork's palette (which can be dark or muddy).
          glowColor: kCurrentTrackColor,
          child: Row(
            children: [
              // Album Artwork Container
              ArtworkImage(
                song: song,
                size: 48.0,
                borderRadius: BorderRadius.circular(12.0),
                // The playing row shows a waveform instead of the cover, so
                // the "this is what is playing" signal survives tracks that
                // have art.
                placeholder: Icon(
                  isCurrent && isPlaying
                      ? CupertinoIcons.waveform
                      : CupertinoIcons.music_note,
                  color: Colors.white,
                  size: 22.0,
                ),
              ),
              const SizedBox(width: 14.0),

              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 15.0,
                        // The playing row reads in light white -- a highlight,
                        // not a colour taken from the artwork's palette.
                        color: isCurrent
                            ? kCurrentTrackColor
                            : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3.0),
                    Text(
                      '${song.artist} • ${song.album}',
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

              // Duration & Favorite Action
              Text(
                song.durationFormatted,
                style: TextStyle(
                  fontSize: 12.0,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8.0),
              if (onFavoriteToggle != null)
                IconButton(
                  icon: Icon(
                    song.isFavorite
                        ? CupertinoIcons.heart_fill
                        : CupertinoIcons.heart,
                    color: song.isFavorite
                        ? IOS27Colors.sunsetCoral
                        : Colors.white.withValues(alpha: 0.4),
                    size: 20.0,
                  ),
                  onPressed: onFavoriteToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
