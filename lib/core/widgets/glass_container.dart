import 'ui_image_filter_compat.dart';
import 'package:flutter/material.dart';
import '../theme/ios27_colors.dart';
import '../theme/ios27_glass_theme.dart';

/// Fundamental iOS 27 Glassmorphic Container
/// Combines BackdropFilter blur, multi-layered specular gradient border, and translucent tint.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double blurSigma;
  final double borderRadius;
  final Color? tintColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadows;

  /// Whether the surface really blurs what is behind it.
  ///
  /// A [BackdropFilter] forces the engine into a saveLayer over everything
  /// painted below it, so a long list of these -- one per song row -- spends
  /// most of a frame budget on blurring pixels that are a flat backdrop
  /// anyway. Pass `false` for surfaces sitting on the ambient backdrop, where
  /// the translucent tint and sheen read identically to a real blur and cost
  /// a single draw. Keep it `true` for floating chrome over live content
  /// (the navigation bar, the mini player, the search field).
  final bool backdrop;

  final VoidCallback? onTap;

  /// Announced by screen readers when [onTap] makes the surface a control.
  ///
  /// A bare [GestureDetector] contributes nothing to the semantics tree, so a
  /// tappable glass panel was invisible to TalkBack and to anything else reading
  /// the accessibility tree. Pass a label wherever the tap target carries
  /// meaning that its contents do not -- "Open the expanded player" for the mini
  /// player, whose own text says nothing about what tapping does.
  final String? semanticLabel;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.blurSigma = IOS27GlassTheme.blurStandard,
    this.borderRadius = IOS27GlassTheme.radiusMedium,
    this.tintColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.shadows,
    this.backdrop = true,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultTint = isDark
        ? IOS27Colors.glassDarkSurface
        : IOS27Colors.glassLightSurface;

    final defaultBorder = isDark
        ? IOS27Colors.glassDarkBorder
        : IOS27Colors.glassLightBorder;

    final defaultShadows = shadows ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ];

    final radius = BorderRadius.circular(borderRadius);

    // The specular sheen: a faint diagonal light band drawn over the surface,
    // the way a real piece of glass catches a light source. Drawn through
    // [foregroundDecoration] so it sits above the content like a reflection
    // would, at alphas low enough that text under it stays readable.
    final sheen = BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.10 : 0.22),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: isDark ? 0.04 : 0.07),
        ],
        stops: const [0.0, 0.45, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );

    Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: defaultShadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: blurredSurface(
          radius,
          tint: defaultTint,
          border: defaultBorder,
          isDark: isDark,
        ),
      ),
    );

    // The sheen is painted over the whole surface, including the border, so
    // it wraps the clip rather than the padded content box.
    content = Container(
      foregroundDecoration: sheen,
      child: content,
    );

    if (onTap != null) {
      Widget tappable = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );

      if (semanticLabel != null) {
        tappable = Semantics(
          container: true,
          button: true,
          label: semanticLabel,
          child: tappable,
        );
      }

      return tappable;
    }

    return content;
  }

  /// The tinted surface, wrapped in the liquid blur when [backdrop] is set.
  ///
  /// With the blur skipped, the tint below carries the surface on its own --
  /// which is what the list rows use, so scrolling a thousand-song library
  /// never queues a blur pass per row.
  Widget blurredSurface(
    BorderRadius radius, {
    required Color tint,
    required Color border,
    required bool isDark,
  }) {
    final surface = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor ?? tint,
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? border,
          width: borderWidth,
        ),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.02),
                ]
              : [
                  Colors.white.withValues(alpha: 0.6),
                  Colors.white.withValues(alpha: 0.2),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );

    if (!backdrop) return surface;

    return BackdropFilter(
      filter: UiImageFilterCompat.liquidBlur(sigma: blurSigma),
      child: surface,
    );
  }
}
