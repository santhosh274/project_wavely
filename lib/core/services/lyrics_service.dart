import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/song_model.dart';

/// One timestamped line of an LRC lyric file.
@immutable
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});

  @override
  bool operator ==(Object other) =>
      other is LyricLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);
}

/// Why a lyrics lookup ended the way it did.
enum LyricsStatus {
  /// Lines were found and parsed.
  found,

  /// No `.lrc` file sits next to the audio file.
  notFound,

  /// The file is there but unreadable, or is not a lyric file.
  unreadable,
}

/// Outcome of one lyrics lookup.
@immutable
class LyricsResult {
  final LyricsStatus status;

  /// Lines in playback order. Empty unless [status] is [LyricsStatus.found].
  final List<LyricLine> lines;

  /// Where the lyrics were read from, for display.
  final String? sourcePath;

  const LyricsResult._(this.status, this.lines, {this.sourcePath});

  const LyricsResult.found(List<LyricLine> lines, String sourcePath)
      : this._(LyricsStatus.found, lines, sourcePath: sourcePath);

  const LyricsResult.notFound() : this._(LyricsStatus.notFound, const []);

  const LyricsResult.unreadable() : this._(LyricsStatus.unreadable, const []);

  /// The line playing at [position], or null before the first timestamp.
  LyricLine? lineAt(Duration position) {
    LyricLine? active;
    for (final line in lines) {
      if (line.time <= position) {
        active = line;
      } else {
        break;
      }
    }
    return active;
  }
}

/// Reads lyrics from a `.lrc` file sitting next to the track.
///
/// Local music players conventionally keep a sidecar `<track name>.lrc` beside
/// the audio file, and that is the only source available for files already on a
/// device. Nothing is fetched from the network and nothing is invented: a track
/// with no sidecar reports [LyricsStatus.notFound] so the UI can say so.
class LyricsService {
  const LyricsService();

  /// Candidate sidecar paths for [song], most likely first.
  ///
  /// Tries the full file name (`Song.mp3.lrc`) before the bare name
  /// (`Song.lrc`), because that is what tagging tools write by default.
  List<String> candidatePathsFor(WavelySong song) {
    final source = song.uri;
    if (source.isEmpty) return const [];

    // A content:// track has no filesystem path, so there is no sidecar to find.
    final separator = source.lastIndexOf(RegExp(r'[/\\]'));
    final directory = separator < 0 ? '' : source.substring(0, separator + 1);
    final fileName = separator < 0 ? source : source.substring(separator + 1);

    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);

    return [
      '$directory$fileName.lrc',
      '$directory$stem.lrc',
    ];
  }

  /// Look up lyrics for [song].
  Future<LyricsResult> load(WavelySong song) async {
    for (final path in candidatePathsFor(song)) {
      final file = File(path);
      if (!await file.exists()) continue;

      try {
        final content = await file.readAsString();
        final lines = parseLrc(content);
        if (lines.isEmpty) return const LyricsResult.unreadable();
        return LyricsResult.found(lines, path);
      } on FileSystemException {
        // Permission denied or the file vanished mid-read: try the next
        // candidate rather than failing the whole lookup.
        continue;
      }
    }

    return const LyricsResult.notFound();
  }

  /// Parse LRC content into timestamped lines.
  ///
  /// Lines without a timestamp are skipped rather than guessed at: showing them
  /// with a fabricated time of zero would put every untimed line at the start of
  /// the song. Metadata tags (`[ar:]`, `[ti:]`, ...) are dropped for the same
  /// reason -- they are not lyrics.
  static List<LyricLine> parseLrc(String content) {
    final lines = <LyricLine>[];

    for (final raw in content.split(RegExp(r'\r\n|\r|\n'))) {
      // One LRC line can carry several timestamps for a repeated chorus, so
      // every one of them gets its own entry with the same text.
      final stamps = _timestampsIn(raw);
      if (stamps.isEmpty) continue;

      final text = raw.replaceFirst(_timestampPattern, '').trim();
      for (final time in stamps) {
        lines.add(LyricLine(time: time, text: text));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Matches one or more `[mm:ss.xx]` groups at the start of a line.
  static final RegExp _timestampPattern = RegExp(r'^\s*((?:\[\d+:\d{1,2}(?:[.:]\d{1,3})?\])+)');

  static List<Duration> _timestampsIn(String line) {
    final match = _timestampPattern.firstMatch(line);
    if (match == null) return const [];

    // Each captured group is the text between the brackets, so the closing
    // bracket has to go back on for the parser.
    final tags = match.group(1)!.split(']').where((t) => t.isNotEmpty);
    return [
      for (final tag in tags) ?_parseTimestamp('$tag]'),
    ];
  }

  /// Parse `[mm:ss]`, `[mm:ss.xx]` or `[mm:ss:xx]`.
  ///
  /// Fractional parts are scaled by their digit count, so `.5` is half a second
  /// and `.50` is too, while `.05` is a twentieth -- which a fixed two-digit
  /// reading would get wrong.
  static Duration? _parseTimestamp(String tag) {
    final body = tag.replaceAll(RegExp(r'[\[\]]'), '');
    final parts = body.split(RegExp(r'[:.]'));
    if (parts.length < 2) return null;

    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (minutes == null || seconds == null) return null;

    var millis = 0;
    if (parts.length >= 3 && parts[2].isNotEmpty) {
      final fraction = parts[2];
      final value = int.tryParse(fraction) ?? 0;
      // The fraction is a decimal with as many places as it has digits, so the
      // divisor is a power of ten: `.5` and `.50` are both 500ms, while `.05` is
      // 50ms and `.500` is 500ms again. Reading it as a fixed two-digit value
      // would put a whole chorus two seconds late.
      var divisor = 1;
      for (var place = 0; place < fraction.length; place++) {
        divisor *= 10;
      }
      millis = (value * 1000) ~/ divisor;
    }

    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }
}