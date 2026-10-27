import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../resistance.dart';
import '../services/haptics.dart';

/// A skeuomorphic "slide to unlock" switch.
///
/// The knob rests at the right end when [value] is true (Instagram blocked)
/// and at the left end when it is false (allowed). Dragging left-to-right to
/// switch blocking ON is a plain 1:1 swipe. Dragging right-to-left to switch
/// blocking OFF is rubber-banded by [resistance] (see [resistanceGain]) and
/// springs back unless the knob is pulled the whole way across.
class SlideSwitch extends StatefulWidget {
  const SlideSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.haptics,
    this.resistance = 0.6,
    this.height = 72.0,
  });

  /// True = blocked. The knob rests at the right end.
  final bool value;

  /// Fired once the knob has been dragged the full width of the track.
  final ValueChanged<bool> onChanged;

  final Haptics haptics;

  /// 0.0 (knob follows the finger exactly) to 1.0 (very hard). Only affects
  /// dragging toward OFF.
  final double resistance;

  final double height;

  @override
  State<SlideSwitch> createState() => _SlideSwitchState();
}

class _SlideSwitchState extends State<SlideSwitch>
    with TickerProviderStateMixin {
  /// Normalized knob position: 0.0 at the left end, 1.0 at the right end.
  /// Driven directly during a drag and by a spring simulation afterwards.
  late final AnimationController _pos;

  /// Free-running controller for the sweep across the hint text.
  late final AnimationController _shimmer;

  /// Horizontal distance in pixels the knob's centre can travel. Measured
  /// during layout, so gestures can convert pixels to normalized units.
  double _trackSpan = 0.0;

  /// Set once the knob reaches the far end, so a completed pull does not also
  /// get treated as a failed one when the finger lifts.
  bool _completed = false;

  /// Which of the discrete tick points have already fired this drag.
  final List<bool> _ticked = <bool>[false, false, false];
  static const List<double> _tickStops = <double>[0.25, 0.5, 0.75];

  /// How far the knob must come back from its resting end before releasing it
  /// counts as a failed pull worth a wobble, rather than a stray tap.
  static const double _wobbleThreshold = 0.04;

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    )..addListener(_onPosChanged);
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SlideSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The state can change from outside the widget (restored at startup, or
    // cleared by the platform). Glide the knob to the matching end.
    if (oldWidget.value != widget.value && !_completed) {
      _springTo(widget.value ? 1.0 : 0.0, 0.0);
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _onPosChanged() => setState(() {});

  // --- gesture handling ----------------------------------------------------

  void _onDragStart(DragStartDetails _) {
    _pos.stop();
    _completed = false;
    for (var i = 0; i < _ticked.length; i++) {
      // Points already behind the knob should not fire on the way past.
      _ticked[i] = _pos.value >= _tickStops[i];
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_trackSpan <= 0 || _completed) return;

    final delta = details.delta.dx / _trackSpan;
    final current = _pos.value;

    if (widget.value) {
      // Blocked: the user is pulling left toward OFF, against the rubber band.
      // Resistance applies to leftward motion only — letting the band relax
      // back toward the blocked end is free.
      final gain = delta < 0
          ? resistanceGain(1.0 - current, widget.resistance)
          : 1.0;
      _pos.value = (current + delta * gain).clamp(0.0, 1.0);
      widget.haptics.tension(
        offProgress: 1.0 - _pos.value,
        resistance: widget.resistance,
      );
      if (_pos.value <= 0.0) _complete(false);
    } else {
      // Allowed: pushing right toward ON. No resistance, just ticks.
      _pos.value = (current + delta).clamp(0.0, 1.0);
      _fireTicks(_pos.value);
      if (_pos.value >= 1.0) _complete(true);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_completed) {
      _completed = false;
      return;
    }
    widget.haptics.stopTension();

    final resting = widget.value ? 1.0 : 0.0;
    final travelled = (_pos.value - resting).abs();
    if (travelled > _wobbleThreshold) widget.haptics.snapBack();

    final velocity = _trackSpan > 0
        ? (details.primaryVelocity ?? 0.0) / _trackSpan
        : 0.0;
    _springTo(resting, velocity);
  }

  void _onDragCancel() {
    if (_completed) {
      _completed = false;
      return;
    }
    widget.haptics.stopTension();
    _springTo(widget.value ? 1.0 : 0.0, 0.0);
  }

  /// The knob made it all the way across: commit the new state.
  void _complete(bool newValue) {
    _completed = true;
    widget.haptics.stopTension();
    if (newValue) {
      widget.haptics.blocked();
    } else {
      widget.haptics.unblocked();
    }
    widget.onChanged(newValue);
  }

  /// Fires the evenly spaced discrete ticks on the way toward ON.
  void _fireTicks(double t) {
    for (var i = 0; i < _tickStops.length; i++) {
      if (!_ticked[i] && t >= _tickStops[i]) {
        _ticked[i] = true;
        widget.haptics.tick();
      }
    }
  }

  void _springTo(double target, double velocity) {
    _pos.animateWith(
      SpringSimulation(
        snapBackSpring(widget.resistance),
        _pos.value,
        target,
        velocity,
      ),
    );
  }

  // --- painting ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final knobDiameter = widget.height - 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _trackSpan = width - knobDiameter - 10.0;

        final t = _pos.value.clamp(0.0, 1.0);
        final resting = widget.value ? 1.0 : 0.0;
        // Hint text fades as the knob is pulled away from its resting end.
        final hintOpacity = (1.0 - (t - resting).abs() * 2.2).clamp(0.0, 1.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: <Widget>[
                _buildTrack(),
                Positioned.fill(
                  child: Opacity(
                    opacity: hintOpacity,
                    child: _buildHintText(knobDiameter),
                  ),
                ),
                Positioned(
                  left: 5.0 + t * _trackSpan,
                  top: 5.0,
                  child: _buildKnob(knobDiameter),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The recessed channel. Flutter has no inset shadow, so the recess is faked:
  /// a dark gradient body, a shadow-coloured wash at the top that fades out,
  /// and a pale hairline along the bottom edge acting as the lip catching light.
  Widget _buildTrack() {
    final radius = BorderRadius.circular(widget.height / 2);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF15181D), Color(0xFF2A2F38)],
        ),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x66000000), Color(0x00000000), Color(0x22FFFFFF)],
            stops: <double>[0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }

  /// The hint text, with a highlight repeatedly sweeping across it.
  Widget _buildHintText(double knobDiameter) {
    final label = widget.value ? 'slide to unblock' : 'slide to block';
    // Leave room for the parked knob so the text sits in the open channel.
    final padLeft = widget.value ? 12.0 : knobDiameter + 12.0;
    final padRight = widget.value ? knobDiameter + 12.0 : 12.0;

    return Padding(
      padding: EdgeInsets.only(left: padLeft, right: padRight),
      child: Center(
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, child) {
            // Slide a narrow bright band across a dim base colour.
            final x = _shimmer.value * 3.0 - 1.0;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(x - 0.6, 0.0),
                end: Alignment(x + 0.6, 0.0),
                colors: const <Color>[
                  Color(0xFF6B7280),
                  Color(0xFFF4F6FA),
                  Color(0xFF6B7280),
                ],
              ).createShader(bounds),
              child: child,
            );
          },
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// The glossy knob: a vertical grey gradient for the body, a soft drop
  /// shadow, and a bright elliptical highlight across the top half for glass.
  Widget _buildKnob(double diameter) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFFFFFFFF),
            Color(0xFFE2E5EA),
            Color(0xFFB4B9C2),
          ],
          stops: <double>[0.0, 0.55, 1.0],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x40FFFFFF), blurRadius: 1, offset: Offset(0, -1)),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // Glass highlight.
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              widthFactor: 0.78,
              heightFactor: 0.46,
              child: Container(
                margin: const EdgeInsets.only(top: 3),
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(40, 20)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xCCFFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          ),
          Icon(
            widget.value ? Icons.chevron_left : Icons.chevron_right,
            size: diameter * 0.52,
            color: const Color(0xFF6B7280),
          ),
        ],
      ),
    );
  }
}
