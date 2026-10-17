import 'dart:async';

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/services/artwork_service.dart';
import '../core/services/audio_engine.dart';
import '../core/services/library_filter_store.dart';
import '../core/services/local_media_service.dart';
import '../core/services/playback_state_store.dart';
import '../core/theme/theme_controller.dart';
import '../features/library/controllers/library_controller.dart';
import '../features/navigation/controllers/shell_controller.dart';
import '../features/player/controllers/player_controller.dart';
import '../features/room/controllers/room_controller.dart';
import '../features/room/services/local_network_permission.dart';
import '../features/room/services/room_audio_cache.dart';
import '../features/room/services/room_transport.dart';

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
  PlaybackSnapshot? initialSnapshot,
  LibraryFilterStore? filterStore,
  RoomTransportFactory? roomTransportFactory,
  RoomAudioCache? roomAudioCache,
  LocalNetworkPermission? localNetworkPermission,
}) {
  return [
    // The local-network permission a listening room's sockets need. One seam for
    // the whole app rather than one per user: the launch-time prompt asks
    // through it, and a room asks through the same one if that was refused, so a
    // test can answer for both.
    Provider<LocalNetworkPermission>.value(
      value: localNetworkPermission ?? const PlatformLocalNetworkPermission(),
    ),
    ChangeNotifierProvider(create: (_) => ThemeController()),
    ChangeNotifierProvider(create: (_) => ShellController()),
    // Declared before the player, because the player is built through a proxy
    // that looks this provider up: nesting it the other way round makes
    // `Provider.of<LibraryController>` throw "could not find the correct
    // Provider" on the first frame, taking the whole app down with it.
    ChangeNotifierProvider(
      create: (_) => LibraryController(
        mediaService: mediaService,
        // Defaults to the file-backed store in production, so the user's
        // folder / duration exclusions survive a relaunch.
        filterStore: filterStore,
      ),
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
      create: (_) {
        final controller = PlayerController(
          audioService: audioService,
          artworkService: artworkService,
          stateStore: stateStore,
          preloadedSnapshot: initialSnapshot,
        );
        // The stored session goes back the moment the player exists, not when the
        // media scan happens to finish. It carries the queue itself, so this is
        // what makes the app open on the song and the list the last session left
        // playing instead of on "Nothing playing" -- which on a device with a
        // large library lasted as long as the scan did. Not awaited: the first
        // frame must not wait on a file read, and a launch with nothing stored
        // is a no-op.
        unawaited(controller.restorePlayback());
        return controller;
      },
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
    // The room sits above both: it drives the player while it is up, and it has
    // to resolve the host's tracks against the library this device actually
    // holds. Its library source is a function rather than a list because every
    // scan replaces the songs wholesale.
    ChangeNotifierProxyProvider2<LibraryController, PlayerController,
        RoomController>(
      // Read rather than injected: a proxy's `create` runs before its two
      // upstream values are supplied on the first frame, and the room needs the
      // player from the moment it exists.
      create: (context) => RoomController(
        player: context.read<PlayerController>(),
        // The device's own name, so a member list says who is who rather than
        // showing five identical rows.
        displayName: defaultRoomDisplayName(),
        transportFactory: roomTransportFactory,
        audioCache: roomAudioCache,
        // The same seam the launch-time prompt asked through, so a grant there
        // is felt here.
        localNetwork: context.read<LocalNetworkPermission>(),
      ),
      update: (_, library, player, room) {
        room!.librarySource = () => library.songs;
        return room;
      },
    ),
  ];
}
