import 'package:flutter/material.dart';
import 'glass_container.dart';
import '../theme/ios27_colors.dart';
import '../theme/ios27_glass_theme.dart';

/// iOS 27 Glass Segmented Tab Bar Switcher
class GlassSegmentedControl<T> extends StatelessWidget {
  final Map<T, String> children;
  final T groupValue;
  final ValueChanged<T> onValueChanged;
  final EdgeInsetsGeometry padding;

  const GlassSegmentedControl({
    super.key,
    required this.children,
    required this.groupValue,
    required this.onValueChanged,
    this.padding = const EdgeInsets.all(4.0),
  });

  @override
  Widget build(BuildContext context) {
    final keys = children.keys.toList();

    return GlassContainer(
      padding: padding,
      borderRadius: IOS27GlassTheme.radiusPill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: keys.map((key) {
          final isSelected = key == groupValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onValueChanged(key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? IOS27Colors.electricIndigo.withValues(alpha: 0.85)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(IOS27GlassTheme.radiusPill),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: IOS27Colors.electricIndigo.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    children[key]!,
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
