import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_container.dart';
import '../theme/ios27_glass_theme.dart';

class GlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// iOS 27 Glass Navigation Bar.
///
/// A floating capsule rather than a full-width strip: the bar is inset from the
/// screen edges and lifted clear of the gesture bar, so it reads as a piece of
/// hardware hovering over the content instead of a chrome band welded to the
/// bottom of the screen. It sits directly under the mini player with the same
/// side margins, and the two together form a floating dock.
///
/// The capsule is split into four **equal** segments -- one per tab, each
/// claiming exactly a quarter of the bar and centring its own contents. That is
/// what keeps the buttons evenly spaced with identical gaps and identical insets
/// at either end, the way a Spotify bottom bar reads. Sizing each slot to its own
/// content instead (loose flex, natural width) leaves the leftover width piled up
/// at the trailing edge, which is what made the buttons look shoved to the left
/// with an empty strip on the right.
///
/// The buttons themselves are kept deliberately quiet. The current tab is marked
/// by one small rounded tile behind its icon, the accent tint and the filled
/// glyph; everything else is a plain icon. There is no outer pill, no glow and no
/// sheen on a tab, because those are three pieces of decoration competing to say
/// the same thing that the tile and the glyph already say.
///
/// Tab changes animate rather than snap: the tile fades in under the new icon,
/// the icon cross-fades to its filled variant, and the label fades up beneath it.
/// Every animation is one-shot (it runs on selection and finishes), so a tap
/// reads as liquid movement without ever leaving an animation controller running
/// in the background.
class GlassNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  /// The bar's own height, excluding the floating margins.
  static const double barHeight = 66.0;

  /// Horizontal inset. Shared with the mini player's margin so the dock's two
  /// cards line up edge to edge.
  static const double sideMargin = 18.0;

  /// Cap on the dock's width. On a phone this never binds; on a tablet it keeps
  /// the capsule from stretching into a band across the whole screen, which is
  /// what makes a floating capsule stop looking like a floating capsule. The
  /// mini player caps at the same width so the two stay aligned.
  static const double maxWidth = 560.0;

  /// The size of the active tab's icon tile. Fixed, so a tab's icon sits in the
  /// same place before and after it becomes current -- a tile that appeared
  /// under the icon would otherwise shove the glyph sideways.
  static const double _tileWidth = 38.0;
  static const double _tileHeight = 34.0;

  /// The label's slot below the icon. Reserved whether or not a label is
  /// showing, so all four icons share one baseline and a tab never nudges
  /// upwards the moment it becomes current.
  static const double _labelHeight = 15.0;

  const GlassNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          // Floats above the gesture bar rather than meeting the screen edge, and
          // stops short of the sides, so the content behind it stays visible
          // around the capsule.
          padding: const EdgeInsets.fromLTRB(sideMargin, 0.0, sideMargin, 10.0),
          child: GlassContainer(
            height: barHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
            borderRadius: barHeight / 2,
            blurSigma: IOS27GlassTheme.blurHeavy,
            tintColor: Colors.black.withValues(alpha: 0.42),
            borderColor: Colors.white.withValues(alpha: 0.10),
            shadows: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 34,
                spreadRadius: -6,
                offset: const Offset(0, 16),
              ),
            ],
            child: Row(
              // Stretch so each tab's tap target is the full height of the
              // capsule, not just the icon: a 21px glyph is a small thing to
              // hit on a moving bus.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(items.length, (index) {
                final isSelected = index == currentIndex;
                final item = items[index];

                // An equal share of the bar for every tab. Expanded (tight fit)
                // rather than Flexible (loose fit): the slot claims its quarter
                // of the width even when its contents are narrower, so the four
                // buttons are spread evenly with no leftover strip at the end.
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // A tick under the finger the instant the tab moves: the
                      // cheapest way to make a tap feel like it landed.
                      if (!isSelected) HapticFeedback.selectionClick();
                      onTap(index);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // The active tab's only chrome: a small rounded tile
                        // behind the icon. Transparent (but still taking its
                        // space) when inactive, so nothing shifts.
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: _tileWidth,
                          height: _tileHeight,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary.withValues(alpha: 0.20)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12.0),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.9,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Icon(
                              isSelected ? item.activeIcon : item.icon,
                              // Keyed so the switcher treats the filled and
                              // outline icons as two children to cross-fade.
                              key: ValueKey(isSelected),
                              color: isSelected
                                  ? primary
                                  : Colors.white.withValues(alpha: 0.55),
                              size: 21.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        // Sits under the icon rather than beside it: a slot this
                        // narrow only has room for a centred caption, not an
                        // icon and a caption in a row. The ellipsis is the
                        // safety net for the longest label at the narrowest
                        // width; at normal sizes it never engages.
                        SizedBox(
                          height: _labelHeight,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                            child: isSelected
                                ? Text(
                                    item.label,
                                    key: const ValueKey(true),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: primary,
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.1,
                                    ),
                                  )
                                : const SizedBox.shrink(key: ValueKey(false)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
