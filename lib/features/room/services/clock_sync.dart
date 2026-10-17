/// How far this device's clock is from the host's, estimated the way NTP does it.
///
/// Two phones never agree on the time -- they can be seconds apart, because the
/// clock is only as good as the last time the device synced -- so every timestamp
/// on the wire is meaningless until it is converted. A four-stamp exchange gives
/// both numbers needed:
///
/// ```
///   client                                  host
///     | ---- request  (t0) -----------------> |
///     |                        (t1) receive    |
///     |                        (t2) reply      |
///     | <--- reply    (t3) ------------------ |
/// ```
///
/// `offset = ((t1 - t0) + (t2 - t3)) / 2` is the host's clock minus ours, with the
/// network's one-way delay cancelled out; `rtt = (t3 - t0) - (t2 - t1)` is the
/// round trip with the host's own processing time removed.
///
/// The samples are not averaged blindly. A frame that sat in a queue behind other
/// traffic has a large round trip *and* a skewed offset, so only the samples with
/// the shortest round trips are trusted, and their offsets are reduced with a
/// median rather than a mean so one outlier cannot drag the clock.
class ClockSync {
  /// Samples kept. More than a handful adds nothing: the estimate only improves
  /// with samples that were genuinely faster, not simply later.
  static const int maxSamples = 12;

  /// How many of the fastest samples the estimate is taken from.
  static const int _trustedSamples = 3;

  final List<_Sample> _samples = <_Sample>[];

  /// The current host-minus-local offset, once at least one round trip landed.
  int? _offsetMs;

  bool get isReady => _offsetMs != null;

  /// Host clock minus this device's clock, in milliseconds.
  ///
  /// Zero until the first exchange completes, which is the safe default: an
  /// unsynchronised room plays "now", which is no worse than not being in one.
  int get offsetMs => _offsetMs ?? 0;

  /// The round trip of the fastest trusted sample, or null before any.
  int? get roundTripMs {
    final trusted = _trusted;
    if (trusted.isEmpty) return null;
    return trusted.first.rttMs;
  }

  /// Translate a host timestamp into this device's clock.
  int toLocal(int hostEpochMs) => hostEpochMs - offsetMs;

  /// Translate this device's clock into the host's.
  int toHost(int localEpochMs) => localEpochMs + offsetMs;

  /// Record one completed exchange.
  ///
  /// [clientSentMs] and [clientReceivedMs] are from this device's clock,
  /// [hostReceivedMs] and [hostSentMs] from the host's. A negative round trip
  /// means the two stamps contradict each other, which happens when a clock is
  /// adjusted mid-exchange; the sample is dropped rather than allowed to poison
  /// the offset.
  void addRoundTrip({
    required int clientSentMs,
    required int hostReceivedMs,
    required int hostSentMs,
    required int clientReceivedMs,
  }) {
    final rtt = (clientReceivedMs - clientSentMs) -
        (hostSentMs - hostReceivedMs);
    if (rtt < 0) return;

    final offset = ((hostReceivedMs - clientSentMs) +
            (hostSentMs - clientReceivedMs)) /
        2;

    _samples.add(_Sample(rttMs: rtt, offsetMs: offset.round()));
    if (_samples.length > maxSamples) _samples.removeAt(0);

    _offsetMs = _median(_trusted.map((s) => s.offsetMs).toList());
  }

  /// Forget everything, for when the link is re-established and the old delay
  /// profile no longer describes it.
  void reset() {
    _samples.clear();
    _offsetMs = null;
  }

  /// The fastest [_trustedSamples] samples, best first.
  List<_Sample> get _trusted {
    if (_samples.isEmpty) return const [];
    final sorted = List<_Sample>.of(_samples)
      ..sort((a, b) => a.rttMs.compareTo(b.rttMs));
    return sorted.take(_trustedSamples).toList();
  }

  static int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return ((sorted[middle - 1] + sorted[middle]) / 2).round();
  }
}

class _Sample {
  final int rttMs;
  final int offsetMs;

  const _Sample({required this.rttMs, required this.offsetMs});
}
