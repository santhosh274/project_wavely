import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/core/models/song_model.dart';
import 'package:wavely/core/services/lyrics_service.dart';

void main() {
  group('LRC parsing', () {
    test('reads timestamped lines into playback order', () {
      final lines = LyricsService.parseLrc(
        '[00:12.50]first line\n[00:04.00]an earlier line\n',
      );

      expect(lines.map((l) => l.text), ['an earlier line', 'first line']);
      expect(lines.first.time, const Duration(seconds: 4));
    });

    test('scales fractional seconds by their digit count', () {
      // `.5`, `.50` and `.500` are all half a second; `.05` is a twentieth.
      expect(
        LyricsService.parseLrc('[00:01.5]a\n').single.time,
        const Duration(milliseconds: 1500),
      );
      expect(
        LyricsService.parseLrc('[00:01.50]a\n').single.time,
        const Duration(milliseconds: 1500),
      );
      expect(
        LyricsService.parseLrc('[00:01.500]a\n').single.time,
        const Duration(milliseconds: 1500),
      );
      expect(
        LyricsService.parseLrc('[00:01.05]a\n').single.time,
        const Duration(milliseconds: 1050),
      );
    });

    test('accepts the colon-separated fraction some writers use', () {
      expect(
        LyricsService.parseLrc('[01:02:30]a\n').single.time,
        const Duration(minutes: 1, seconds: 2, milliseconds: 300),
      );
    });

    test('handles minutes past an hour', () {
      expect(
        LyricsService.parseLrc('[61:00.00]a\n').single.time,
        const Duration(minutes: 61),
      );
    });

    test('a repeated chorus keeps both timestamps', () {
      final lines = LyricsService.parseLrc('[00:10.00]chorus\n[00:40.00]chorus\n');

      expect(lines.map((l) => l.time), [
        const Duration(seconds: 10),
        const Duration(seconds: 40),
      ]);
      expect(lines.every((l) => l.text == 'chorus'), isTrue);
    });

    test('one line carrying several timestamps becomes several entries', () {
      final lines = LyricsService.parseLrc('[00:10.00][01:10.00]chorus\n');

      expect(lines.map((l) => l.time), [
        const Duration(seconds: 10),
        const Duration(minutes: 1, seconds: 10),
      ]);
    });

    test('metadata tags and untimed lines are dropped, not invented', () {
      // Guessing a time of zero would put every untimed line at the start.
      final lines = LyricsService.parseLrc(
        '[ar:Some Artist]\n[ti:Some Title]\nsome stray note\n'
        '[00:03.00]real line\n',
      );

      expect(lines.map((l) => l.text), ['real line']);
    });

    test('tolerates leading whitespace and blank lines', () {
      final lines = LyricsService.parseLrc('\n  [00:05.00]a\n\n[00:06.00]b\n');

      expect(lines.map((l) => l.text), ['a', 'b']);
    });

    test('content with no timestamps at all parses to nothing', () {
      expect(LyricsService.parseLrc('just some words\n'), isEmpty);
      expect(LyricsService.parseLrc(''), isEmpty);
    });
  });

  group('looking up the sidecar file', () {
    const service = LyricsService();

    test('tries the full file name before the bare name', () {
      final candidates = service.candidatePathsFor(
        _songAt('/sdcard/Music/Track.mp3'),
      );

      // Tagging tools write `Track.mp3.lrc` by default, so that is the first
      // place worth looking.
      expect(candidates, [
        '/sdcard/Music/Track.mp3.lrc',
        '/sdcard/Music/Track.lrc',
      ]);
    });

    test('reports not found when there is no sidecar next to the track',
        () async {
      // The path does not exist, so this exercises the real file probe rather
      // than a stubbed one.
      final result = await service.load(_songAt('/no/such/place/Track.mp3'));

      expect(result.status, LyricsStatus.notFound);
      expect(result.lines, isEmpty);
    });

    test('reads the lyrics when a sidecar really is there', () async {
      final dir = await Directory.systemTemp.createTemp('wavely_lyrics');
      addTearDown(() => dir.delete(recursive: true));

      final audio = File('${dir.path}/Track.mp3');
      await audio.writeAsString('not really audio');

      final sidecar = File('${dir.path}/Track.mp3.lrc');
      await sidecar.writeAsString('[00:01.00]a real line\n[00:02.00]another\n');

      final result = await service.load(
        _songAt(audio.path),
      );

      expect(result.status, LyricsStatus.found);
      expect(result.lines.map((l) => l.text), ['a real line', 'another']);
      expect(result.sourcePath, sidecar.path);
    });

    test('reports unreadable rather than found for an empty sidecar', () async {
      final dir = await Directory.systemTemp.createTemp('wavely_lyrics');
      addTearDown(() => dir.delete(recursive: true));

      final audio = File('${dir.path}/Track.mp3');
      await audio.writeAsString('not really audio');
      await File('${dir.path}/Track.mp3.lrc').writeAsString('no timestamps');

      final result = await service.load(_songAt(audio.path));

      // Pretending an empty file is a lyric sheet would be worse than saying so.
      expect(result.status, LyricsStatus.unreadable);
      expect(result.lines, isEmpty);
    });

    test('a track with no path has nothing to look beside', () {
      // Content-only tracks under scoped storage have no readable directory, so
      // inventing a candidate path would only fail at open time.
      expect(service.candidatePathsFor(_songAt('')), isEmpty);
    });
  });

  group('finding the line for a position', () {
    final result = LyricsResult.found(
      LyricsService.parseLrc('[00:10.00]ten\n[00:20.00]twenty\n[00:30.00]thirty\n'),
      '/tmp/track.lrc',
    );

    test('is empty before the first timestamp', () {
      expect(result.lineAt(const Duration(seconds: 5)), isNull);
    });

    test('holds a line until the next one starts', () {
      expect(result.lineAt(const Duration(seconds: 10))!.text, 'ten');
      expect(result.lineAt(const Duration(seconds: 19))!.text, 'ten');
      expect(result.lineAt(const Duration(seconds: 20))!.text, 'twenty');
      expect(result.lineAt(const Duration(seconds: 99))!.text, 'thirty');
    });

    test('starts the line exactly at its timestamp, not after it', () {
      expect(result.lineAt(const Duration(milliseconds: 9999)), isNull);
      expect(result.lineAt(const Duration(milliseconds: 10000))!.text, 'ten');
    });
  });
}

/// A track whose only identity for lyrics purposes is [uri].
WavelySong _songAt(String uri) => WavelySong(
      id: uri,
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(minutes: 3),
      uri: uri,
    );