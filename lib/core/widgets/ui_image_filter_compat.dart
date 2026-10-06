import 'dart:ui' as ui;

class UiImageFilterCompat {
  static ui.ImageFilter blur({required double sigmaX, required double sigmaY}) {
    return ui.ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY);
  }

  /// The liquid-glass filter: blur composed with a saturation boost.
  ///
  /// Plain blur drains the colour out of whatever is behind a surface -- a
  /// bright album cover behind frosted glass turns into a grey smear. Apple's
  /// material does the opposite: it blurs *and* pushes saturation back up,
  /// which is what makes their glass read as coloured light rather than fog.
  /// The [saturation] matrix is applied after the blur, in a single composed
  /// filter, so it costs one extra pass over the blurred pixels only.
  static ui.ImageFilter liquidBlur({
    required double sigma,
    double saturation = 1.9,
  }) {
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      inner: ui.ColorFilter.matrix(_saturationMatrix(saturation)),
    );
  }

  /// Colour matrix that scales saturation around the luma vector
  /// (0.213, 0.715, 0.072). s = 1 is a no-op; s > 1 oversaturates.
  static List<double> _saturationMatrix(double s) => <double>[
    0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
    0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}
