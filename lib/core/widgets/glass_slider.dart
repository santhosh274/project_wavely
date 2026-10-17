import 'package:flutter/material.dart';
import '../theme/ios27_colors.dart';

/// Custom iOS 27 Glassmorphic Slider
class GlassSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;
  final double trackHeight;

  const GlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.onChangeStart,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.trackHeight = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    final active = activeColor ?? IOS27Colors.electricIndigo;
    final inactive = inactiveColor ?? Colors.white.withValues(alpha: 0.15);

    final clampedValue = value.clamp(min, max);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: trackHeight,
        activeTrackColor: active,
        inactiveTrackColor: inactive,
        thumbColor: Colors.white,
        overlayColor: active.withValues(alpha: 0.2),
        thumbShape: const _GlassSliderThumbShape(thumbRadius: 8.0),
        trackShape: const RoundedRectSliderTrackShape(),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
      ),
      child: Slider(
        value: clampedValue,
        min: min,
        max: max,
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

class _GlassSliderThumbShape extends SliderComponentShape {
  final double thumbRadius;

  const _GlassSliderThumbShape({this.thumbRadius = 8.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(thumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Outer Glow Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center + const Offset(0, 2), thumbRadius, shadowPaint);

    // Inner Solid Thumb
    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, thumbRadius, thumbPaint);

    // Border Halo
    final borderPaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? IOS27Colors.electricIndigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, thumbRadius + 1.0, borderPaint);
  }
}
