// The motion toolkit of the instrument language: the primitives the figures
// and the controls share for motion that fires once on a real event and
// comes to rest. The screens own the triggers (a new block, a copy, a
// toggle); this file owns the look and the timing, so every flare, bracket
// and ring in the app decays the same way.
//
// Rules the callers keep: nothing loops but the figures' breath; a value is
// never animated through a figure it did not have; brackets frame, they do
// not verify. Reduced motion (the platform's accessibility setting, read by
// [reducedMotionOf]) shows every effect's end state at once.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'instrument.dart';

/// The timing vocabulary, one value for each kind of motion, app-wide.
class MotionTiming {
  /// A flare's time constant: a glow is at 1/e after this long.
  static const flare = Duration(milliseconds: 350);

  /// Corner brackets travelling from outside a frame onto it.
  static const converge = Duration(milliseconds: 450);

  /// A ring expanding from a control and fading.
  static const ring = Duration(milliseconds: 350);

  /// A copper wash crossing a line of text.
  static const wipe = Duration(milliseconds: 700);

  /// A fade to rest after a lock.
  static const fade = Duration(milliseconds: 900);

  /// The opacity blip that stands in for a wipe under reduced motion.
  static const blip = Duration(milliseconds: 150);
}

/// True when the platform asks for reduced motion (iOS Reduce Motion, the
/// Android animator scale at zero). False where no media query exists.
bool reducedMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Exponential decay from 1 at [t] = 0 with the time constant [tau], both
/// in seconds; 0 before the event.
double decay(double t, double tau) => t < 0 ? 0.0 : math.exp(-t / tau);

/// A glow bead: a bright core with a soft halo, additive, built from a radial
/// gradient rather than a blur so it costs one draw on any device.
void paintGlowDot(Canvas canvas, Offset centre, double radius, double alpha,
    {Color core = Instrument.leadEdge, Color halo = Instrument.signal}) {
  if (alpha <= 0 || radius <= 0) return;
  final a = alpha.clamp(0.0, 1.0);
  final paint = Paint()
    ..blendMode = BlendMode.plus
    ..shader = RadialGradient(
      colors: [
        core.withValues(alpha: a),
        halo.withValues(alpha: a * 0.55),
        halo.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.35, 1.0],
    ).createShader(Rect.fromCircle(center: centre, radius: radius));
  canvas.drawCircle(centre, radius, paint);
}

/// A glow line: a wide soft halo under a core stroke.
void paintGlowLine(
    Canvas canvas, Offset a, Offset b, double width, double alpha,
    {Color color = Instrument.leadEdge}) {
  if (alpha <= 0) return;
  final al = alpha.clamp(0.0, 1.0);
  canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = width * 4
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..color = Instrument.signal.withValues(alpha: 0.25 * al));
  canvas.drawLine(
      a,
      b,
      Paint()
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: al));
}

/// Four corner brackets around [frame], each leg [length] long, drawn
/// [offset] outside it. Framing, never verification.
void paintBrackets(
    Canvas canvas, Rect frame, double offset, double length, double alpha,
    {double stroke = 1.6, Color color = Instrument.leadEdge}) {
  if (alpha <= 0) return;
  final r = frame.inflate(offset);
  final l = math.min(length, math.min(r.width, r.height) / 2);
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke
    ..strokeCap = StrokeCap.butt
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
  for (final (cx, cy, sx, sy) in [
    (r.left, r.top, 1.0, 1.0),
    (r.right, r.top, -1.0, 1.0),
    (r.left, r.bottom, 1.0, -1.0),
    (r.right, r.bottom, -1.0, -1.0),
  ]) {
    canvas.drawPath(
        Path()
          ..moveTo(cx, cy + sy * l)
          ..lineTo(cx, cy)
          ..lineTo(cx + sx * l, cy),
        p);
  }
}

/// The four corners of [frame] inflated by [offset], for a flare at each.
List<Offset> bracketCorners(Rect frame, double offset) {
  final r = frame.inflate(offset);
  return [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
}

/// A lock-on: brackets converge from [from] to [to] outside [frame] over
/// [MotionTiming.converge], flare at the corners as they land, then settle
/// to [restAlpha] over [MotionTiming.fade]. [t] is seconds since the start.
/// [restAlpha] 0 removes them; a positive value keeps them as a frame.
void paintLockOn(Canvas canvas, Rect frame, double t,
    {double from = 24, double to = 4, double length = 7, double restAlpha = 0}) {
  if (t < 0) return;
  final converge = MotionTiming.converge.inMilliseconds / 1000;
  final fade = MotionTiming.fade.inMilliseconds / 1000;
  final c = (t / converge).clamp(0.0, 1.0);
  final offset = from + (to - from) * Curves.easeOutCubic.transform(c);
  final settle = ((t - converge) / fade).clamp(0.0, 1.0);
  final alpha = 1.0 + (restAlpha - 1.0) * settle;
  final color = Color.lerp(Instrument.leadEdge, Instrument.signalDim, settle)!;
  paintBrackets(canvas, frame, offset, length, alpha, color: color);
  if (c >= 1) {
    final flare = decay(t - converge, MotionTiming.flare.inMilliseconds / 1000);
    for (final corner in bracketCorners(frame, to)) {
      paintGlowDot(canvas, corner, 5, 0.9 * flare);
    }
  }
}

/// A ring that expands from a point on [child] and fades, once per change of
/// [trigger], clipped to the child's bounds, with a glow at the origin that
/// decays with it (the knob, the finger). The origin is [origin] in the
/// child's coordinates, else [originFor] of the child's size, else the
/// centre. Under reduced motion nothing is drawn: the control's own change
/// is the confirmation.
class RingPulse extends StatefulWidget {
  final Widget child;
  final Object? trigger;
  final Offset? origin;
  final Offset Function(Size size)? originFor;
  const RingPulse({
    super.key,
    required this.child,
    required this.trigger,
    this.origin,
    this.originFor,
  });
  @override
  State<RingPulse> createState() => RingPulseState();
}

class RingPulseState extends State<RingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: MotionTiming.ring);
  Offset? _origin;

  /// True while a ring is in flight.
  bool get active => _ring.isAnimating;

  @override
  void didUpdateWidget(RingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) fire();
  }

  /// One ring from the origin, unless the platform asks for reduced motion.
  void fire() {
    if (reducedMotionOf(context)) return;
    _origin = widget.origin;
    _ring.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-ring: end it, and repaint to nothing.
    if (reducedMotionOf(context) && _ring.isAnimating) {
      _ring.stop();
      _ring.value = 0;
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ClipRect(
          child: CustomPaint(
            foregroundPainter: _RingPainter(_ring, _origin, widget.originFor),
            child: widget.child,
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final Animation<double> ring;
  final Offset? origin;
  final Offset Function(Size size)? originFor;
  _RingPainter(this.ring, this.origin, this.originFor) : super(repaint: ring);

  @override
  void paint(Canvas canvas, Size size) {
    if (!ring.isAnimating) return;
    final p = ring.value;
    final c = origin ??
        originFor?.call(size) ??
        Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOutCubic.transform(p);
    final radius = 15 + 115 * eased;
    final alpha = (1 - p) * math.exp(-2.5 * p);
    canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..blendMode = BlendMode.plus
          ..color = Instrument.leadEdge.withValues(alpha: alpha));
    paintGlowDot(canvas, c, 12, 0.8 * (1 - p));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.ring != ring || old.origin != origin || old.originFor != originFor;
}

/// A copper wash with a bright leading edge crossing [child] from left to
/// right once per change of [trigger], after [delay]; the glyphs stay legible
/// throughout and the text ends as it began. Under reduced motion a short
/// opacity blip stands in for the sweep.
class TintWipe extends StatefulWidget {
  final Widget child;
  final Object? trigger;
  final Duration delay;
  const TintWipe({
    super.key,
    required this.child,
    required this.trigger,
    this.delay = Duration.zero,
  });
  @override
  State<TintWipe> createState() => TintWipeState();
}

class TintWipeState extends State<TintWipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wipe =
      AnimationController(vsync: this, duration: MotionTiming.wipe);
  bool _blip = false;

  /// True while a wipe (or its reduced-motion blip) is in flight.
  bool get active => _wipe.isAnimating;

  @override
  void didUpdateWidget(TintWipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) fire();
  }

  /// One sweep, or one blip under reduced motion.
  void fire() {
    _blip = reducedMotionOf(context);
    _wipe.duration =
        _blip ? MotionTiming.blip : widget.delay + MotionTiming.wipe;
    _wipe.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-sweep: the text ends as it began.
    if (reducedMotionOf(context) && _wipe.isAnimating && !_blip) {
      _wipe.stop();
      _wipe.value = 0;
    }
  }

  @override
  void dispose() {
    _wipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _wipe,
          child: widget.child,
          builder: (_, child) {
            if (!_wipe.isAnimating) return child!;
            if (_blip) {
              return Opacity(
                  opacity: 1 - 0.6 * math.sin(_wipe.value * math.pi),
                  child: child);
            }
            final total = _wipe.duration!.inMilliseconds;
            final delay = widget.delay.inMilliseconds;
            final p = ((_wipe.value * total - delay) / (total - delay))
                .clamp(0.0, 1.0);
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Instrument.signal.withValues(alpha: 0),
                  Instrument.signal.withValues(alpha: 0.75),
                  Instrument.leadEdge,
                  Instrument.leadEdge.withValues(alpha: 0),
                ],
                stops: tintWipeStops(p),
              ).createShader(bounds),
              child: child,
            );
          },
        ),
      );
}

/// The tint wipe's gradient stops at sweep progress [p]: the tail of the
/// wash, the wash, the leading edge and its far side, each clamped to the
/// text's width. The leading edge runs from past the left edge to well past
/// the right, so the wash trailing 0.45 of the width behind it has left the
/// text by the last frame and the text ends as it began, with no cut.
List<double> tintWipeStops(double p) {
  final x = -0.1 + 1.6 * Curves.easeInOut.transform(p);
  double stop(double v) => v.clamp(0.0, 1.0);
  return [stop(x - 0.45), stop(x - 0.08), stop(x), stop(x + 0.05)];
}
