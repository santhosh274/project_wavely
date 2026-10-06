import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wavely/core/models/album_model.dart';
import 'package:wavely/core/widgets/glass_card.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// Glassmorphic Grid Card for Albums
class AlbumCard extends StatelessWidget {
  final WavelyAlbum album;
  final VoidCallback onTap;

  const AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12.0),
      borderRadius: 24.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album Cover Box with 3D Gloss
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.0),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      IOS27Colors.glowingPurple,
                      IOS27Colors.electricIndigo,
                      IOS27Colors.neonCyan,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(
                    CupertinoIcons.music_albums,
                    size: 40.0,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10.0),

          // Album Name
          Text(
            album.albumName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2.0),

          // Artist & Song Count
          Text(
            '${album.artist} • ${album.songCount} tracks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.0,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
