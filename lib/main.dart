import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';

import 'app/wavely_providers.dart';
import 'core/theme/ios27_colors.dart';
import 'core/theme/ios27_glass_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/artwork_image.dart';
import 'features/navigation/presentation/screens/main_navigation_screen.dart';
import 'features/player/controllers/player_controller.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Runs the player inside a media session hosted by a foreground service.
  // This is what keeps the music going when the app is minimised or the screen
  // is locked, and what fills the notification and lock screen controls. It has
  // to happen before the first AudioPlayer is built, because it installs the
  // platform implementation the player talks to.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.wavely.app.wavely.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationChannelDescription:
        'Controls for the song Wavely is playing.',
    // Kept dismissible: an ongoing notification the user cannot swipe away
    // becomes something they mute instead, which they then do for every song.
    androidNotificationOngoing: false,
    // The MediaItem cover is a content:// URI, which the notification service
    // loads itself straight from the media store (fast thumbnail path on
    // API 29+). The Dart preloader only speaks http(s) -- enabling it makes
    // every queued track log an "Unsupported scheme 'content'" error and the
    // artwork never arrives that way. artDownscale still applies: the native
    // loader uses it to size the notification bitmap.
    preloadArtwork: false,
    artDownscaleWidth: 512,
    artDownscaleHeight: 512,
  );

  // Declares the audio as music rather than speech: that is what gets the right
  // routing and volume behaviour, makes navigation prompts duck the music, and
  // on iOS keeps the session alive while the app is in the background.
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // Set system UI to immersive transparent glass style. Drawing behind the
  // gesture bar needs edge-to-edge mode as well as the transparent colours:
  // without it Android keeps a strip of window reserved at the bottom, and on
  // Android 10+ it additionally enforces a contrast scrim -- the white
  // rectangle users see behind the gesture bar -- unless
  // systemNavigationBarContrastEnforced is switched off.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(MultiProvider(providers: wavelyProviders(), child: const WavelyApp()));
}

class WavelyApp extends StatefulWidget {
  const WavelyApp({super.key});

  @override
  State<WavelyApp> createState() => _WavelyAppState();
}

class _WavelyAppState extends State<WavelyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the foreground is the last point at which the session can
    // reliably be written: after this the process may be killed at any moment,
    // and what was saved is what the next launch restores.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      context.read<PlayerController>().flushState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeCtrl = context.watch<ThemeController>();
    // Hoisted above the MaterialApp so pushed routes -- album and playlist
    // details, the settings page, bottom sheets -- share the one artwork cache
    // the shell already filled. Inside the shell it would be unreachable from
    // every one of them.
    // Selected, not watched: a full watch rebuilds MaterialApp -- the entire
    // app -- on every play/pause/seek notification. Only the palette seed
    // matters here; the artwork cache object below is stable for the session.
    final accentSeed = context.select<PlayerController, Color>(
      (player) => player.ambientPrimary,
    );

    // The app's accent follows the playing track: the most prominent artwork
    // colour, lifted so dark covers still read. Rebuilds on palette change
    // only; disabled honours the settings toggle with indigo.
    final accent = themeCtrl.dynamicArtworkColorEnabled
        ? IOS27Colors.liftedForGlow(accentSeed)
        : null;

    return ArtworkScope(
      service: context.read<PlayerController>().artworkService,
      child: MaterialApp(
        title: 'Wavely Music',
        debugShowCheckedModeBanner: false,
        themeMode: themeCtrl.themeMode,
        theme: IOS27GlassTheme.lightTheme(accent: accent),
        darkTheme: IOS27GlassTheme.darkTheme(accent: accent),
        home: const MainNavigationScreen(),
        routes: {'/settings': (context) => const SettingsScreen()},
      ),
    );
  }
}
