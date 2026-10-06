import 'package:flutter/material.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'glass_container.dart';

/// iOS 27 Glassmorphic Action Button & Floating Control Button
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool isPrimary;
  final Color? accentColor;
  final double borderRadius;

  const GlassButton({
    super.key,
    required this.child,
    required this.onTap,
    this.width,
    this.height = 48.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
    this.isPrimary = false,
    this.accentColor,
    this.borderRadius = IOS27GlassTheme.radiusPill,
  });

  /// Circular Glass Icon Button (for media playback controls)
  factory GlassButton.icon({
    Key? key,
    required IconData icon,
    required VoidCallback onTap,
    double size = 56.0,
    double iconSize = 28.0,
    bool isPrimary = false,
    Color? accentColor,
    Color? iconColor,
  }) {
    return GlassButton(
      key: key,
      onTap: onTap,
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      isPrimary: isPrimary,
      accentColor: accentColor,
      borderRadius: IOS27GlassTheme.radiusPill,
      child: Icon(
        icon,
        size: iconSize,
        color: iconColor ?? (isPrimary ? Colors.white : null),
      ),
    );
  }

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    // Darkened toward black so the white glyph stays readable on light
    // artwork hues (sky blues, yellows): a translucent lifted colour over a
    // bright backdrop washes the icon out. The hue is preserved, only the
    // luminance drops, and the outer glow keeps the un-darkened accent.
    final fill = Color.lerp(accent, Colors.black, 0.32)!;

    return GestureDetector(
      onTapDown: (_) => _animController.forward(),
      onTapUp: (_) => _animController.reverse(),
      onTapCancel: () => _animController.reverse(),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: GlassContainer(
            width: widget.width,
            height: widget.height,
            padding: widget.padding,
            borderRadius: widget.borderRadius,
            tintColor: widget.isPrimary
                ? fill.withValues(alpha: 0.85)
                : null,
            borderColor: widget.isPrimary
                ? accent.withValues(alpha: 0.9)
                : null,
            shadows: widget.isPrimary
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
            child: Center(
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
