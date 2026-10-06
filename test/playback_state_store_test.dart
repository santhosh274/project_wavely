import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/services/audio_player_service.dart'
    show RepeatBehaviour;
import 'package:wavely/core/services/playback_state_store.dart';

PlaybackSnapshot _snapshot({
  List<String> songIds = const ['10', '11', '12'],
  int index = 1,
  Duration position = const Duration(seconds: 42),
  bool wasPlaying = true,
  bool shuffle = false,
  RepeatBehaviour repeatMode = RepeatBehaviour.off,
  double volume = 0.8,
  String? queueTitle = 'Evening',
}) {
  return PlaybackSnapshot(
    songIds: songIds,
    index: index,
    position: position,
    wasPlaying: wasPlaying,
    shuffle: shuffle,
    repeatMode: repeatMode,
    volume: volume,
    queueTitle: queueTitle,
    savedAt: DateTime.fromMillisecondsSinceEpoch(1767225600000),
  );
}

void main() {
  group('PlaybackSnapshot', () {
    test('survives a round trip through JSON', () {
      final snapshot = _snapshot(
        index: 2,
        position: const Duration(minutes: 3, seconds: 7),
        shuffle: true,
        repeatMode: RepeatBehaviour.one,
        volume: 0.42,
      );

      final parsed = PlaybackSnapshot.tryParse(jsonEncode(snapshot.toJson()));

      expect(parsed, isNotNull);
      expect(parsed!.songIds, snapshot.songIds);
      expect(parsed.index, 2);
      expect(parsed.position, const Duration(minutes: 3, seconds: 7));
      expect(parsed.wasPlaying, isTrue);
      expect(parsed.shuffle, isTrue);
      expect(parsed.repeatMode, RepeatBehaviour.one);
      expect(parsed.volume, 0.42);
      expect(parsed.queueTitle, 'Evening');
      expect(parsed.savedAt, snapshot.savedAt);
    });

    test('a corrupt or foreign file reads as "nothing to restore"', () {
      // Restoring has to be best effort: a file mangled by a partial write or a
      // downgraded build must not be able to stop the app from opening.
      expect(PlaybackSnapshot.tryParse('not json at all'), isNull);
      expect(PlaybackSnapshot.tryParse('[]'), isNull);
      expect(PlaybackSnapshot.tryParse('{}'), isNull);
      expect(PlaybackSnapshot.tryParse('{"songIds": [], "index": 0}'), isNull);
      expect(
        PlaybackSnapshot.tryParse(
          '{"songIds": [1, 2], "index": 0, "positionMs": 0, "savedAtMs": 0}',
        ),
        isNull,
      );
    });

    test('unusable fields fall back instead of throwing', () {
      final parsed = PlaybackSnapshot.tryParse(
        jsonEncode({
          'songIds': ['10'],
          'index': 0,
          'positionMs': 5000,
          'wasPlaying': 'yes please',
          'shuffle': 1,
          'repeat': 'sideways',
          'volume': 7.5,
          'queueTitle': '',
          'savedAtMs': 1767225600000,
        }),
      );

      expect(parsed, isNotNull);
      // Strictly typed so the switch and the shuffle flag mean what they say.
      expect(parsed!.wasPlaying, isFalse);
      expect(parsed.shuffle, isFalse);
      expect(parsed.repeatMode, RepeatBehaviour.off);
      expect(parsed.queueTitle, isNull);
      // A volume outside the range would otherwise come back as a slider pinned
      // to an unusable level.
      expect(parsed.volume, 1.0);
    });
  });

  group('FilePlaybackStateStore', () {
    late Directory directory;
    late FilePlaybackStateStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('wavely_playback');
      store = FilePlaybackStateStore(directory: () async => directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('a session written is a session read back', () async {
      expect(await store.read(), isNull);

      await store.write(_snapshot());

      final restored = await store.read();
      expect(restored, isNotNull);
      expect(restored!.songIds, ['10', '11', '12']);
      expect(restored.index, 1);
      expect(restored.queueTitle, 'Evening');
    });

    test('a later write replaces the earlier one', () async {
      await store.write(_snapshot(songIds: const ['1'], index: 0));
      await store.write(_snapshot(songIds: const ['2', '3'], index: 1));

      expect((await store.read())!.songIds, ['2', '3']);
    });

    test('nothing is left over from the temporary file', () async {
      await store.write(_snapshot());

      // The write goes to a temp file that is renamed into place, so a partial
      // write cannot leave debris next to the real one.
      final leftovers = directory
          .listSync()
          .where((entry) => entry.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('clearing removes the stored session', () async {
      await store.write(_snapshot());
      await store.clear();

      expect(await store.read(), isNull);
      // Clearing something that was never written is not an error.
      await store.clear();
    });

    test('a mangled file is treated as no stored session', () async {
      await File('${directory.path}/${FilePlaybackStateStore.fileName}')
          .writeAsString('{ half written');

      expect(await store.read(), isNull);
    });

    test('an unwritable location never throws at the player', () async {
      final broken = FilePlaybackStateStore(
        // A directory that does not exist: writing into it fails exactly as a
        // full or unavailable volume would.
        directory: () async => Directory('${directory.path}/missing'),
      );

      await expectLater(broken.write(_snapshot()), completes);
      expect(await broken.read(), isNull);
      await expectLater(broken.clear(), completes);
    });
  });
}
