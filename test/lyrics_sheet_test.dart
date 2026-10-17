import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/features/player/controllers/player_controller.dart';
import 'package:wavely/features/player/presentation/widgets/lyrics_sheet.dart';

import 'support/fake_artwork_service.dart';
import 'support/fake_audio_engine.dart';
import 'support/memory_playback_store.dart';

void main() {
  late Directory directory;
  late WavelySong song;
  late FakeAudioEngine engine;
  late PlayerController player;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wavely_lyrics');
    final audio = File('${directory.path}/song.mp3');
    await audio.writeAsBytes(const []);

    // A sidecar beside the track, named the way tagging tools name them.
    await File('${audio.path}.lrc').writeAsString(
      '[ar:Vela]\n'
      '[00:00.00] First light\n'
      '[00:10.00] Second line\n'
      '[00:20.00] Third line\n',
    );

    song = WavelySong(
      id: '1',
      title: 'Neon Tide',
      artist: 'Vela',
      album: 'Harbour Lights',
      duration: const Duration(minutes: 3),
      uri: audio.path,
    );

    engine = FakeAudioEngine();
    player = PlayerController(
      audioService: engine,
      artworkService: FakeArtworkService(),
      stateStore: MemoryPlaybackStateStore(),
    );
  });

  tearDown(() async {
    player.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  /// The size the sheet draws a lyric line at: larger means it is the line under
  /// the playhead.
  double fontSizeOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.fontSize!;

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          home: Scaffold(body: LyricsSheet(song: song)),
        ),
      ),
    );

    // The sidecar is read from the real filesystem, and each `await` in the
    // lookup is a real I/O step, so the test has to hand the event loop back and
    // forth: a real-zone turn for the read to finish, then a frame for the
    // sheet to show the answer. `pumpAndSettle` cannot be used to wait for it at
    // all -- the sheet shows a spinner while the lookup is pending, and a
    // spinner never settles.
    for (var round = 0; round < 5; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('the sidecar is found and its first line is highlighted', (
    tester,
  ) async {
    await pumpSheet(tester);

    // Metadata tags are not lyrics, and the untimed header is dropped.
    expect(find.text('First light'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);
    expect(find.textContaining('[ar:'), findsNothing);

    expect(fontSizeOf(tester, 'First light'), 18.0);
    expect(fontSizeOf(tester, 'Second line'), 16.0);
  });

  testWidgets('the highlight follows the playhead as the track plays', (
    tester,
  ) async {
    await pumpSheet(tester);

    // Past the second timestamp: the line under the playhead moves, and with it
    // the emphasis. The sheet listens to the position stream directly, so this is
    // the one thing that has to keep working as the playhead ticks.
    engine.reportTimeline(
      position: const Duration(seconds: 12),
      duration: song.duration,
    );
    await tester.pump();
    await tester.pump();

    expect(fontSizeOf(tester, 'First light'), 16.0);
    expect(fontSizeOf(tester, 'Second line'), 18.0);
    expect(fontSizeOf(tester, 'Third line'), 16.0);

    // And on again, so the highlight is not stuck where it first landed.
    engine.reportTimeline(
      position: const Duration(seconds: 25),
      duration: song.duration,
    );
    await tester.pump();
    await tester.pump();

    expect(fontSizeOf(tester, 'Second line'), 16.0);
    expect(fontSizeOf(tester, 'Third line'), 18.0);
  });

  testWidgets('a track with no sidecar says so instead of inventing lyrics', (
    tester,
  ) async {
    song = WavelySong(
      id: '2',
      title: 'No Lyrics Here',
      artist: 'Vela',
      album: 'Harbour Lights',
      duration: const Duration(minutes: 3),
      uri: '${directory.path}/absent.mp3',
    );

    await pumpSheet(tester);

    expect(find.textContaining('No lyrics on this device'), findsOneWidget);
  });
}
