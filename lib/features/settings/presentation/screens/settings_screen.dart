import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/services/audio_player_service.dart' show RepeatBehaviour;
import 'package:wavely/core/theme/ios27_colors.dart';
import 'package:wavely/core/utils/formatters.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';

/// The profile page: settings, playback preferences and listening stats.
///
/// Reachable from the avatar on the home tab. Every number here is counted from
/// real library state rather than being written in, so the page cannot drift out
/// of sync with what the app is actually doing.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    // Read from the installed bundle rather than hardcoding the pubspec version,
    // which would keep reporting the value it had on the day it was typed.
    _packageInfo = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    final playerCtrl = context.watch<PlayerController>();

    final allSongs = libraryCtrl.allSongs;
    final runtime = libraryCtrl.totalDurationOf(allSongs);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 32.0),
            children: [
              _TopBar(),
              const SizedBox(height: 8.0),
              const _ProfileCard(),
              const SizedBox(height: 24.0),
              _Section(
                title: 'Your library',
                children: [
                  _Stat(
                    icon: CupertinoIcons.music_note,
                    label: 'Songs',
                    value: '${allSongs.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.clock,
                    label: 'Total runtime',
                    value: formatRuntime(runtime),
                  ),
                  _Stat(
                    icon: CupertinoIcons.music_albums,
                    label: 'Albums',
                    value: '${libraryCtrl.albums.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.person_2,
                    label: 'Artists',
                    value: '${libraryCtrl.artists.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.list_bullet,
                    label: 'Playlists',
                    value: '${libraryCtrl.playlists.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.square_stack_3d_up,
                    label: 'Your playlists',
                    value: '${libraryCtrl.userPlaylists.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.heart,
                    label: 'Favourites',
                    value: '${libraryCtrl.favorites.length}',
                  ),
                  _Stat(
                    icon: CupertinoIcons.play_circle,
                    label: 'Tracks played',
                    value: '${libraryCtrl.recentlyPlayed.length}',
                    footnote: 'Since this app was last opened',
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              _Section(
                title: 'Playback',
                children: [
                  _SwitchRow(
                    icon: CupertinoIcons.shuffle,
                    title: 'Shuffle',
                    subtitle: 'Play the queue in a random order',
                    value: playerCtrl.isShuffle,
                    onChanged: (_) => playerCtrl.toggleShuffle(),
                  ),
                  _RepeatRow(),
                  _SliderRow(
                    icon: CupertinoIcons.volume_up,
                    title: 'Volume',
                    value: playerCtrl.volume,
                    onChanged: playerCtrl.setVolume,
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              _Section(
                title: 'This device',
                children: [
                  _ActionRow(
                    icon: CupertinoIcons.arrow_clockwise,
                    title: 'Rescan this device',
                    subtitle: libraryCtrl.isLoading
                        ? 'Reading the media store...'
                        : 'Pick up tracks added since the last scan',
                    onTap: libraryCtrl.isLoading ? null : libraryCtrl.loadLibrary,
                  ),
                  _ActionRow(
                    icon: CupertinoIcons.location,
                    title: 'Grant media access',
                    subtitle: 'Open the system settings for this app',
                    onTap: libraryCtrl.openSystemSettings,
                  ),
                ],
              ),
              const SizedBox(height: 20.0),
              _Section(
                title: 'About',
                children: [
                  _AboutRow(info: _packageInfo),
                ],
              ),
            ],
          ),
        ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(
            CupertinoIcons.chevron_left,
            color: Colors.white,
            size: 28.0,
          ),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              fontSize: 26.0,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Avatar and the two numbers that frame the page.
///
/// Deliberately has no sign-in: there is no account system, and a "Log in"
/// button that does nothing would be worse than not having one.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    final libraryCtrl = context.watch<LibraryController>();
    final playerCtrl = context.watch<PlayerController>();
    final current = playerCtrl.currentSong;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.0),
        gradient: LinearGradient(
          colors: [
            playerCtrl.ambientPrimary.withValues(alpha: 0.5),
            playerCtrl.ambientSecondary.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 64.0,
            height: 64.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: const Icon(
              CupertinoIcons.person_fill,
              color: Colors.white,
              size: 34.0,
            ),
          ),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Local listener',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  current == null
                      ? 'Nothing playing right now'
                      : 'Listening to ${current.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13.0,
                  ),
                ),
                const SizedBox(height: 2.0),
                Text(
                  libraryCtrl.needsPermission
                      ? 'Media access not granted'
                      : '${libraryCtrl.allSongs.length} tracks on this device',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12.0,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Each row gets its own transparent Material so its ink splash
              // lands on top of this panel's tint. Without it the splash would
              // be painted on the Material far above and hidden behind the
              // decoration, and Flutter flags that in debug builds.
              for (final child in children)
                Material(
                  type: MaterialType.transparency,
                  child: child,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One counted statistic. Read-only, so it shows no chevron.
class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Explains where the number comes from when it is not simply a list length.
  final String? footnote;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: footnote == null
          ? null
          : Text(
              footnote!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
      trailing: Text(
        value,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      activeTrackColor: IOS27Colors.electricIndigo,
    );
  }
}

/// Repeat is a three-way cycle, so it is stepped with a button rather than
/// pretending to be a boolean switch.
class _RepeatRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final playerCtrl = context.watch<PlayerController>();
    final (label, detail) = switch (playerCtrl.repeatMode) {
      RepeatBehaviour.off => ('Repeat', 'Play through the queue once'),
      RepeatBehaviour.all => ('Repeat all', 'Loop the queue when it ends'),
      RepeatBehaviour.one => ('Repeat one', 'Loop the current track'),
    };

    return ListTile(
      leading: const Icon(CupertinoIcons.repeat, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        detail,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      trailing: TextButton(
        onPressed: () => playerCtrl.toggleRepeat(),
        child: Text(
          switch (playerCtrl.repeatMode) {
            RepeatBehaviour.off => 'Off',
            RepeatBehaviour.all => 'All',
            RepeatBehaviour.one => 'One',
          },
          style: const TextStyle(color: IOS27Colors.neonCyan),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 16.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(color: Colors.white)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.0,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                    activeTrackColor: IOS27Colors.neonCyan,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44.0,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      // A chevron is only shown when the row can actually be tapped, so it never
      // advertises a target that does nothing.
      trailing: onTap == null
          ? null
          : Icon(
              CupertinoIcons.chevron_right,
              color: Colors.white.withValues(alpha: 0.5),
            ),
      onTap: onTap,
    );
  }
}

/// Version and build number, read from the installed bundle.
class _AboutRow extends StatelessWidget {
  final Future<PackageInfo> info;

  const _AboutRow({required this.info});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(CupertinoIcons.info_circle, color: Colors.white70),
      title: const Text(
        'Version',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: FutureBuilder<PackageInfo>(
        future: info,
        builder: (context, snapshot) => Text(
          switch (snapshot.connectionState) {
            // Until the platform answers there is genuinely nothing to show, so
            // this says so rather than falling back to a made-up number.
            ConnectionState.done when snapshot.hasError => 'Unavailable',
            ConnectionState.done => '${snapshot.data!.version} '
                '(build ${snapshot.data!.buildNumber})',
            _ => 'Reading...',
          },
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}