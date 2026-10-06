import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wavely/core/models/artist_model.dart';
import 'package:wavely/core/widgets/glass_card.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// Glassmorphic Artist Item
class ArtistTile extends StatelessWidget {
  final WavelyArtist artist;
  final VoidCallback onTap;

  const ArtistTile({
    super.key,
    required this.artist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Circular Avatar
            Container(
              width: 50.0,
              height: 50.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [IOS27Colors.cyberPink, IOS27Colors.electricIndigo],
                ),
                boxShadow: [
                  BoxShadow(
                    color: IOS27Colors.cyberPink.withValues(alpha: 0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.person_fill,
                  color: Colors.white,
                  size: 24.0,
                ),
              ),
            ),
            const SizedBox(width: 14.0),

            // Artist Name & Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.artistName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.0,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3.0),
                  Text(
                    '${artist.numberOfAlbums} Albums • ${artist.numberOfTracks} Tracks',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              CupertinoIcons.chevron_right,
              color: Colors.white.withValues(alpha: 0.4),
              size: 18.0,
            ),
          ],
        ),
      ),
    );
  }
}
