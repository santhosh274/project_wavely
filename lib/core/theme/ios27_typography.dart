import 'package:flutter/material.dart';

import 'ios27_colors.dart';

/// iOS 27 Typography Hierarchy.
///
/// Inter is bundled in `assets/fonts` and declared in pubspec, so every weight
/// resolves locally: the previous google_fonts setup fetched each weight over
/// the network at runtime, which stalled first paint and threw on offline
/// devices.
class IOS27Typography {
  IOS27Typography._();

  static const String _family = 'Inter';

  static TextStyle displayLarge({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: isDark ? IOS27Colors.textPrimaryDark : IOS27Colors.textPrimaryLight,
      );

  static TextStyle titleLarge({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: isDark ? IOS27Colors.textPrimaryDark : IOS27Colors.textPrimaryLight,
      );

  static TextStyle titleMedium({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: isDark ? IOS27Colors.textPrimaryDark : IOS27Colors.textPrimaryLight,
      );

  static TextStyle bodyLarge({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        color: isDark ? IOS27Colors.textPrimaryDark : IOS27Colors.textPrimaryLight,
      );

  static TextStyle bodyMedium({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: isDark ? IOS27Colors.textSecondaryDark : IOS27Colors.textSecondaryLight,
      );

  static TextStyle caption({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: isDark ? IOS27Colors.textTertiaryDark : IOS27Colors.textTertiaryLight,
      );

  static TextStyle glassButton({bool isDark = true}) => TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: isDark ? IOS27Colors.textPrimaryDark : IOS27Colors.textPrimaryLight,
      );
}
