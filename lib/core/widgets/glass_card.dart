import 'package:flutter/material.dart';
import 'glass_container.dart';
import '../theme/ios27_glass_theme.dart';

/// Tactile Glass Card with iOS 27 press feedback
class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final bool isSelected;
  final Color? glowColor;

  /// Whether the card really blurs what is behind it. Off by default.
  ///
  /// Cards are list and grid rows: a library screen can have dozens on screen
  /// at once and hundreds while scrolling, and a BackdropFilter per card makes
  /// every one of those frames pay a saveLayer. Behind a card is the flat or
  /// gradient ambient backdrop, so the tint and sheen read the same as a blur
  /// would -- the expensive part is skipped and nothing visibly changes.
  final bool backdrop;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.borderRadius = IOS27GlassTheme.radiusMedium,
    this.isSelected = false,
    this.glowColor,
    this.backdrop = false,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final glow = widget.glowColor ?? theme.colorScheme.primary;

    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: GlassContainer(
            width: widget.width,
            height: widget.height,
            padding: widget.padding,
            margin: widget.margin,
            borderRadius: widget.borderRadius,
            backdrop: widget.backdrop,
            borderColor: widget.isSelected
                ? glow.withValues(alpha: 0.8)
                : (isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.6)),
            borderWidth: widget.isSelected ? 2.0 : 1.0,
            shadows: widget.isSelected
                ? [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
