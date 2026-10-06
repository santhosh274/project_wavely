/// `m:ss`, or `h:mm:ss` once the duration passes an hour.
///
/// Negative durations come out of just_audio while a source is still being
/// opened, and showing `-1:-3` in the transport bar looks like a bug rather than
/// a track that has not started, so they are floored at zero.
String formatDuration(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
}

/// A runtime long enough to read at a glance, e.g. `1 hr 12 min`.
String formatRuntime(Duration duration) {
  if (duration.inMinutes < 1) return 'under a minute';

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours hr';
  return '$hours hr $minutes min';
}