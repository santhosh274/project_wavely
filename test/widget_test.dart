import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wavely/main.dart';
import 'package:wavely/core/theme/theme_controller.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/library/controllers/library_controller.dart';
import 'package:wavely/core/services/local_media_service.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/navigation/controllers/shell_controller.dart';

/// Stands in for a user who declined the media permission.
class _DeniedMediaService extends LocalMediaService {
  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<LibraryLoadResult> fetchLocalSongs() async =>
      const LibraryLoadResult(
        status: LibraryLoadStatus.permissionDenied,
        message: 'Storage access is needed to read songs stored on this device.',
      );
}

/// Stands in for a device holding real, readable music.
class _GrantedMediaService extends LocalMediaService {
  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<LibraryLoadResult> fetchLocalSongs() async => LibraryLoadResult(
        status: LibraryLoadStatus.success,
        songs: const [
          WavelySong(
            id: '10',
            title: 'Aurora Fields',
            artist: 'Real Artist',
            album: 'Real Album',
            duration: Duration(minutes: 3, seconds: 20),
            uri: 'content://media/external/audio/media/10',
            genre: 'Ambient',
          ),
          WavelySong(
            id: '11',
            title: 'Neon Tide',
            artist: 'Another Artist',
            album: 'Real Album',
            duration: Duration(minutes: 4, seconds: 5),
            uri: 'content://media/external/audio/media/11',
            genre: 'Ambient',
          ),
        ],
      );
}

Widget _wrap(LibraryController library, {ShellController? shell}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeController()),
      ChangeNotifierProvider<ShellController>.value(
        value: shell ?? ShellController(),
      ),
      ChangeNotifierProvider(create: (_) => PlayerController()),
      ChangeNotifierProvider.value(value: library),
    ],
    child: const WavelyApp(),
  );
}

void main() {
  testWidgets('Wavely App renders without crashing', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => ShellController()),
          ChangeNotifierProvider(create: (_) => PlayerController()),
          ChangeNotifierProvider(create: (_) => LibraryController()),
        ],
        child: const WavelyApp(),
      ),
    );

    expect(find.byType(WavelyApp), findsOneWidget);
  });

  testWidgets('declined permission shows a prompt, not placeholder tracks',
      (tester) async {
    final controller =
        LibraryController(mediaService: _DeniedMediaService());
    addTearDown(controller.dispose);

    final shell = ShellController();
    await tester.pumpWidget(_wrap(controller, shell: shell));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The library tab is where the permission gate is surfaced.
    shell.selectTab(3);
    await tester.pumpAndSettle();

    expect(find.text('Permission needed'), findsOneWidget);

    // The demo tracks that used to stand in for a real library must be gone.
    expect(find.text('Midnight Glass Echoes'), findsNothing);
    expect(find.text('Frosted Prism'), findsNothing);
    expect(find.text('Chill Glass Synth'), findsNothing);
    expect(controller.songs, isEmpty);
  });

  testWidgets('granted permission lists the real tracks from the device',
      (tester) async {
    final controller =
        LibraryController(mediaService: _GrantedMediaService());
    addTearDown(controller.dispose);

    final shell = ShellController();
    await tester.pumpWidget(_wrap(controller, shell: shell));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Songs are listed in the library tab's first section.
    shell.selectTab(3);
    await tester.pumpAndSettle();

    expect(find.text('Aurora Fields'), findsOneWidget);
    expect(find.text('Neon Tide'), findsOneWidget);
    expect(find.text('Permission needed'), findsNothing);

    // Playlists are derived from the genres actually present.
    expect(controller.playlists.map((p) => p.name), contains('Ambient'));
    expect(controller.genres, contains('Ambient'));
  });
}
