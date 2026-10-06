import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/lyrics_service.dart';
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/widgets/ambient_background.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// Lyrics for the track that is playing.
///
/// Reads the `.lrc` sidecar next to the audio file and highlights the line that
/// matches the playhead. When there is no sidecar the sheet says so plainly
/// rather than showing a stand-in: the button promises lyrics, so pretending
/// there are none of a kind would just be a different lie.
class LyricsSheet extends StatefulWidget {
  final WavelySong song;

  const LyricsSheet({super.key, required this.song});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  static const LyricsService _service = LyricsService();

  late Future<LyricsResult> _lookup;

  @override
  void initState() {
    super.initState();
    _lookup = _service.load(widget.song);
  }

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();

    return FractionallySizedBox(
      heightFactor: 0.78,
      child: AmbientBackground(
        washPrimary: playerCtrl.ambientPrimary,
        washSecondary: playerCtrl.ambientSecondary,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12.0),
              Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
              const SizedBox(height: 14.0),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    Text(
                      widget.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      widget.song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8.0),
              Expanded(
                child: FutureBuilder<LyricsResult>(
                  future: _lookup,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CupertinoActivityIndicator(color: Colors.white),
                      );
                    }

                    final result = snapshot.data;
                    if (result == null) {
                      return const _LyricsMessage(
                        icon: CupertinoIcons.exclamationmark_triangle,
                        message: 'Could not read the lyrics for this track.',
                      );
                    }

                    return switch (result.status) {
                      LyricsStatus.found => _LyricsBody(
                          result: result,
                          songId: widget.song.id,
                        ),
                      LyricsStatus.notFound => const _LyricsMessage(
                          icon: CupertinoIcons.text_quote,
                          message:
                              'No lyrics on this device. Save an .lrc file '
                              'next to the audio file, named after the track, '
                              'and it will show up here.',
                        ),
                      LyricsStatus.unreadable => const _LyricsMessage(
                          icon: CupertinoIcons.doc,
                          message:
                              'A lyrics file sits next to this track but it '
                              'does not contain any timed lines.',
                        ),
                    };
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lyric lines, with the current one highlighted against the playhead.
class _LyricsBody extends StatefulWidget {
  final LyricsResult result;
  final String songId;

  const _LyricsBody({required this.result, required this.songId});

  @override
  State<_LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends State<_LyricsBody> {
  final _scrollController = ScrollController();
  Duration _lastPosition = Duration.zero;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.read<PlayerController>();

    // Follows the playhead through the narrow position listenable rather than
    // through the controller's notifications, so the highlight moves without
    // dragging the whole sheet through a rebuild on every tick.
    return ValueListenableBuilder<Duration>(
      valueListenable: playerCtrl.positionListenable,
      builder: (context, position, _) {
        final lines = widget.result.lines;

        // Only react when the active line actually changed. The position stream
        // fires several times a second and rebuilding every line each time would
        // both flicker and fight the user's scrolling.
        final activeIndex = _indexOfLineAt(lines, position);
        if (position != _lastPosition) {
          _lastPosition = position;
          _scrollToActive(activeIndex);
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final isActive = index == activeIndex;
            // Before the first timestamp nothing has been sung yet, so no line is
            // "past" -- every one reads as upcoming.
            final isPast = activeIndex != null && index < activeIndex;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                lines[index].text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: isPast ? 0.28 : 0.45),
                  fontSize: isActive ? 18.0 : 16.0,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  height: 1.4,
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Index of the last line at or before [position], or null before the first.
  static int? _indexOfLineAt(List<LyricLine> lines, Duration position) {
    int? active;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  /// Keep the active line roughly centred.
  ///
  /// Only nudges when it has drifted well off screen, so the view does not
  /// fight a user who is reading ahead.
  void _scrollToActive(int? activeIndex) {
    if (activeIndex == null || !_scrollController.hasClients) return;

    final viewport = _scrollController.position.viewportDimension;
    final target = (activeIndex * _estimatedLineExtent) - (viewport / 2) + 24.0;
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    if ((_scrollController.offset - clamped).abs() < 24.0) return;

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  /// Rough height of a lyric row: font size plus line spacing plus padding.
  ///
  /// Computing real per-item offsets would mean a layout pass over every line;
  /// the estimate is only used to decide where to scroll, so being slightly off
  /// is invisible.
  static const double _estimatedLineExtent = 47.0;
}

class _LyricsMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _LyricsMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 40.0),
            const SizedBox(height: 14.0),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14.0,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10.0),
            Text(
              'Timed .lrc lines look like [00:12.50] words, words, words',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: IOS27Colors.neonCyan.withValues(alpha: 0.8),
                fontSize: 12.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}