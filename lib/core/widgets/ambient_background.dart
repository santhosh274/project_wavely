import 'package:flutter/material.dart';

/// Backdrop for the player-only surfaces that want an artwork wash.
///
/// Strictly wash-only: with no [washPrimary]/[washSecondary] this renders a
/// plain [ColoredBox] of [color] and nothing else. The old static graphite
/// gradient plus slate glow -- the "fog" behind every menu -- is gone; menus
/// sit on flat black and the wash lives only where colour belongs (the
/// expanded player, its fallback tint, the lyrics sheet).
class AmbientBackground extends StatelessWidget {
  /// Opaque base colour under the wash. Defaults to near-black.
  final Color? color;

  /// Dominant colour of the current artwork; the large upper glow.
  final Color? washPrimary;

  /// Secondary accent of the current artwork; the lower counter-glow.
  final Color? washSecondary;

  final Widget child;

  const AmbientBackground({
    super.key,
    this.color,
    this.washPrimary,
    this.washSecondary,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final base = color ?? const Color(0xFF05060B);

    // No wash requested (or an explicit flat colour): a plain surface, one
    // draw, nothing to repaint -- the "normal" background every menu uses.
    if (washPrimary == null && washSecondary == null) {
      return ColoredBox(color: base, child: child);
    }

    return ColoredBox(
      color: base,
      child: CustomPaint(
        painter: _AmbientWashPainter(
          primary: washPrimary,
          secondary: washSecondary,
        ),
        isComplex: true,
        willChange: false,
        child: child,
      ),
    );
  }
}

class _AmbientWashPainter extends CustomPainter {
  final Color? primary;
  final Color? secondary;

  _AmbientWashPainter({this.primary, this.secondary});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    if (primary != null) {
      // Upper-left: the dominant colour fills most of the view.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              primary!.withValues(alpha: 0.32),
              primary!.withValues(alpha: 0.0),
            ],
            center: const Alignment(-0.6, -0.75),
            radius: size.longestSide * 0.95,
          ).createShader(rect),
      );
    }

    if (secondary != null) {
      // Lower-right: the accent picks up where the first fades out.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              secondary!.withValues(alpha: 0.24),
              secondary!.withValues(alpha: 0.0),
            ],
            center: const Alignment(0.85, 0.85),
            radius: size.longestSide * 0.75,
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientWashPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}
