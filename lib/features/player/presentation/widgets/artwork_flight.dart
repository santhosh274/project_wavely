import 'dart:typed_data';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'package:wavely/core/widgets/artwork_image.dart';

/// The mini player's cover lifting into the expanded player, and back.
///
/// The expanded player is a tab, not a pushed route, so Flutter's [Hero]
/// flight never fires (heroes only animate across route transitions). This
/// drives the same effect by hand: the source rect and the destination rect are
/// read off the two widgets that show the cover, a copy of the artwork is placed
/// in a full-screen overlay, and it animates size, position and corner radius
/// between them while the screens cross-fade underneath. Because the flight ends
/// exactly on the destination cover -- same rect, same radius, same pixels -- the
/// hand-off is invisible.
class ArtworkFlight {
  ArtworkFlight._();

  /// Shared handles the flight participants key their cover with, so the mini
  /// player and the expanded player can point at each other's artwork without
  /// knowing each other's widget tree.
  static final GlobalKey miniArt = GlobalKey(debugLabel: 'miniArt');
  static final GlobalKey expandedArt = GlobalKey(debugLabel: 'expandedArt');

  /// The cover's corner radius on each side, so the flight interpolates the
  /// shape and not just the box.
  static const double _miniRadius = 12.0;
  static const double _expandedRadius = IOS27GlassTheme.radiusLarge;

  /// How long the cover takes to travel between the two covers.
  ///
  /// The expanded player fades in/out over exactly this long, so the backdrop and
  /// the chrome finish arriving/leaving on the same frame the cover lands.
  static const Duration travelDuration = Duration(milliseconds: 360);

  /// Modern, ultra-smooth fluid cubic curve (fast launch, smooth deceleration).
  static const Curve motionCurve = Cubic(0.16, 1.0, 0.30, 1.0);

  /// Bumped the instant an expand flight begins.
  static final ValueNotifier<int> revealTick = ValueNotifier<int>(0);

  /// Bumped the instant a collapse flight begins.
  static final ValueNotifier<int> collapseTick = ValueNotifier<int>(0);

  /// How far the cover is through its travel: 0 at the source, 1 at the target.
  ///
  /// Published by the flying copy itself, every frame, both ways. Anything that
  /// has to move *with* the artwork reads this and gets the exact number the
  /// flight is drawing the cover at, rather than running a second animation
  /// alongside it and hoping the two stay in step. The expanded player's chrome
  /// uses it to fade out in proportion to the cover shrinking.
  static final ValueNotifier<double> progress = ValueNotifier<double>(0.0);

  /// True while a cover is in the air.
  static final ValueNotifier<bool> inFlightNotifier = ValueNotifier<bool>(
    false,
  );

  /// True while a collapse flight is in progress.
  static final ValueNotifier<bool> isCollapsing = ValueNotifier<bool>(
    false,
  );

  /// Where the mini player's artwork sat the last time it was on screen.
  static Rect? _miniRect;

  /// Marked while a flight is in progress.
  static bool _inFlight = false;

  /// Whether a cover is in the air right now.
  static bool get inFlight => _inFlight;

  /// Record where the mini player's cover is, while it is on screen.
  static void rememberMiniArt(Rect rect) {
    _miniRect = rect;
  }

  /// Flight from the mini player up into the expanded player.
  static void expand(
    BuildContext context, {
    required WavelySong song,
    VoidCallback? onStart,
  }) {
    _fly(
      context,
      song: song,
      sourceKey: miniArt,
      targetKey: expandedArt,
      sourceRadius: _miniRadius,
      targetRadius: _expandedRadius,
      onStart: onStart,
      revealOnStart: true,
      isCollapse: false,
    );
  }

  /// Flight from the expanded player back down to the mini player.
  static void collapse(
    BuildContext context, {
    required WavelySong song,
    VoidCallback? onComplete,
  }) {
    _fly(
      context,
      song: song,
      sourceKey: expandedArt,
      targetKey: miniArt,
      sourceRadius: _expandedRadius,
      targetRadius: _miniRadius,
      onComplete: onComplete,
      isCollapse: true,
    );
  }

  static void _fly(
    BuildContext context, {
    required WavelySong song,
    required GlobalKey sourceKey,
    required GlobalKey targetKey,
    required double sourceRadius,
    required double targetRadius,
    VoidCallback? onStart,
    VoidCallback? onComplete,
    bool revealOnStart = false,
    bool isCollapse = false,
  }) {
    if (_inFlight) return;

    final sourceBox =
        sourceKey.currentContext?.findRenderObject() as RenderBox?;
    if (sourceBox == null || !sourceBox.attached || !sourceBox.hasSize) {
      onStart?.call();
      onComplete?.call();
      return;
    }
    final source = sourceBox.localToGlobal(Offset.zero) & sourceBox.size;
    if (source.isEmpty) {
      onStart?.call();
      onComplete?.call();
      return;
    }

    if (sourceKey == miniArt) _miniRect = source;

    final target = _targetRect(context, targetKey: targetKey, source: source);

    final service = ArtworkScope.read(context);
    final bytes = service.cachedArtworkFor(song);
    if (bytes == null) {
      onStart?.call();
      onComplete?.call();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => RepaintBoundary(
        child: _FlightTransition(
          bytes: bytes,
          source: source,
          target: target,
          sourceRadius: sourceRadius,
          targetRadius: targetRadius,
          duration: travelDuration,
          isCollapse: isCollapse,
          onDone: () {
            entry.remove();
            _setInFlight(false);
            isCollapsing.value = false;
            onComplete?.call();
          },
        ),
      ),
    );

    // Rewound before anything is told a flight has started: a listener that
    // reads the progress the moment it hears about the flight would otherwise
    // see the number the *previous* one ended on, and paint one frame of the
    // finished state.
    progress.value = 0.0;
    isCollapsing.value = isCollapse;
    _setInFlight(true);
    if (revealOnStart) {
      revealTick.value++;
    } else if (isCollapse) {
      collapseTick.value++;
    }

    onStart?.call();
    overlay.insert(entry);
  }

  static void _setInFlight(bool value) {
    _inFlight = value;
    inFlightNotifier.value = value;
  }

  static Rect _targetRect(
    BuildContext context, {
    required GlobalKey targetKey,
    required Rect source,
  }) {
    final box = targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize && !box.size.isEmpty) {
      return box.localToGlobal(Offset.zero) & box.size;
    }

    if (targetKey == miniArt && _miniRect != null) return _miniRect!;

    final size = MediaQuery.sizeOf(context);
    final cover = size.width * 0.78;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: cover,
      height: cover,
    );
  }
}

class _FlightTransition extends StatefulWidget {
  final Uint8List bytes;
  final Rect source;
  final Rect target;
  final double sourceRadius;
  final double targetRadius;
  final Duration duration;
  final bool isCollapse;
  final VoidCallback onDone;

  const _FlightTransition({
    required this.bytes,
    required this.source,
    required this.target,
    required this.sourceRadius,
    required this.targetRadius,
    required this.duration,
    required this.isCollapse,
    required this.onDone,
  });

  @override
  State<_FlightTransition> createState() => _FlightTransitionState();
}

class _FlightTransitionState extends State<_FlightTransition>
    with SingleTickerProviderStateMixin {
  static const int _decodeWidth = 512;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // Published from a listener rather than from `build`: a tick arrives in the
    // transient-callback phase, before anything is laid out, so a listener that
    // moves other widgets marks them dirty for *this* frame instead of midway
    // through building it.
    _controller.addListener(_publishProgress);
    _controller.forward().whenComplete(widget.onDone);
  }

  void _publishProgress() => ArtworkFlight.progress.value = _controller.value;

  @override
  void dispose() {
    _controller.removeListener(_publishProgress);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final rawT = _controller.value;
          final t = ArtworkFlight.motionCurve.transform(rawT);
          final rect = Rect.lerp(widget.source, widget.target, t)!;
          final radius = lerpDouble(
            widget.sourceRadius,
            widget.targetRadius,
            t,
          )!;

          final elevation = widget.isCollapse ? (1.0 - t) : t;
          final shadowAlpha = (0.10 + (0.35 * elevation)).clamp(0.0, 0.45);
          final shadowBlur = 8.0 + (28.0 * elevation);
          final shadowOffsetY = 2.0 + (12.0 * elevation);

          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: shadowAlpha),
                        blurRadius: shadowBlur,
                        spreadRadius: -2 * elevation,
                        offset: Offset(0, shadowOffsetY),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: Image.memory(
                      widget.bytes,
                      cacheWidth: _decodeWidth,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
