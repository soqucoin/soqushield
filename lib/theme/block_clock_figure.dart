// THE BLOCK CLOCK — the Network screen's hero, built to the figure rules of
// figures.dart: solid uniform strokes, typographic stat blocks, real data
// only, the shared breath and a billet on an event.
//
// A ring fills clockwise from twelve over the target spacing since the last
// block; past the target it keeps going in the dim tone (the chain is late
// against its target, as chains often are), and a new block resets it with a
// billet running the ring. The centre reads the time since the last block;
// the two stat blocks read the height and the network hashrate. Offline, the
// ring is a dashed slate and the centre reads a dash.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'instrument.dart';
import 'motion.dart';

/// The comet head's angle on the ring at [fraction] of the target spacing,
/// measured from twelve: the true elapsed fraction, so a late block keeps
/// the head on its second lap at the angle of a first.
double cometHeadAngle(double fraction) =>
    -math.pi / 2 + (fraction % 1.0) * 2 * math.pi;

/// How lit tick [index] is (0 at twelve, clockwise, twelve a lap) at
/// [fraction]: full as the head reaches it, decaying with
/// [MotionTiming.tick] at [targetSeconds] a lap; nothing for a tick the
/// head has not reached this lap. The head exactly on a tick is a crossing
/// and lights it in full; only the start of the lap is nothing.
double tickFlareAlpha(double fraction, int index, double targetSeconds) {
  if (fraction <= 0 || targetSeconds <= 0) return 0;
  final passed = (fraction % 1.0) * 12 - index; // in ticks
  if (passed < 0) return 0;
  final seconds = passed / 12 * targetSeconds;
  return decay(seconds, MotionTiming.tick.inMilliseconds / 1000);
}

class BlockClockPainter extends CustomPainter {
  final double breath; // 0..1 ambient loop
  final double pulse; // 0..1 billet progress, or < 0 when idle
  final bool live;
  final double fraction; // elapsed / target; may exceed 1
  final String centreValue; // '0:42' or '—'
  final String centreSub; // 'SINCE LAST BLOCK' / 'OFFLINE'
  final String leftValue; // 'BLOCK 112,127'
  final String leftSub; // 'HEIGHT'
  final String rightValue; // '20.4 GH/s'
  final String rightSub; // 'NETWORK HASHRATE'
  final bool motion; // the comet head and the tick lights, on a clocked chain
  final double targetSeconds; // one lap of the ring

  BlockClockPainter({
    required this.breath,
    required this.pulse,
    required this.live,
    required this.fraction,
    this.motion = false,
    this.targetSeconds = 60,
    required this.centreValue,
    required this.centreSub,
    required this.leftValue,
    required this.leftSub,
    required this.rightValue,
    required this.rightSub,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final cy = size.height / 2;
    final r = math.min(size.height * 0.40, w * 0.19);
    final breathA = 0.5 + 0.5 * math.sin(breath * 2 * math.pi);

    TextPainter tp(String s, double fs, Color c,
        {String font = kMono, FontWeight fw = FontWeight.w400, double ls = 0}) {
      final t = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                color: c,
                fontSize: fs,
                fontFamily: font,
                fontWeight: fw,
                letterSpacing: ls)),
        textDirection: TextDirection.ltr,
      )..layout();
      return t;
    }

    // ── the ring: twelve hairline ticks, the seam ring, the filled arc ──
    final centre = Offset(cx, cy);
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Instrument.line;
    if (live) {
      canvas.drawCircle(centre, r, seam);
    } else {
      // Not connected: a dashed slate ring.
      seam.color = Instrument.lineHi;
      const dashes = 36;
      for (var i = 0; i < dashes; i++) {
        final a0 = -math.pi / 2 + i * 2 * math.pi / dashes;
        canvas.drawArc(Rect.fromCircle(center: centre, radius: r), a0,
            math.pi / dashes, false, seam);
      }
    }
    final tick = Paint()
      ..strokeWidth = 1.0
      ..color = Instrument.lineHi;
    for (var i = 0; i < 12; i++) {
      final a = -math.pi / 2 + i * math.pi / 6;
      final inner = r - 5;
      final outer = r - 1;
      canvas.drawLine(
          Offset(cx + inner * math.cos(a), cy + inner * math.sin(a)),
          Offset(cx + outer * math.cos(a), cy + outer * math.sin(a)),
          tick);
    }

    if (live) {
      final rect = Rect.fromCircle(center: centre, radius: r);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.butt;
      // The first lap, copper, breathing at rest.
      final lap1 = fraction.clamp(0.0, 1.0);
      arc.color = Instrument.signal.withValues(alpha: 0.85 + 0.15 * breathA);
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * lap1, false, arc);
      // Past the target: a dim lap over the copper, the chain is late.
      if (fraction > 1) {
        final lap2 = (fraction - 1).clamp(0.0, 1.0);
        arc.color = Instrument.signalDim;
        canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * lap2, false, arc);
      }
      // The target mark at twelve.
      canvas.drawLine(Offset(cx, cy - r - 7), Offset(cx, cy - r + 1),
          Paint()
            ..strokeWidth = 1.6
            ..color = Instrument.signal.withValues(alpha: 0.9));
      if (motion) {
        // The comet head at the true fraction, its trail fading eighty
        // degrees behind it, drawn in short arcs so the seam at twelve
        // needs no special case.
        final a = cometHeadAngle(fraction);
        const segments = 16;
        const trail = 80 * math.pi / 180;
        final trailPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.butt
          ..blendMode = BlendMode.plus;
        for (var i = 0; i < segments; i++) {
          final t = i / segments; // from the trail's faint end to the head
          trailPaint.color = Color.lerp(Instrument.signal, Instrument.leadEdge, t)!
              .withValues(alpha: 0.85 * t * t);
          canvas.drawArc(rect, a - trail + t * trail, trail / segments + 0.002,
              false, trailPaint);
        }
        paintGlowDot(canvas, Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
            6, 0.95);
        // The ticks light as the head passes them.
        for (var i = 0; i < 12; i++) {
          final lit = tickFlareAlpha(fraction, i, targetSeconds);
          if (lit < 0.02) continue;
          final ta = -math.pi / 2 + i * math.pi / 6;
          canvas.drawLine(
              Offset(cx + (r - 6) * math.cos(ta), cy + (r - 6) * math.sin(ta)),
              Offset(cx + r * math.cos(ta), cy + r * math.sin(ta)),
              Paint()
                ..strokeWidth = 1.8
                ..color = Instrument.leadEdge.withValues(alpha: lit));
          paintGlowDot(
              canvas,
              Offset(cx + (r - 1) * math.cos(ta), cy + (r - 1) * math.sin(ta)),
              4,
              0.8 * lit);
        }
      }
    }

    // ── the centre: the time since the last block over its eyebrow ──
    final value = tp(centreValue, 24, live ? Instrument.readout : Instrument.faint,
        fw: FontWeight.w600, ls: -0.5);
    final sub = tp(centreSub, 7.5, Instrument.label, font: kLabel, ls: 7.5 * 0.14);
    value.paint(canvas, Offset(cx - value.width / 2, cy - value.height / 2 - 6));
    sub.paint(canvas, Offset(cx - sub.width / 2, cy + value.height / 2 - 2));

    // ── the stat blocks, left and right of the ring ──
    final x0 = w * 0.055;
    final xr = w - x0;
    final lv = tp(leftValue, 12.5, Instrument.readout, fw: FontWeight.w600);
    final lsub = tp(leftSub, 8, Instrument.label, font: kLabel, ls: 8 * 0.12);
    lv.paint(canvas, Offset(x0, cy - 10));
    lsub.paint(canvas, Offset(x0, cy + 9));
    final rv = tp(rightValue, 12.5, Instrument.readout, fw: FontWeight.w600);
    final rsub = tp(rightSub, 8, Instrument.label, font: kLabel, ls: 8 * 0.12);
    rv.paint(canvas, Offset(xr - rv.width, cy - 10));
    rsub.paint(canvas, Offset(xr - rsub.width, cy + 9));

    // ── the billet: on a new block, one bead runs the ring from twelve ──
    if (live && pulse >= 0 && pulse <= 1) {
      final fade =
          pulse < 0.85 ? 1.0 : (1 - (pulse - 0.85) / 0.15).clamp(0.0, 1.0);
      final a = -math.pi / 2 + pulse * 2 * math.pi;
      final b = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      final bp = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      bp.color = Instrument.leadEdge.withValues(alpha: 0.9 * fade);
      canvas.drawCircle(b, 2.8, bp);
      bp.color = Instrument.signal.withValues(alpha: 0.5 * fade);
      canvas.drawCircle(b, 5.0, bp);
    }
  }

  @override
  bool shouldRepaint(covariant BlockClockPainter old) =>
      old.breath != breath ||
      old.pulse != pulse ||
      old.live != live ||
      old.fraction != fraction ||
      old.motion != motion ||
      old.targetSeconds != targetSeconds ||
      old.centreValue != centreValue ||
      old.centreSub != centreSub ||
      old.leftValue != leftValue ||
      old.rightValue != rightValue ||
      old.leftSub != leftSub ||
      old.rightSub != rightSub;
}
