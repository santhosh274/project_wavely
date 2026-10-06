import 'package:flutter/foundation.dart';

/// Index of the tab showing the expanded player.
///
/// Declared as a constant so the mini player and the shell cannot drift apart:
/// tapping the mini player used to push a route, which stacked a second copy of
/// the player over the shell instead of switching tabs.
const int kPlayerTabIndex = 1;

/// Owns which tab the navigation shell is showing.
///
/// The mini player sits deep inside the tree and needs to move the shell to the
/// player tab, so it cannot simply call `Navigator.push` without leaving the
/// shell's own state behind. Passing the index down through every constructor
/// would work too, but a small controller keeps the wiring in one place.
class ShellController extends ChangeNotifier {
  int _currentIndex = 0;

  /// Which tab is currently visible.
  int get currentIndex => _currentIndex;

  /// How many tabs the shell holds.
  ///
  /// Asserted against in [selectTab]: an out-of-range index would otherwise be
  /// accepted here and blow up inside the IndexedStack, far from the mistake.
  static const int tabCount = 4;

  /// Switch to [index]. No-op when already there, so a tap on the mini player
  /// while the player is open does nothing instead of rebuilding.
  void selectTab(int index) {
    if (index < 0 || index >= tabCount) {
      throw RangeError.index(index, this, 'index', null, tabCount);
    }
    if (index == _currentIndex) return;
    _currentIndex = index;
    notifyListeners();
  }
}