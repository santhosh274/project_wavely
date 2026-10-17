import 'package:flutter_test/flutter_test.dart';
import 'package:wavely/features/room/services/clock_sync.dart';

/// One completed exchange, with the host's clock [offsetMs] ahead of ours.
///
/// [rttMs] is the round trip the client sees *including* the host's own
/// processing, which is what makes these numbers useful for checking that the
/// processing time is taken back out again.
void sample(
  ClockSync clock, {
  required int offsetMs,
  int rttMs = 10,
  int hostProcessingMs = 0,
  int sentAtMs = 100000,
}) {
  final hostArrived = sentAtMs + rttMs ~/ 2 + offsetMs;
  clock.addRoundTrip(
    clientSentMs: sentAtMs,
    hostReceivedMs: hostArrived,
    hostSentMs: hostArrived + hostProcessingMs,
    clientReceivedMs: sentAtMs + rttMs + hostProcessingMs,
  );
}

void main() {
  group('clock sync', () {
    test('starts unmeasured, so a room that has not synced plays "now"', () {
      final clock = ClockSync();
      expect(clock.isReady, isFalse);
      expect(clock.offsetMs, 0);
      expect(clock.roundTripMs, isNull);
      expect(clock.toLocal(5000), 5000);
    });

    test('solves the offset from a symmetric exchange', () {
      final clock = ClockSync();
      sample(clock, offsetMs: 400);

      expect(clock.isReady, isTrue);
      // The host is 400ms ahead, so a host stamp becomes ours minus 400.
      expect(clock.offsetMs, 400);
      expect(clock.toLocal(10000), 9600);
      expect(clock.toHost(9600), 10000);
    });

    test('a device whose clock is ahead reads the offset as negative', () {
      final clock = ClockSync();
      sample(clock, offsetMs: -250);

      expect(clock.offsetMs, -250);
      expect(clock.toLocal(1000), 1250);
    });

    test('the round trip excludes the host\'s own processing time', () {
      final clock = ClockSync();
      sample(clock, offsetMs: 0, rttMs: 8, hostProcessingMs: 30);

      // 38ms end to end, but 30 of it was the host thinking, which is not the
      // network's fault and must not inflate the estimate's uncertainty.
      expect(clock.roundTripMs, 8);
    });

    test('an offset is right regardless of how slow the link was', () {
      final clock = ClockSync();
      sample(clock, offsetMs: 120, rttMs: 300);
      expect(clock.offsetMs, 120);
    });

    test('a sample whose stamps contradict each other is dropped', () {
      final clock = ClockSync();
      clock.addRoundTrip(
        clientSentMs: 1000,
        hostReceivedMs: 1000,
        // The host claims to have spent 100ms on a frame that was back with us
        // after 50ms. A clock was adjusted mid-exchange, and an offset derived
        // from these stamps would be wrong in a way nothing later could correct.
        hostSentMs: 1100,
        clientReceivedMs: 1050,
      );

      expect(clock.isReady, isFalse);
    });

    test('a slow sample does not drag the estimate', () {
      final clock = ClockSync();
      // Three fast samples agree on +100.
      sample(clock, offsetMs: 100, rttMs: 4, sentAtMs: 1000);
      sample(clock, offsetMs: 100, rttMs: 5, sentAtMs: 2000);
      sample(clock, offsetMs: 100, rttMs: 6, sentAtMs: 3000);

      // Then one frame that sat in a queue for half a second, whose offset is
      // correspondingly wrong.
      sample(clock, offsetMs: 600, rttMs: 900, sentAtMs: 4000);

      expect(clock.offsetMs, 100);
      expect(clock.roundTripMs, 4);
    });

    test('a better sample later still updates the estimate', () {
      final clock = ClockSync();
      sample(clock, offsetMs: 100, rttMs: 200);
      expect(clock.offsetMs, 100);

      // The fast samples now outvote the slow first one.
      sample(clock, offsetMs: 40, rttMs: 3, sentAtMs: 5000);
      sample(clock, offsetMs: 40, rttMs: 4, sentAtMs: 6000);
      sample(clock, offsetMs: 40, rttMs: 5, sentAtMs: 7000);
      expect(clock.offsetMs, 40);
    });

    test('only a bounded number of samples is kept', () {
      final clock = ClockSync();
      for (var i = 0; i < ClockSync.maxSamples * 3; i++) {
        sample(clock, offsetMs: i, rttMs: 10, sentAtMs: 1000 + i * 10000);
      }

      // The oldest samples are gone, so the estimate follows the recent ones
      // rather than the history.
      expect(clock.offsetMs, greaterThan(ClockSync.maxSamples));
    });

    test('reset forgets the offset for a new link', () {
      final clock = ClockSync();
      sample(clock, offsetMs: 400);
      clock.reset();

      expect(clock.isReady, isFalse);
      expect(clock.offsetMs, 0);
      expect(clock.roundTripMs, isNull);
    });
  });
}
