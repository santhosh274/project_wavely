import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/services/artwork_service.dart';
import '../core/services/audio_engine.dart';
import '../core/services/local_media_service.dart';
import '../core/services/playback_state_store.dart';
import '../core/theme/theme_controller.dart';
import '../features/library/controllers/library_controller.dart';
import '../features/navigation/controllers/shell_controller.dart';
import '../features/player/controllers/player_controller.dart';

/// The provider tree the app runs on.
///
/// Exposed as a function rather than written inline in `main()` so that widget
/// tests can mount the *same* wiring with a fake backend swapped in. The wiring
/// is where the interesting behaviour lives -- the player reporting track
/// changes to the library, the shell deciding which tab to show -- and a test
/// that rebuilt the tree by hand would quietly stop covering it as soon as the
/// app changed. Every parameter is optional: production passes none.
List<SingleChildWidget> wavelyProviders({
  LocalMediaService? mediaService,
  AudioEngine? audioService,
  ArtworkService? artworkService,
  PlaybackStateStore? stateStore,
}) {
  return [
    ChangeNotifierProvider(create: (_) => ThemeController()),
    ChangeNotifierProvider(create: (_) => ShellController()),
    // Declared before the player, because the player is built through a proxy
    // that looks this provider up: nesting it the other way round makes
    // `Provider.of<LibraryController>` throw "could not find the correct
    // Provider" on the first frame, taking the whole app down with it.
    ChangeNotifierProvider(
      create: (_) => LibraryController(mediaService: mediaService),
    ),
    // The player reports every track that becomes current to the library, so
    // "recently played" reflects what was actually heard -- including tracks the
    // queue rolled into on its own. The callback is re-pointed on every rebuild
    // so it always reaches the live library instance.
    //
    // The wiring runs the other way too: each completed scan is handed to the
    // player, which is what lets it rebuild the queue the last session was
    // playing. The stored queue is a list of ids, so it cannot be resolved until
    // the library has been read.
    ChangeNotifierProxyProvider<LibraryController, PlayerController>(
      create: (_) => PlayerController(
        audioService: audioService,
        artworkService: artworkService,
        stateStore: stateStore,
      ),
      update: (_, library, player) {
        final controller = player!;
        controller.onTrackStarted = library.recordPlayed;
        library.onLoaded = (songs) async {
          // Warm the covers first so the rows land painted; restoring then
          // picks up the session on top of an already-filled cache.
          controller.warmArtworkCache(songs);
          await controller.restorePlayback(songs: songs);
        };
        return controller;
      },
    ),
  ];
}
