import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/widgets/glass_container.dart';
import 'package:wavely/core/widgets/glass_navigation_bar.dart';

/// The bar's real items, including the longest label it has to fit ("Library").
const _items = <GlassNavItem>[
  GlassNavItem(
    icon: CupertinoIcons.house,
    activeIcon: CupertinoIcons.house_fill,
    label: 'Home',
  ),
  GlassNavItem(
    icon: CupertinoIcons.music_note_2,
    activeIcon: CupertinoIcons.music_note_list,
    label: 'Player',
  ),
  GlassNavItem(
    icon: CupertinoIcons.search,
    activeIcon: CupertinoIcons.search_circle_fill,
    label: 'Search',
  ),
  GlassNavItem(
    icon: CupertinoIcons.list_bullet,
    activeIcon: CupertinoIcons.list_bullet_indent,
    label: 'Library',
  ),
];

void main() {
  /// Mount the bar alone at [width] logical points, so layout can be judged
  /// without the shell's dock, artwork or providers in the way.
  Future<void> pumpBar(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
              builder: (context, setState) => GlassNavigationBar(
                currentIndex: selected,
                onTap: (index) => setState(() => selected = index),
                items: _items,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('layout', () {
    /// Fail unless every neighbouring pair is the same distance apart.
    void expectEvenGaps(List<double> centers) {
      final gaps = <double>[
        for (var i = 1; i < centers.length; i++) centers[i] - centers[i - 1],
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, 0.5));
      }
    }

    testWidgets('divides the capsule into equal, evenly spaced segments', (
      tester,
    ) async {
      await pumpBar(tester, 360.0);
      await tester.pumpAndSettle();

      // The current tab shows its filled glyph, the rest their outline one.
      double centerOf(int index, int current) => tester
          .getCenter(
            find.byIcon(
              current == index ? _items[index].activeIcon : _items[index].icon,
            ),
          )
          .dx;

      // Home starts selected.
      var centers = <double>[
        for (var i = 0; i < _items.length; i++) centerOf(i, 0),
      ];
      expectEvenGaps(centers);

      // Equal insets at both ends of the capsule: no leftover width piled up
      // against the right edge, which is the bug this pins.
      final capsule = tester.getRect(find.byType(GlassContainer));
      expect(
        centers.first - capsule.left,
        closeTo(capsule.right - centers.last, 0.5),
      );

      // Now select the widest label ('Library') and check the spacing is
      // unaffected by the caption that appears under it.
      await tester.tap(find.byIcon(_items[3].icon));
      await tester.pumpAndSettle();

      centers = <double>[
        for (var i = 0; i < _items.length; i++) centerOf(i, 3),
      ];
      expectEvenGaps(centers);
      expect(
        centers.first - capsule.left,
        closeTo(capsule.right - centers.last, 0.5),
      );
    });

    // 320 is the narrowest phone the app is expected to run on, and the capsule
    // is where the longest label runs out of room first.
    for (final width in <double>[320.0, 360.0, 430.0]) {
      testWidgets(
        'holds together at ${width.toInt()}pt through every tab swap',
        (tester) async {
          await pumpBar(tester, width);

          // Walk a cycle, including revisiting a tab. Each move is stepped frame
          // by frame, because the overlap -- two labels mid-animation -- is the
          // moment a bar this narrow would overflow.
          for (final index in <int>[1, 2, 3, 0, 3, 1, 0]) {
            await tester.tap(find.byIcon(_items[index].icon));
            for (var frame = 0; frame < 24; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
          }
        },
      );
    }
  });

  group('buttons', () {
    testWidgets('only the current tab wears a label and its filled glyph', (
      tester,
    ) async {
      await pumpBar(tester, 360.0);

      for (final index in <int>[2, 3, 1, 0]) {
        // An unselected tab is found by its outline icon, the way the shell's
        // own tests do it: the bar renders one glyph per slot.
        await tester.tap(find.byIcon(_items[index].icon));
        await tester.pumpAndSettle();

        expect(find.byIcon(_items[index].activeIcon), findsOneWidget);
        expect(find.text(_items[index].label), findsOneWidget);

        // Exactly one label on the bar: the minimalist read depends on the
        // inactive tabs saying nothing.
        for (var other = 0; other < _items.length; other++) {
          if (other == index) continue;
          expect(
            find.text(_items[other].label),
            findsNothing,
            reason: '${_items[other].label} should not be showing',
          );
        }
      }
    });
  });
}
