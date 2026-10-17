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

  /// The track whose load has been issued, so a rebuild between the request and
  /// its reply does not fire a second one.
  String? _requestedFor;

  /// How long the cover takes to cross-fade when it changes.
  ///
  /// Long enough to read as a dissolve rather than a snap, short enough that
  /// scrubbing through a queue never feels like it is waiting on artwork. The
  /// outgoing cover keeps painting for the whole fade, so a track change never
  /// exposes the gradient placeholder underneath.
  static const Duration _fade = Duration(milliseconds: 220);

  /// The content currently on screen, and the key identifying it to the
  /// cross-fade.
  ///
  /// The identity is the bytes when there is a cover and the settled flag when
  /// there is not, so a rebuild that changes nothing *visible* -- a reply landing
  /// for a track whose cover is already up, an unrelated parent rebuild -- mints
  /// no key and the switcher does nothing. A fresh [UniqueKey] is minted only when
  /// that identity really changes: keying on the state instead ("has a cover",
  /// "placeholder") lets two *different* covers both claim the same key while one
  /// is still fading out, which the switcher rejects as duplicate children.
  Object? _contentIdentity;
  Key? _contentKey;

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

  /// Resolve the cover for the current song.
  ///
  /// A hit in the service's cache is applied without a future and without a
  /// frame of placeholder: this is the common case on a track change (the
  /// palette extraction already pulled the album, and prefetch warms the queue),
  /// and going through `async` here is exactly what used to flash the placeholder
  /// for one frame on every change. Both callers rebuild right after, so the
  /// fields can be written directly rather than through `setState`.
  void _load() {
    final songId = widget.song.id;
    if (_requestedFor == songId) return;
    _requestedFor = songId;

    final service = ArtworkScope.of(context);
    if (service.isCached(widget.song)) {
      _loadedFor = songId;
      _bytes = service.cachedArtworkFor(widget.song);
      return;
    }

    _resolve(service, songId);
  }

  Future<void> _resolve(ArtworkService service, String songId) async {
    final bytes = await service.artworkFor(widget.song);
    if (!mounted || widget.song.id != songId) return;

    setState(() {
      _loadedFor = songId;
      _bytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    // "Settled" means the answer for *this* track is in: either a cover or a
    // device that genuinely has none. Until then the previous track's cover
    // keeps painting, so a change dissolves cover-to-cover instead of
    // collapsing to the placeholder first.
    final settled = _loadedFor == widget.song.id;

    Widget content;
    if (bytes != null) {
      // Decode at the size the widget is drawn at, not at the 512px the media
      // store hands over: a 44px list thumbnail decoded full-size holds a
      // 512×512 bitmap for the whole session, and a library screen decodes a
      // dozen of those per scroll. cacheWidth makes the codec downsample
      // during decode, so the memory and the decode time both drop by an
      // order of magnitude on the small tiles.
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final targetWidth = (widget.size * dpr).round().clamp(16, 512);

      content = ClipRRect(
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
    } else {
      // The cover is either still being read, or the device does not have one.
      // Neither is worth an error state: the placeholder is the answer for
      // both, and it stays put until the real cover shows up.
      content = _Shell(
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

    // Cross-fade only when the content actually changes: an unrelated rebuild
    // keeps the same key and reuses the child for free, while a track change (or
    // a cover arriving) dissolves.
    final Object identity = bytes ?? ValueKey<bool>(settled);
    if (_contentIdentity != identity) {
      _contentIdentity = identity;
      _contentKey = UniqueKey();
    }

    return AnimatedSwitcher(
      duration: _fade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [...previousChildren, ?currentChild],
      ),
      child: KeyedSubtree(key: _contentKey, child: content),
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

  /// The service without registering a dependency on the scope.
  ///
  /// For callers outside the build phase -- a tap handler starting an artwork
  /// flight -- where depending on the inherited widget would be meaningless and
  /// subscribing an already-built element is not wanted.
  static ArtworkService read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ArtworkScope>();
    assert(scope != null, 'No ArtworkScope found above this widget.');
    return scope!.service;
  }

  @override
  bool updateShouldNotify(ArtworkScope oldWidget) => service != oldWidget.service;
}
