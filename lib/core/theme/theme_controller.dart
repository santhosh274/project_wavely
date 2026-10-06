import 'package:flutter/material.dart';
import 'ios27_glass_theme.dart';

enum GlassThemeMode { dark, light, auto }

/// Manages iOS 27 Glassmorphism Theme Settings & Customizations
class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  double _glassBlurSigma = IOS27GlassTheme.blurStandard;
  double _glassOpacity = 0.25;
  bool _dynamicArtworkColorEnabled = true;

  ThemeMode get themeMode => _themeMode;
  double get glassBlurSigma => _glassBlurSigma;
  double get glassOpacity => _glassOpacity;
  bool get dynamicArtworkColorEnabled => _dynamicArtworkColorEnabled;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void setBlurSigma(double sigma) {
    _glassBlurSigma = sigma;
    notifyListeners();
  }

  void setGlassOpacity(double opacity) {
    _glassOpacity = opacity;
    notifyListeners();
  }

  void setDynamicArtworkColor(bool enabled) {
    _dynamicArtworkColorEnabled = enabled;
    notifyListeners();
  }
}
