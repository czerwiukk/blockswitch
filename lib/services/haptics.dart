import 'dart:math' as math;

import 'package:pulsar_haptics/pulsar.dart';

/// Every haptic in the app goes through this class.
///
/// One [Pulsar] instance is created here and reused app-wide, as the SDK asks.
/// Swapping which preset fires for which event is a one-line change in this
/// file and nowhere else.
///
/// Every method is safe to call on a device with no haptic hardware: [init]
/// records whether playback is possible and all the play methods no-op if not.
class Haptics {
  Haptics();

  /// Presets this app uses, preloaded at startup so the first play is not late.
  static const List<String> _preloaded = <String>[
    _lockPreset,
    _latchPreset,
    _wobblePreset,
    _buzzPreset,
  ];

  // The four event -> preset bindings. Change them here.
  static const String _lockPreset = 'lock'; // completed to ON (blocked)
  static const String _latchPreset = 'latch'; // completed to OFF (unblocked)
  static const String _wobblePreset = 'wobble'; // released early, snapped back
  static const String _buzzPreset = 'buzz'; // arrived via Instagram intercept

  /// How often realtime updates are allowed through to the platform channel.
  /// Drag updates arrive far faster than this; without the throttle we would
  /// flood the channel with set() calls that the hardware cannot act on anyway.
  static const Duration _realtimeInterval = Duration(milliseconds: 40);

  final Pulsar _pulsar = Pulsar();

  /// Whether the device can actually play haptics. Everything no-ops if false.
  bool _available = false;
  bool get isAvailable => _available;

  /// Dev-only multiplier on the realtime amplitude, driven by the debug slider.
  double intensity = 1.0;

  /// True between the first realtime [tension] call and the matching [stopTension].
  bool _realtimeActive = false;

  /// Measures the gap since the last realtime update, for the throttle.
  final Stopwatch _sinceLastRealtime = Stopwatch();

  /// Must be awaited once at startup, before the first haptic.
  Future<void> init() async {
    try {
      _available = await _pulsar.canPlayHaptics();
      if (_available) {
        await _pulsar.preloadPresets(_preloaded);
      }
    } catch (_) {
      // A device or emulator without haptic support should cost us nothing.
      _available = false;
    }
  }

  Future<void> _play(String preset) async {
    if (!_available) return;
    try {
      await _pulsar.getPresets().play(preset);
    } catch (_) {
      // Haptics are decoration; never let one break a gesture.
    }
  }

  /// Switch completed to ON — Instagram is now blocked.
  Future<void> blocked() => _play(_lockPreset);

  /// Switch completed to OFF — Instagram is allowed again.
  Future<void> unblocked() => _play(_latchPreset);

  /// Released before the end of the track; the knob is springing back.
  Future<void> snapBack() => _play(_wobblePreset);

  /// The app was opened by the Android intercept because Instagram was blocked.
  Future<void> intercepted() => _play(_buzzPreset);

  /// Continuous "tension" while dragging toward OFF.
  ///
  /// [offProgress] is 0.0 at the blocked end and 1.0 at the unblocked end;
  /// [resistance] is the dev slider. Amplitude climbs steeply with progress so
  /// the haptic gets heavier exactly where the rubber-banding gets heavier, and
  /// a higher resistance setting feels stronger throughout. Frequency rises
  /// more gently, which reads as the band stretching rather than just getting
  /// louder.
  ///
  /// Call this freely on every drag update — it throttles itself.
  Future<void> tension({
    required double offProgress,
    required double resistance,
  }) async {
    if (!_available) return;

    // Let the very first call through, then one every _realtimeInterval.
    if (_realtimeActive &&
        _sinceLastRealtime.elapsed < _realtimeInterval) {
      return;
    }
    _sinceLastRealtime
      ..reset()
      ..start();

    final u = offProgress.clamp(0.0, 1.0);
    final r = resistance.clamp(0.0, 1.0);

    final amplitude =
        (0.12 + 0.88 * math.pow(u, 1.4)) * (0.35 + 0.65 * r) * intensity;
    final frequency = 0.20 + 0.60 * u;

    _realtimeActive = true;
    try {
      await _pulsar.getRealtimeComposer().set(
            amplitude.clamp(0.0, 1.0),
            frequency.clamp(0.0, 1.0),
          );
    } catch (_) {
      // Ignore: see _play.
    }
  }

  /// Ends the continuous haptic. Safe to call when nothing is playing, and must
  /// be called on both drag end and drag cancel so the motor never sticks on.
  Future<void> stopTension() async {
    if (!_realtimeActive) return;
    _realtimeActive = false;
    _sinceLastRealtime.stop();
    try {
      await _pulsar.getRealtimeComposer().stop();
    } catch (_) {
      // Ignore: see _play.
    }
  }

  /// A light discrete tick, used at evenly spaced points while dragging to ON.
  Future<void> tick() async {
    if (!_available) return;
    try {
      await _pulsar
          .getRealtimeComposer()
          .playDiscrete((0.35 * intensity).clamp(0.0, 1.0), 0.6);
    } catch (_) {
      // Ignore: see _play.
    }
  }

}
