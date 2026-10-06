import 'package:flutter/material.dart';

/// iOS 27 Design System - Glassmorphic Color Palette
class IOS27Colors {
  IOS27Colors._();

  // Glass Surface Tints
  static const Color glassDarkBase = Color(0x2B0D0E1A);
  static const Color glassDarkSurface = Color(0x3D181A2A);
  static const Color glassDarkBorder = Color(0x33FFFFFF);
  static const Color glassDarkHighlight = Color(0x26FFFFFF);

  static const Color glassLightBase = Color(0x66F0F3F9);
  static const Color glassLightSurface = Color(0x80FFFFFF);
  static const Color glassLightBorder = Color(0x66FFFFFF);
  static const Color glassLightHighlight = Color(0x99FFFFFF);

  // Vibrant Accents (iOS 27 Dynamic Neon & Fluid Spectrum)
  static const Color electricIndigo = Color(0xFF6366F1);

  /// A brighter indigo for text sitting on dark glass: the base indigo is the
  /// app's primary, but at title sizes on near-black it reads slightly dim, so
  /// the "now playing" track uses this lifted variant of the same hue.
  static const Color electricIndigoBright = Color(0xFF8B90FF);
  static const Color neonCyan = Color(0xFF06B6D4);
  static const Color sunsetCoral = Color(0xFFFF5252);
  static const Color glowingPurple = Color(0xFFA855F7);
  static const Color liquidEmerald = Color(0xFF10B981);
  static const Color cyberPink = Color(0xFFEC4899);
  static const Color amberGlow = Color(0xFFF59E0B);

  // Ambient Gradients
  static const LinearGradient defaultAmbientGradient = LinearGradient(
    colors: [
      Color(0xFF2E0854),
      Color(0xFF0F172A),
      Color(0xFF030712),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient glassSpecularGradient = LinearGradient(
    colors: [
      Color(0x66FFFFFF),
      Color(0x0DFFFFFF),
      Color(0x33FFFFFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient activeTrackGradient = LinearGradient(
    colors: [
      electricIndigo,
      neonCyan,
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Lifts a colour extracted from artwork so it stays visible as a glow or a
  /// background wash on near-black surfaces.
  ///
  /// Album art is often very dark -- a black-and-white cover, a moody indie
  /// record -- and its dominant colour can be nearly indistinguishable from the
  /// black it is glowing against. Clamping the HSL lightness up (and the
  /// saturation to something above grey) keeps every track's ambience legible
  /// without touching colours that are already bright enough.
  static Color liftedForGlow(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.45, 1.0).toDouble())
        .withLightness(hsl.lightness.clamp(0.45, 0.72).toDouble())
        .toColor();
  }

  // Text & Content Colors
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0x99F8FAFC);
  static const Color textTertiaryDark = Color(0x66F8FAFC);

  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0x990F172A);
  static const Color textTertiaryLight = Color(0x660F172A);
}
