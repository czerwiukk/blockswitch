import 'dart:math' as math;

import 'package:flutter/physics.dart';

/// Tuning constants for the un-blocking drag. All of the "feel" lives here.
///
/// [kResistanceStrength] sets how much harder the very end of the pull is than
/// the very start. [kResistanceCurve] sets how back-loaded that is: a high
/// exponent means the first half of the track is essentially free and the
/// difficulty piles up at the end.
const double kResistanceStrength = 2.2;
const double kResistanceCurve = 4.0;

/// Hard floor on the gain, so that no combination of inputs can ever make the
/// knob stop responding entirely. Resistance 1.0 must still be completable.
const double kMinGain = 0.22;

/// How much of the finger's movement the knob actually follows while the user
/// is dragging *toward OFF* (un-blocking).
///
/// This is the rubber-banding. The knob is not glued to the finger: each pixel
/// of finger travel is multiplied by the gain returned here before it moves the
/// knob. A gain of 1.0 is 1:1 tracking, a gain of 0.3 means the finger has to
/// travel three pixels to drag the knob one.
///
/// [offProgress] is how far the knob has already come toward OFF, 0.0 at the
/// blocked (right) end and 1.0 at the unblocked (left) end. [resistance] is the
/// dev slider, 0.0 (no resistance at all) to 1.0 (very hard).
///
///   gain(u, r) = 1 / (1 + K * r * u^p)
///
/// Because the gain shrinks as `u` grows, the pull gets heavier the further it
/// goes — the last stretch is the hardest, which is the whole point.
///
/// The total finger distance needed to cross the track is the integral of
/// 1/gain over the track, which works out to `1 + K*r/(p+1)` track-widths —
/// about 1.44 track-widths at resistance 1.0. That is deliberately sized to
/// still fit inside a single determined swipe on a phone screen: 1.0 is meant
/// to be punishing, never impossible.
double resistanceGain(double offProgress, double resistance) {
  final u = offProgress.clamp(0.0, 1.0);
  final r = resistance.clamp(0.0, 1.0);
  if (r <= 0.0) return 1.0; // 0.0 means the knob tracks the finger exactly.

  final gain = 1.0 / (1.0 + kResistanceStrength * r * math.pow(u, kResistanceCurve));
  return math.max(gain, kMinGain);
}

/// The spring the knob snaps back with when the user lets go too early.
///
/// Higher resistance gives a stiffer spring, so a failed pull is yanked back
/// faster and more rudely. The damping ratio is just under 1.0, which leaves a
/// small overshoot — that visible wobble is what the `wobble` haptic preset is
/// timed against.
SpringDescription snapBackSpring(double resistance) {
  final r = resistance.clamp(0.0, 1.0);
  return SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 180.0 + 320.0 * r,
    ratio: 0.72,
  );
}
