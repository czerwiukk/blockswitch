import 'package:blockswitch/resistance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resistanceGain', () {
    test('resistance 0.0 tracks the finger exactly everywhere', () {
      for (final u in <double>[0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(resistanceGain(u, 0.0), 1.0);
      }
    });

    test('gain falls as the pull progresses, so the end is the hardest', () {
      double previous = double.infinity;
      for (final u in <double>[0.0, 0.2, 0.4, 0.6, 0.8, 1.0]) {
        final gain = resistanceGain(u, 1.0);
        expect(gain, lessThan(previous));
        previous = gain;
      }
    });

    test('higher resistance is never easier at the same position', () {
      expect(resistanceGain(0.9, 1.0), lessThan(resistanceGain(0.9, 0.3)));
    });

    test('never stops responding, even at the hardest point', () {
      expect(resistanceGain(1.0, 1.0), greaterThanOrEqualTo(kMinGain));
    });

    test('resistance 1.0 stays completable within one determined swipe', () {
      // Integrate 1/gain across the track to get the finger distance needed,
      // expressed in track widths. Must stay small enough to fit one swipe.
      const steps = 2000;
      var trackWidths = 0.0;
      for (var i = 0; i < steps; i++) {
        final u = (i + 0.5) / steps;
        trackWidths += (1.0 / resistanceGain(u, 1.0)) / steps;
      }
      expect(trackWidths, greaterThan(1.0));
      expect(trackWidths, lessThan(1.6));
    });

    test('inputs outside 0..1 are clamped rather than extrapolated', () {
      expect(resistanceGain(-1.0, 1.0), resistanceGain(0.0, 1.0));
      expect(resistanceGain(2.0, 1.0), resistanceGain(1.0, 1.0));
      expect(resistanceGain(0.5, 5.0), resistanceGain(0.5, 1.0));
    });
  });

  group('snapBackSpring', () {
    test('stiffens as resistance rises', () {
      expect(
        snapBackSpring(1.0).stiffness,
        greaterThan(snapBackSpring(0.0).stiffness),
      );
    });
  });
}
