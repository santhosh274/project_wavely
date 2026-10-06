import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/artwork_service.dart';
import 'package:wavely/core/theme/ios27_colors.dart';

/// Album artwork for [song], loaded on demand.
///
/// The artwork is fetched through [ArtworkService] rather than being carried on
/// the song, because scanning a library of thousands of tracks cannot afford to
/// decode an image for each one. This widget shows the gradient placeholder and
/// swaps in the real cover once it arrives, so a slow disk read never blocks the
/// first frame.
class ArtworkImage extends StatefulWidget {
  final WavelySong song;
  final double size;

  /// Border radius for the artwork. Defaults to a rounded square.
  final BorderRadius? borderRadius;

  /// Shown when the device genuinely has no cover for this track.
  final Widget? placeholder;

  const ArtworkImage({
    super.key,
    required this.song,
    required this.size,
    this.borderRadius,
    this.placeholder,
  });

  @override
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  Uint8List? _bytes;

  /// The track [_bytes] belongs to, so a late reply for an abandoned track is
  /// dropped instead of showing the wrong cover.
  String? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) _load();
  }

  Future<void> _load() async {
    final songId = widget.song.id;
    final bytes = await ArtworkScope.of(context).artworkFor(widget.song);
    if (!mounted || widget.song.id != songId) return;

    setState(() {
      _loadedFor = songId;
      _bytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final settled = _loadedFor == widget.song.id;

    if (settled && bytes != null) {
      // Decode at the size the widget is drawn at, not at the 512px the media
      // store hands over: a 44px list thumbnail decoded full-size holds a
      // 512×512 bitmap for the whole session, and a library screen decodes a
      // dozen of those per scroll. cacheWidth makes the codec downsample
      // during decode, so the memory and the decode time both drop by an
      // order of magnitude on the small tiles.
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final targetWidth = (widget.size * dpr).round().clamp(16, 512);

      return ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(16.0),
        child: Image.memory(
          bytes,
          cacheWidth: targetWidth,
          fit: BoxFit.cover,
          width: widget.size,
          height: widget.size,
          gaplessPlayback: true,
        ),
      );
    }

    // The cover is either still being read, or the device does not have one.
    // Neither is worth an error state: the placeholder is the answer for both,
    // and it stays put until the real cover shows up.
    return _Shell(
      size: widget.size,
      borderRadius: widget.borderRadius,
      child: widget.placeholder ??
          Icon(
            Icons.music_note_rounded,
            color: Colors.white.withValues(alpha: settled ? 0.9 : 0.0),
            size: widget.size * 0.35,
          ),
    );
  }
}

class _Shell extends StatelessWidget {
  final double size;
  final BorderRadius? borderRadius;
  final Widget child;

  /// A null [borderRadius] falls back to the same rounded square the real cover
  /// gets, so the swap does not change the shape.
  static const _fallbackRadius = BorderRadius.all(Radius.circular(16.0));

  const _Shell({
    required this.size,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? _fallbackRadius,
        gradient: const LinearGradient(
          colors: [IOS27Colors.electricIndigo, IOS27Colors.neonCyan],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: child),
    );
  }
}

/// Makes one [ArtworkService] available to every [ArtworkImage] below it.
///
/// The cache has to outlive individual widgets: scrolling a list rebuilds them
/// constantly, and a per-widget cache would re-query the media store every time
/// a row scrolled back into view.
class ArtworkScope extends InheritedWidget {
  final ArtworkService service;

  const ArtworkScope({
    super.key,
    required this.service,
    required super.child,
  });

  static ArtworkService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ArtworkScope>();
    assert(scope != null, 'No ArtworkScope found above this widget.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(ArtworkScope oldWidget) => service != oldWidget.service;
}