// Shared hero figures for the instrument language. Each is a real quantum-domain
// object whose MOTION comes from FigureMotion (the contract the NTT butterfly
// set) — so every figure breathes and sweeps the same way; only the geometry
// differs. Screens construct a painter per frame from their animation values.
//
// Every figure here carries real data at its call site. What remains:
// NttButterflyPainter (Send's signing phase), CrystallizingLatticePainter
// (activation/lock key events), the AssetGlyph marks, and TxAnatomyPainter
// (the Send instrument's stat schematic).
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'instrument.dart';

/// The font size at which [text] fits [maxWidth], starting from [size] and
/// shrinking as far as [minSize]: a figure's digits stay whole and exact
/// while the figure stays inside its column. Painters call it for every
/// value a user can make long (a balance, an amount).
double fitFontSize(String text, double size, double maxWidth,
    {double minSize = 8,
    String font = kMono,
    FontWeight weight = FontWeight.w400,
    double spacing = 0}) {
  if (maxWidth <= 0 || text.isEmpty) return size;
  final probe = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: size,
            fontFamily: font,
            fontWeight: weight,
            letterSpacing: spacing)),
    textDirection: TextDirection.ltr,
  )..layout();
  if (probe.width <= maxWidth) return size;
  // The floor never exceeds the size asked for: a label that does not fit
  // shrinks or stays, it never grows.
  return math.max(math.min(minSize, size), size * maxWidth / probe.width);
}

/// The NTT butterfly — ML-DSA's computational core (a recursive
/// number-theoretic-transform network). Breathes at rest; on an event a
/// wavefront sweeps the stages so a payment is "computed / quantum-signed."
/// dir +1 sweeps L→R (out / sign), -1 R→L (in / verify).
class NttButterflyPainter extends CustomPainter {
  final double breath;
  final double pulse;
  final int dir;
  final Color accent;
  final Color accentDim;
  NttButterflyPainter({
    required this.breath,
    required this.pulse,
    required this.dir,
    this.accent = Instrument.signal,
    this.accentDim = Instrument.signalDim,
  });

  static const int n = 8;
  static const int stages = 3; // log2(n)

  @override
  void paint(Canvas canvas, Size size) {
    final mx = size.width * 0.15, my = size.height * 0.08;
    final left = mx, right = size.width - mx, top = my, bottom = size.height - my;
    final colDx = (right - left) / stages, rowDy = (bottom - top) / (n - 1);
    Offset node(int c, int r) => Offset(left + c * colDx, top + r * rowDy);

    final m = FigureMotion(
        breath: breath,
        pulse: pulse,
        dir: dir,
        left: left,
        right: right,
        accent: accent,
        accentDim: accentDim);

    // ── edges, drawn as lit segments so the wavefront travels fluidly ──
    final ep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const seg = 7;
    for (var s = 0; s < stages; s++) {
      final span = 1 << s; // 1,2,4 — crossings widen each stage
      final wide = span / (n / 2);
      final baseW = 0.55 + wide * 0.75;
      final baseA = (0.085 + wide * 0.05) * (0.6 + 0.4 * m.breathA);
      for (var i = 0; i < n; i++) {
        if ((i & span) != 0) continue;
        final j = i | span;
        for (final pr in const [
          [0, 0],
          [1, 1],
          [0, 1],
          [1, 0]
        ]) {
          final a = node(s, pr[0] == 0 ? i : j);
          final b = node(s + 1, pr[1] == 0 ? i : j);
          for (var k = 0; k < seg; k++) {
            final p0 = Offset.lerp(a, b, k / seg)!;
            final p1 = Offset.lerp(a, b, (k + 1) / seg)!;
            final g = m.wavefront((p0.dx + p1.dx) / 2);
            ep
              ..color = g > 0.02
                  ? m.heat(g, baseA, extra: 0.85)
                  : Instrument.line.withValues(alpha: baseA)
              ..strokeWidth = baseW + g * 1.4;
            canvas.drawLine(p0, p1, ep);
          }
        }
      }
    }

    // ── nodes: fire & fade as the wavefront passes; I/O columns emphasized ──
    final np = Paint()..style = PaintingStyle.fill;
    for (var c = 0; c <= stages; c++) {
      final x = left + c * colDx;
      final g = m.wavefront(x);
      final io = (c == 0 || c == stages) ? 0.14 : 0.0;
      for (var r = 0; r < n; r++) {
        final baseA = (0.26 + io) * (0.64 + 0.36 * m.breathA);
        np
          ..color = m.heat(g, baseA, extra: 0.9)
          ..maskFilter =
              g > 0.12 ? MaskFilter.blur(BlurStyle.normal, 1.4 + g * 4) : null;
        canvas.drawCircle(node(c, r), 1.6 + g * 2.6, np);
      }
    }

    // ── the leading-edge glow line riding the wavefront ──
    if (m.active && m.frontX >= left - 14 && m.frontX <= right + 14) {
      final lp = Paint()
        ..color = Instrument.leadEdge.withValues(alpha: 0.5 * m.endFade)
        ..strokeWidth = 1.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawLine(
          Offset(m.frontX, top - 10), Offset(m.frontX, bottom + 10), lp);
    }
  }

  @override
  bool shouldRepaint(covariant NttButterflyPainter old) =>
      old.breath != breath ||
      old.pulse != pulse ||
      old.dir != dir ||
      old.accent != accent;
}

/// The CRYSTALLIZING LATTICE — keys born from quantum-hard noise into ordered
/// structure. At rest the lattice is settled and breathes. On an event the
/// "crystallize" parameter sweeps 0→1: nodes fly in from scattered noise to their
/// exact lattice positions and the edges materialise — the "Activation" moment,
/// your keys coming online. crystallize = the pulse while active, else 1 (settled).
class CrystallizingLatticePainter extends CustomPainter {
  final double breath;
  final double pulse; // 0..1 = crystallising; <0 = settled
  final Color accent;
  final Color accentDim;
  CrystallizingLatticePainter({
    required this.breath,
    required this.pulse,
    this.accent = Instrument.signal,
    this.accentDim = Instrument.signalDim,
  });

  static const int nx = 4; // 9 cols
  static const int ny = 3; // 7 rows

  // deterministic per-node hash → noise offset (no Math.random in paint)
  static double _h(int i, int j, int salt) {
    final x = math.sin(i * 127.1 + j * 311.7 + salt * 74.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mx = size.width * 0.14, my = size.height * 0.14;
    final left = mx, right = size.width - mx, top = my, bottom = size.height - my;
    final cx = (left + right) / 2, cy = (top + bottom) / 2;
    final colDx = (right - left) / (2 * nx), rowDy = (bottom - top) / (2 * ny);
    final amp = (colDx + rowDy) * 1.6; // how far the noise scatters nodes

    final breathA = 0.5 + 0.5 * math.sin(breath * 2 * math.pi);
    final c = (pulse < 0 ? 1.0 : pulse).clamp(0.0, 1.0); // crystallisation 0..1
    final ease = c * c * (3 - 2 * c); // smoothstep
    final order = ease; // 0 = noise, 1 = ordered

    Offset pos(int i, int j) {
      final ordered = Offset(cx + i * colDx, cy + j * rowDy);
      final ang = _h(i, j, 1) * 2 * math.pi;
      final mag = (0.4 + _h(i, j, 2)) * amp * (1 - order);
      return ordered + Offset(math.cos(ang) * mag, math.sin(ang) * mag);
    }

    Color heat(double a) =>
        Color.lerp(accentDim, accent, order)!.withValues(alpha: a.clamp(0.0, 1.0));

    // ── edges materialise as the lattice orders (alpha ∝ order²) ──
    final ep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.7;
    final edgeA = order * order * 0.16 * (0.6 + 0.4 * breathA);
    if (edgeA > 0.004) {
      ep.color = heat(edgeA);
      for (var i = -nx; i <= nx; i++) {
        for (var j = -ny; j <= ny; j++) {
          final p = pos(i, j);
          if (i < nx) canvas.drawLine(p, pos(i + 1, j), ep);
          if (j < ny) canvas.drawLine(p, pos(i, j + 1), ep);
        }
      }
    }

    // ── nodes: dim & scattered in noise, bright & sharp when ordered ──
    final np = Paint()..style = PaintingStyle.fill;
    for (var i = -nx; i <= nx; i++) {
      for (var j = -ny; j <= ny; j++) {
        final p = pos(i, j);
        final a = (0.12 + 0.20 * order) * (0.6 + 0.4 * breathA);
        np
          ..color = heat(a)
          ..maskFilter = order > 0.7
              ? MaskFilter.blur(BlurStyle.normal, (order - 0.7) * 6)
              : null;
        canvas.drawCircle(p, 1.2 + 1.4 * order, np);
      }
    }

    // ── the core glow — your key, condensing into being as it orders ──
    final coreA = (0.15 + 0.45 * order) * (0.7 + 0.3 * breathA);
    canvas.drawCircle(
        Offset(cx, cy),
        2.0 + 5.0 * order + 1.5 * breathA,
        Paint()
          ..color = Color.lerp(accent, Instrument.leadEdge, order * 0.5)!
              .withValues(alpha: coreA)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 7 * order));
  }

  @override
  bool shouldRepaint(covariant CrystallizingLatticePainter old) =>
      old.breath != breath || old.pulse != pulse || old.accent != accent;
}

/// A small precise asset mark next to an asset row: a lattice node (SOQ,
/// value in the lattice), echoing the figure vocabulary.
enum AssetMark { node }

class AssetGlyph extends StatelessWidget {
  final AssetMark mark;
  final Color color;
  final double size;
  const AssetGlyph(
      {super.key, required this.mark, required this.color, this.size = 18});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _AssetMarkPainter(mark, color)),
      );
}

class _AssetMarkPainter extends CustomPainter {
  final AssetMark mark;
  final Color color;
  _AssetMarkPainter(this.mark, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.40;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.85);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    switch (mark) {
      case AssetMark.node:
        // a lattice node: a rhombus outline + a lit centre dot
        final path = Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close();
        canvas.drawPath(path, stroke);
        canvas.drawCircle(c, 1.6, fill);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AssetMarkPainter old) =>
      old.mark != mark || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSACTION ANATOMY — the Send instrument, built to the merge-mining
// diagram's construction rules (soqupool/redesign/index.html #pourStage):
//
//   • solid, confident, UNIFORM strokes — a 2px trunk in the flow's colour,
//     1.6px branches; full opacity. No wispy width-∝-value tricks.
//   • dead-simple geometry — one horizontal trunk, ONE junction, V-then-H
//     right-angle branches. Nothing floats.
//   • the data lives in TYPOGRAPHIC STAT BLOCKS: a left intake column
//     (eyebrow / large mono value / sub-label) and ledger-style terminals
//     (bold mono value over a muted sub-label), anchored to a column grid.
//   • colour = destination (recipient in the flow colour, change in ink,
//     fee in muted; overspend recolours the recipient leg threat-red).
//   • motion = a BILLET travelling the paths (the pour), not a glow wash:
//     one bright bead runs the trunk, splits at the junction, rides all
//     three branches out. `breath` only breathes the signature gate.
// ─────────────────────────────────────────────────────────────────────────────
class TxAnatomyPainter extends CustomPainter {
  final double breath;
  final double pulse;
  final int dir; // kept for the figure contract; the pour always runs L→R
  final Color accent; // the flow colour: SOQ cyan / USDSOQ peg / private violet

  // The transaction, as display strings (the painter stays presentational).
  final String balanceValue; // '490.98'
  final String balanceSub; // 'tSOQ · SPENDABLE'
  final String toValue; // '125.00' or '—'
  final String toSub; // 'RECIPIENT' or 'EXCEEDS BALANCE'
  final String changeValue; // '365.98' or '—'
  final String feeValue; // '~0.0076' or '…'
  final String feeSub; // 'FEE' or 'FEE · SOQ'
  final String sigLabel; // 'ML-DSA-44 · 2,420 B'
  final bool overspend;
  final bool hasAmount;

  TxAnatomyPainter({
    required this.breath,
    required this.pulse,
    required this.dir,
    this.accent = Instrument.signal,
    required this.balanceValue,
    required this.balanceSub,
    required this.toValue,
    required this.toSub,
    required this.changeValue,
    required this.feeValue,
    required this.feeSub,
    required this.sigLabel,
    this.overspend = false,
    this.hasAmount = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cy = h * 0.52;
    final dy = h * 0.30; // branch spread
    // The branches end at 0.74 of the width so the ledger column on the
    // right holds eleven characters at the floor on a 402-point phone.
    final trunkX0 = w * 0.30, gateX = w * 0.44, jx = w * 0.58, bx = w * 0.74;
    final toY = cy - dy, feeY = cy + dy;
    final toColor = overspend ? Instrument.threat : accent;
    final breathA = 0.5 + 0.5 * math.sin(breath * 2 * math.pi);

    // ── text helper: one style vocabulary, anchored, never floating ──
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

    // ── the intake column (POOL INTAKE pattern): eyebrow / value / sub ──
    // The value fits the column, between the left margin and the trunk: a
    // mining balance with many digits shrinks rather than running into the
    // diagram. The figure itself is never shortened.
    final x0 = w * 0.055;
    final columnW = trunkX0 - x0 - 14; // clear of the bead's glow at the trunk
    tp('BALANCE', 8.5, Instrument.label, font: kLabel, ls: 8.5 * 0.16)
        .paint(canvas, Offset(x0, cy - 30));
    tp(balanceValue, fitFontSize(balanceValue, 19, columnW, weight: FontWeight.w600),
            Instrument.readout, fw: FontWeight.w600)
        .paint(canvas, Offset(x0, cy - 16));
    // A label shrinks as far as 6.5 points, its tracking with it.
    final balanceSubSize = fitFontSize(balanceSub, 8, columnW,
        minSize: 6.5, font: kLabel, spacing: 8 * 0.12);
    tp(balanceSub, balanceSubSize, Instrument.label,
            font: kLabel, ls: balanceSubSize * 0.12)
        .paint(canvas, Offset(x0, cy + 8));

    // ── trunk — 2px, solid, the flow's colour ──
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    stroke
      ..color = accent
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(trunkX0, cy), Offset(jx, cy), stroke);

    // ── branches — 1.6px, V then H, colour = destination ──
    void branch(double endY, Color c, double alpha) {
      stroke
        ..color = c.withValues(alpha: alpha)
        ..strokeWidth = 1.6;
      final p = Path()..moveTo(jx, cy);
      if (endY != cy) p.lineTo(jx, endY);
      p.lineTo(bx, endY);
      canvas.drawPath(p, stroke);
    }

    branch(toY, toColor, hasAmount || overspend ? 1.0 : 0.30);
    branch(cy, Instrument.readout, 0.55);
    branch(feeY, Instrument.label, 0.65);

    // junction bead — where one stream becomes three
    canvas.drawCircle(
        Offset(jx, cy), 2.4, Paint()..color = accent);

    // ── the signature gate — a diamond ON the trunk, breathing quietly ──
    const gr = 7.0;
    canvas.drawPath(
        Path()
          ..moveTo(gateX, cy - gr)
          ..lineTo(gateX + gr, cy)
          ..lineTo(gateX, cy + gr)
          ..lineTo(gateX - gr, cy)
          ..close(),
        Paint()..color = Instrument.void0); // punch out the trunk behind it
    canvas.drawPath(
        Path()
          ..moveTo(gateX, cy - gr)
          ..lineTo(gateX + gr, cy)
          ..lineTo(gateX, cy + gr)
          ..lineTo(gateX - gr, cy)
          ..close(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent.withValues(alpha: 0.75 + 0.25 * breathA));
    final sig = tp(sigLabel, 7.5, Instrument.label, font: kLabel, ls: 7.5 * 0.10);
    sig.paint(canvas, Offset(gateX - sig.width / 2, cy + gr + 6));

    // ── ledger terminals: bold mono value over a muted sub-label, each
    // fitted to the column between the branch ends and the right margin ──
    final terminalW = w - x0 - (bx + 10);
    void terminal(double y, String value, String sub, Color c) {
      tp(value, fitFontSize(value, 12.5, terminalW, weight: FontWeight.w600), c,
              fw: FontWeight.w600)
          .paint(canvas, Offset(bx + 10, y - 8));
      final subSize = fitFontSize(sub, 7.5, terminalW,
          minSize: 6.5, font: kLabel, spacing: 7.5 * 0.12);
      tp(sub, subSize,
              overspend && y == toY ? Instrument.threat : Instrument.label,
              font: kLabel, ls: subSize * 0.12)
          .paint(canvas, Offset(bx + 10, y + 6));
    }

    terminal(toY, toValue,
        toSub, hasAmount || overspend ? toColor : Instrument.label);
    terminal(cy, changeValue, 'CHANGE', Instrument.readout.withValues(alpha: 0.9));
    terminal(feeY, feeValue, feeSub, Instrument.label);

    // ── the pour: one billet runs the trunk, splits, rides all three out ──
    if (pulse >= 0 && pulse <= 1) {
      final fade =
          pulse < 0.85 ? 1.0 : (1 - (pulse - 0.85) / 0.15).clamp(0.0, 1.0);
      final bp = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      // path lengths: trunk leg vs branch leg (vertical + horizontal)
      final trunkLen = jx - trunkX0;
      void billetOn(double endY, Color c) {
        final vLen = (endY - cy).abs(), hLen = bx - jx;
        final total = trunkLen + vLen + hLen;
        final d = pulse * total;
        Offset pos;
        if (d < trunkLen) {
          pos = Offset(trunkX0 + d, cy);
        } else if (d < trunkLen + vLen) {
          final t = d - trunkLen;
          pos = Offset(jx, cy + (endY > cy ? t : -t));
        } else {
          pos = Offset(jx + (d - trunkLen - vLen), endY);
        }
        bp.color = Instrument.leadEdge.withValues(alpha: 0.9 * fade);
        canvas.drawCircle(pos, 2.6, bp);
        bp.color = c.withValues(alpha: 0.5 * fade);
        canvas.drawCircle(pos, 4.6, bp);
      }

      billetOn(toY, toColor);
      billetOn(cy, Instrument.readout);
      billetOn(feeY, accent);
    }
  }

  @override
  bool shouldRepaint(covariant TxAnatomyPainter old) =>
      old.breath != breath ||
      old.pulse != pulse ||
      old.accent != accent ||
      old.balanceValue != balanceValue ||
      old.balanceSub != balanceSub ||
      old.toValue != toValue ||
      old.toSub != toSub ||
      old.changeValue != changeValue ||
      old.feeValue != feeValue ||
      old.feeSub != feeSub ||
      old.sigLabel != sigLabel ||
      old.overspend != overspend ||
      old.hasAmount != hasAmount;
}
