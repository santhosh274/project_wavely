import 'package:flutter/material.dart';
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

/// iOS 27 Glass Navigation Bar forming the bottom half of the shell dock.
///
/// Flush and square-topped so it joins the mini player above with no seam:
/// together they read as one docked window rather than floating pills.
///

/// Tab changes animate rather than snap: the active pill springs between
/// states, the icon cross-fades to its filled variant, and the label grows in
/// with its pill. Every animation is one-shot (they run on selection and
/// finish), so a tap reads as liquid movement without ever leaving an
/// animation controller running in the background.
class GlassNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    // No outer margins: the bar is the dock's bottom edge, edge to edge.
    return GlassContainer(
        height: 68.0,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        borderRadius: 0,
        blurSigma: IOS27GlassTheme.blurHeavy,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 30,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        ],
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final isSelected = index == currentIndex;
            final item = items[index];

            // The selected item takes double share, so its label has room at
            // steady state; unselected items stay compact. Loose fit lets
            // each item use only what it needs.
            return Flexible(
              flex: isSelected ? 2 : 1,
              child: GestureDetector(
                onTap: () => onTap(index),
                behavior: HitTestBehavior.opaque,
                child: AnimatedScale(
                  // A small press-in on everything while the selected item
                  // springs up: the bar as a whole feels elastic rather than
                  // swapping two fixed layouts.
                  scale: isSelected ? 1.0 : 0.94,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 8.0,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(IOS27GlassTheme.radiusPill),
                      // A specular sheen travels with the active pill, so the
                      // highlight reads as light moving across glass rather
                      // than a background colour swap.
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.14),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.7,
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
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white.withValues(alpha: 0.6),
                            size: 22.0,
                          ),
                        ),
                        // Grows the row to fit the label instead of popping
                        // it in, so the neighbouring items glide aside. The
                        // Flexible + ellipsis pair keeps the transient moment
                        // when two labels are mid-animation from ever
                        // overflowing the bar on narrow screens.
                        Flexible(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            child: isSelected
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 6.0),
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : const SizedBox(width: 6.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
    );
  }
}
