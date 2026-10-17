import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/room/controllers/room_controller.dart';
import 'package:wavely/features/room/services/local_network_permission.dart';
import 'package:wavely/features/room/services/room_audio_cache.dart';

import 'fake_artwork_service.dart';
import 'fake_audio_engine.dart';
import 'fake_local_network_permission.dart';
import 'fake_room_transport.dart';
import 'memory_playback_store.dart';

/// The songs a room test runs on.
const roomTestAurora = WavelySong(
  id: '10',
  title: 'Aurora Fields',
  artist: 'Real Artist',
  album: 'Real Album',
  duration: Duration(minutes: 3, seconds: 20),
  uri: '/audio/aurora.mp3',
  fileSize: 4200,
);

const roomTestNeon = WavelySong(
  id: '11',
  title: 'Neon Tide',
  artist: 'Another Artist',
  album: 'Real Album',
  duration: Duration(minutes: 4, seconds: 5),
  uri: '/audio/neon.mp3',
  fileSize: 5100,
);

/// One device in a room: the *real* player over a fake audio engine, and the
/// real room controller driving it.
///
/// The real controller is the point. What is under test is the behaviour -- who
/// broadcasts, what a guest applies, when it corrects itself -- and a fake room
/// would only be testing the fake.
class RoomTestDevice {
  RoomTestDevice({
    required FakeRoomTransportFactory factory,
    List<WavelySong>? library,
    RoomAudioCache? cache,
    LocalNetworkPermission? localNetwork,
    String displayName = 'Tester',
    Duration beatInterval = const Duration(milliseconds: 50),
    Duration driftInterval = const Duration(milliseconds: 10),
  }) : songs = library ?? const [roomTestAurora, roomTestNeon],
       engine = FakeAudioEngine(),
       localNetwork = localNetwork ?? FakeLocalNetworkPermission() {
    player = PlayerController(
      audioService: engine,
      artworkService: FakeArtworkService(),
      stateStore: MemoryPlaybackStateStore(),
    );
    room = RoomController(
      player: player,
      library: () => songs,
      transportFactory: factory,
      audioCache: cache,
      localNetwork: this.localNetwork,
      displayName: displayName,
      clockInterval: const Duration(milliseconds: 20),
      beatInterval: beatInterval,
      driftInterval: driftInterval,
    );
  }

  final List<WavelySong> songs;
  final FakeAudioEngine engine;

  /// The local-network permission the room asks before it opens. A fake by
  /// default, so the room never reaches for a platform channel in a test.
  final LocalNetworkPermission localNetwork;

  late final PlayerController player;
  late final RoomController room;

  Future<void> dispose() async {
    await room.leave();
    player.dispose();
    await engine.dispose();
  }
}
