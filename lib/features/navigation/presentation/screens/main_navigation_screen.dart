import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/widgets/glass_navigation_bar.dart';
import 'package:wavely/features/collection/presentation/screens/collection_screen.dart';
import 'package:wavely/features/home/presentation/screens/home_screen.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/player/presentation/screens/now_playing_expanded_screen.dart';
import 'package:wavely/features/player/presentation/widgets/mini_player.dart';
import 'package:wavely/features/search/presentation/screens/search_screen.dart';

/// Index of each tab, so nothing has to hardcode a position.
class ShellTabs {
  const ShellTabs._();

  /// The main player, where the app opens.
  static const int home = 0;

  /// The expanded view of whatever is playing.
  static const int player = kPlayerTabIndex;

  /// Free-text search over the library.
  static const int search = 2;

  /// All songs, albums, artists, favourites, history, and playlists.
  ///
  /// This tab absorbed the old Browse tab: albums, artists and genre playlists
  /// now live here as sections, so there is one place to get at the library.
  static const int library = 3;
}

/// Shell holding the four tabs and the glass navigation bar.
///
/// The expanded player is a tab rather than a pushed route, so the mini player
/// can move to it through [ShellController] without leaving a second copy of the
/// player stacked on top of the shell -- and so the back control in the player is
/// a tab switch rather than a pop.
class MainNavigationScreen extends StatelessWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shellCtrl = context.watch<ShellController>();
    // The mini player lives in the shell dock rather than on any one tab, so
    // it survives tab switches and joins the navigation bar as a single
    // window. Hidden on the expanded player tab itself, where it would echo
    // the controls already on screen. Watched (not selected) so the dock
    // appears the moment a track loads.
    final showMini = context.select<PlayerController, bool>(
          (player) => player.currentSong != null,
        ) &&
        shellCtrl.currentIndex != kPlayerTabIndex;

    // Re-declared here rather than only in main(): the system overwrites the
    // overlay style on tab switches and route pushes, and the contrast scrim
    // Android draws behind the gesture bar when it thinks a transparent bar
    // needs "help" comes back with it. That scrim is the white rectangle this
    // exists to keep gone.
    const overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
            children: [
              Positioned.fill(
                child: IndexedStack(
                  index: shellCtrl.currentIndex,
                  children: const [
                    HomeScreen(),
                    NowPlayingExpandedScreen(),
                    SearchScreen(),
                    CollectionScreen(),
                  ],
                ),
              ),
              // One docked window: the mini player joins the navigation bar
              // with zero gap and square meeting edges. SafeArea keeps the
              // gesture bar clear while the dock stays edge to edge.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showMini) const MiniPlayer(),
                      GlassNavigationBar(
                        currentIndex: shellCtrl.currentIndex,
                        onTap: shellCtrl.selectTab,
                  items: const [
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
                  ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
        ),
      ),
    );
  }
}
