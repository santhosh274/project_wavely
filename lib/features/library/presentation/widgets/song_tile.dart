import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/widgets/glass_card.dart';
import 'package:wavely/core/widgets/artwork_image.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// The near-white the selected row's title reads in, on every menu.
///
/// Deliberately not the artwork's palette colour: a dark or muddy cover made
/// the "what is playing" highlight hard to spot. A near-white reads as lit up
/// against every cover, and the mini player's progress line matches it.
const Color kCurrentTrackColor = Color(0xFFF2F4F8);

/// Glassmorphic Song Tile Item
class SongTile extends StatelessWidget {
  final WavelySong song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  /// Opens the row's action sheet on a long press.
  ///
  /// The list owns what the menu can do -- it knows the queue the row belongs
  /// to, which [SongTile] does not -- so the callback is supplied by the caller
  /// rather than the tile reaching for providers itself.
  final VoidCallback? onLongPress;

  /// Exposed so other surfaces can match the selection's highlight colour.
  static const Color currentTrackColor = kCurrentTrackColor;

  const SongTile({
    super.key,
    required this.song,
    this.isCurrent = false,
    this.isPlaying = false,
    required this.onTap,
    this.onFavoriteToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final selected = isCurrent;
    final playing = selected && isPlaying;

    return RepaintBoundary(
      // Rows repaint in isolation: an animated neighbour (mini-player tint,
      // selection state) no longer repaints every row on screen.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: GlassCard(
          onTap: onTap,
          onLongPress: onLongPress,
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
          isSelected: selected,
          // The selected row is a fully opaque, elevated slate slab -- no
          // glass, no sheen, no translucent gradient. The "fog" a selected
          // row used to show was the glass layers brightening its middle;
          // opaque mode renders none of them, so the whole row reads as one
          // solid surface, Apple/Google player style.
          opaque: selected,
          child: Row(
            children: [
              // Album Artwork Container
              ArtworkImage(
                song: song,
                size: 48.0,
                borderRadius: BorderRadius.circular(12.0),
                // With no cover to show, the playing row displays a waveform
                // instead of the plain note, so the "this is what is playing"
                // signal survives tracks without artwork too.
                placeholder: Icon(
                  playing ? CupertinoIcons.waveform : CupertinoIcons.music_note,
                  color: Colors.white,
                  size: 22.0,
                ),
              ),
              const SizedBox(width: 14.0),

              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 15.0,
                        // Selected rows read in near-white on the opaque
                        // slate; unselected rows stay plain white on glass.
                        color: selected ? kCurrentTrackColor : Colors.white,
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
