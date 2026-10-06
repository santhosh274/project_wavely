import 'package:flutter/material.dart';
import 'package:wavely/core/theme/ios27_glass_theme.dart';
import 'glass_container.dart';

/// Floating iOS 27 Glass Top App Bar
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final double height;

  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.height = 64.0,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: GlassContainer(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          borderRadius: IOS27GlassTheme.radiusPill,
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 8.0),
              ],
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleLarge!,
                  overflow: TextOverflow.ellipsis,
                  child: title,
                ),
              ),
              ...?actions,
            ],
          ),
        ),
      ),
    );
  }
}
