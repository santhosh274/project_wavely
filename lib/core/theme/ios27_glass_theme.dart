import 'package:flutter/material.dart';
import 'ios27_colors.dart';
import 'ios27_typography.dart';

/// iOS 27 Glassmorphism Theme Configuration & Presets
class IOS27GlassTheme {
  IOS27GlassTheme._();

  // Glass Blur Presets.
  //
  // Raised from the earlier values so the frost reads at arm's length the way
  // Apple's liquid glass does: strong enough that content behind a surface
  // melts into colour rather than staying legible. The filters in
  // [UiImageFilterCompat.liquidBlur] add a saturation boost on top, which is
  // what makes the blur look "wet" instead of merely grey.
  static const double blurSubtle = 18.0;
  static const double blurStandard = 32.0;
  static const double blurHeavy = 55.0;
  static const double blurUltra = 80.0;

  // Corner Radii
  static const double radiusSmall = 16.0;
  static const double radiusMedium = 24.0;
  static const double radiusLarge = 32.0;
  static const double radiusPill = 100.0;

  /// Returns overall ThemeData with iOS 27 glass styling.
  ///
  /// [accent] re-tints the app's selection and accent surfaces -- switches,
  /// checkboxes, radios, sliders, progress, text selection -- to the playing
  /// track's most prominent artwork colour. Null keeps the default indigo.
  static ThemeData darkTheme({Color? accent}) {
    final primary = accent ?? IOS27Colors.electricIndigo;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: IOS27Colors.neonCyan,
        surface: IOS27Colors.glassDarkSurface,
        onSurface: IOS27Colors.textPrimaryDark,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.35),
        selectionHandleColor: primary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.5)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      textTheme: TextTheme(
        displayLarge: IOS27Typography.displayLarge(isDark: true),
        titleLarge: IOS27Typography.titleLarge(isDark: true),
        titleMedium: IOS27Typography.titleMedium(isDark: true),
        bodyLarge: IOS27Typography.bodyLarge(isDark: true),
        bodyMedium: IOS27Typography.bodyMedium(isDark: true),
        labelLarge: IOS27Typography.glassButton(isDark: true),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
    );
  }

  static ThemeData lightTheme({Color? accent}) {
    final primary = accent ?? IOS27Colors.electricIndigo;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: IOS27Colors.neonCyan,
        surface: IOS27Colors.glassLightSurface,
        onSurface: IOS27Colors.textPrimaryLight,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.35),
        selectionHandleColor: primary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.5)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      textTheme: TextTheme(
        displayLarge: IOS27Typography.displayLarge(isDark: false),
        titleLarge: IOS27Typography.titleLarge(isDark: false),
        titleMedium: IOS27Typography.titleMedium(isDark: false),
        bodyLarge: IOS27Typography.bodyLarge(isDark: false),
        bodyMedium: IOS27Typography.bodyMedium(isDark: false),
        labelLarge: IOS27Typography.glassButton(isDark: false),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
    );
  }
}
