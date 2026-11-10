// The point scene: the figures of the site's scene (soqu-web-next,
// site/js/lattice.js) drawn on a canvas. One set of points holds a shape,
// the Soqucoin mark or the module lattice, and the same motion carries both.
//
// The site moves its points in a vertex shader. The same arithmetic runs
// here on the CPU for at most 2,000 points a frame: each point can be thrown
// from its place by its own random vector, a settled point keeps a small
// drift, far points cool toward blue and near ones run hot, and the light is
// additive. The lattice adds its edges, with signal packets running along
// some of them; a scan can sweep either figure.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'instrument.dart';
import 'mark_points.dart';
import 'motion.dart';

/// The points of one figure and what each carries: its place, its throw, its
/// drift phase and whether it is a hub. Built once and held by the screen;
/// the buffers the painter fills each frame live here too.
class PointField {
  /// The Soqucoin mark, facing the viewer. [count] takes the first points of
  /// the generated list, which is spread evenly over the mark at any length;
  /// a small figure wants fewer, so its light does not pile up.
  PointField.mark({int? count})
    : count = math.min(
        count ?? kMarkPoints.length ~/ 2,
        kMarkPoints.length ~/ 2,
      ),
      reach = _markSpan / 2,
      depthReach = 0,
      baseYaw = 0,
      yawRate = 0,
      sway = 0.04,
      pitch = 0,
      _edges = Uint16List(0) {
    final rng = _allocate();
    for (var i = 0; i < this.count; i++) {
      // A little jitter takes the points off the sampling grid.
      final gx = kMarkPoints[i * 2] + (rng.nextDouble() - 0.5) * 0.6;
      final gy = kMarkPoints[i * 2 + 1] + (rng.nextDouble() - 0.5) * 0.6;
      _home[i * 3] = (gx / kMarkGrid - 0.5) * _markSpan;
      _home[i * 3 + 1] = (gy / kMarkGrid - 0.5) * _markSpan;
      _home[i * 3 + 2] = (rng.nextDouble() - 0.5) * 0.34;
      _hub[i] = rng.nextDouble() < 0.025 ? 1 : 0;
    }
  }

  /// The module lattice: [perAxis] cubed nodes on the site's sheared basis,
  /// joined by their edges, turning slowly.
  PointField.lattice({int perAxis = 6})
    : count = perAxis * perAxis * perAxis,
      depthReach = 0,
      baseYaw = 0.4,
      yawRate = 0.05,
      sway = 0,
      pitch = 0.2,
      reach = 0,
      _edges = Uint16List(3 * perAxis * perAxis * (perAxis - 1) * 2) {
    _allocate();
    final n = perAxis, c = (n - 1) / 2, gap = _latticeSpan / (n - 1);
    var far = 0.0, e = 0;
    int at(int i, int j, int k) => (i * n + j) * n + k;
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        for (var k = 0; k < n; k++) {
          final a = at(i, j, k) * 3;
          for (var q = 0; q < 3; q++) {
            _home[a + q] =
                ((i - c) * _b1[q] + (j - c) * _b2[q] + (k - c) * _b3[q]) * gap;
          }
          far = math.max(
            far,
            math.sqrt(
              _home[a] * _home[a] +
                  _home[a + 1] * _home[a + 1] +
                  _home[a + 2] * _home[a + 2],
            ),
          );
          for (final next in [
            if (i + 1 < n) at(i + 1, j, k),
            if (j + 1 < n) at(i, j + 1, k),
            if (k + 1 < n) at(i, j, k + 1),
          ]) {
            _edges[e++] = at(i, j, k);
            _edges[e++] = next;
          }
        }
      }
    }
    // The corners reach furthest and are few: the figure is fitted to the
    // body of the lattice and a corner may pass the frame as it turns.
    reach = far * 0.68;
    depthReach = far * 0.45;
    _lines = Float32List(_edges.length * 2);
    _packets = Float32List(_edges.length);
    _edgeSeed = Float32List(_edges.length ~/ 2);
    final rng = math.Random(2420);
    for (var i = 0; i < _edgeSeed.length; i++) {
      _edgeSeed[i] = rng.nextDouble();
    }
  }

  // The site's sizes, in scene units: the mark's width and the lattice's.
  static const double _markSpan = 4.6;
  static const double _latticeSpan = 3.9;

  // The lattice basis of lattice.js and of soqu.org/lattice3d.js, so every
  // figure of it describes the same object.
  static const _b1 = [1.0, 0.15, 0.1];
  static const _b2 = [0.13, 1.0, 0.17];
  static const _b3 = [0.08, 0.12, 1.0];

  /// Depth bands a frame's points are sorted into; then the hubs, then the
  /// points a scan is passing.
  static const int _bandCount = 5;

  final int count;

  /// Half the width the settled figure takes, and how far it comes toward
  /// the viewer as it turns: what the painter fits to its frame.
  double reach, depthReach;

  /// The pose: a resting turn, a turn per second, a sway and a tilt, radians.
  final double baseYaw, yawRate, sway, pitch;

  late final Float32List _home, _throw, _phase, _screen;
  late final Uint8List _hub;
  final Uint16List _edges;
  late final Float32List _edgeSeed, _lines, _packets;
  late final List<Float32List> _bands;
  late final List<int> _fill;

  bool get hasEdges => _edges.isNotEmpty;

  math.Random _allocate() {
    final n = count;
    // A fixed seed: a figure is the same every time it is shown.
    final rng = math.Random(204);
    _home = Float32List(n * 3);
    _throw = Float32List(n * 3);
    _phase = Float32List(n);
    _screen = Float32List(n * 2);
    _hub = Uint8List(n);
    for (var i = 0; i < n; i++) {
      _throw[i * 3] = rng.nextDouble() - 0.5;
      _throw[i * 3 + 1] = rng.nextDouble() - 0.5;
      _throw[i * 3 + 2] = rng.nextDouble() - 0.5;
      _phase[i] = rng.nextDouble();
    }
    _bands = List.generate(_bandCount + 2, (_) => Float32List(n * 2));
    _fill = List.filled(_bandCount + 2, 0);
    return rng;
  }
}

/// Paints a field at the time [clock] reports, in seconds.
///
/// [scatter] is how far the points are thrown from their places, in scene
/// units: 0 is the settled figure, [gatherScatter] gives the splash's
/// assembly. [scan] sweeps a band of light across the figure. [still] is the
/// reduced-motion frame: the figure settled, at rest, whatever the clock and
/// the scatter say.
class PointScenePainter extends CustomPainter {
  PointScenePainter({
    required this.field,
    required this.clock,
    required this.frame,
    this.scatter,
    this.scan = false,
    this.still = false,
  }) : super(repaint: Listenable.merge([clock, scatter]));

  final PointField field;
  final ValueListenable<double> clock;
  final ValueListenable<double>? scatter;

  /// Where the settled figure sits on the canvas. Points in flight are drawn
  /// wherever they are, across the whole canvas.
  final Rect frame;
  final bool scan;
  final bool still;

  /// How long the splash's assembly takes.
  static const double assembleSeconds = 2.2;

  /// The assembly at [seconds]: 0 scattered, 1 in place, on an ease-out cubic.
  static double assemblyAt(double seconds) {
    final x = (seconds / assembleSeconds).clamp(0.0, 1.0);
    return 1 - math.pow(1 - x, 3).toDouble();
  }

  /// The scatter of the assembly at [seconds]: thrown wide, then nothing.
  static double gatherScatter(double seconds) {
    final k = 1 - assemblyAt(seconds);
    return _wide * k * k;
  }

  // The scene's tones (lattice.js uCol, uHot, uFar): copper, its hot crest,
  // and the cool tone far points fade toward.
  static const Color _copper = Instrument.signal;
  static const Color _hot = Color(0xFFFFD2AE);
  static const Color _far = Color(0xFF4F74A8);

  static const double _camera = 6.6; // the camera's distance from the figure
  static const double _wide = 7.0; // the scatter of a figure not yet gathered

  // The depth (0 near, 1 far) of the band a settled, flat figure sits in.
  static const double _restDepth = 0.375;

  // (width as a multiple of the core, share of the alpha), widest first.
  static const _pointDiscs = [(3.0, 0.07), (1.8, 0.2), (1.0, 1.0)];
  static const _hubDiscs = [(5.0, 0.05), (3.2, 0.1), (1.9, 0.26), (1.0, 1.0)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = still ? 0.0 : clock.value;
    final thrown = still ? 0.0 : math.max(0.0, scatter?.value ?? 0.0);
    final settle = 1 - (thrown / _wide).clamp(0.0, 1.0);
    final beat = 0.5 + 0.5 * math.sin(t * 0.8);
    final fade = (0.35 + 0.65 * settle) * (0.8 + 0.2 * beat);
    // The figure turns a little as it gathers, on top of its own pose.
    final yaw =
        field.baseYaw +
        0.45 * (1 - settle) +
        (still ? 0.0 : t * field.yawRate + field.sway * math.sin(t * 0.45));
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(field.pitch), sinP = math.sin(field.pitch);

    final side = frame.shortestSide;
    // px per unit at the figure's middle; a figure with depth is fitted by
    // its near side, which looks larger.
    final focal = side / 2 / field.reach * (_camera - 0.75 * field.depthReach);
    final cx = frame.center.dx, cy = frame.center.dy;

    // The bloom the site adds in post: one soft copper glow behind the figure.
    final glow =
        (field.hasEdges ? 0.06 : 0.11) * settle * settle * (0.85 + 0.15 * beat);
    final glowRect = Rect.fromCircle(center: frame.center, radius: side * 0.95);
    canvas.drawCircle(
      frame.center,
      side * 0.95,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _copper.withValues(alpha: glow),
            _copper.withValues(alpha: glow * 0.35),
            _copper.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(glowRect),
    );

    // The scan: a band a sixth of the figure wide, crossing every four
    // seconds.
    final scanning = scan && !still;
    final scanX = field.reach * (-0.9 + 1.8 * ((t * 0.25) % 1));
    final scanHalf = field.reach * 0.17;

    const bands = PointField._bandCount;
    const hubBand = bands, litBand = bands + 1;
    final fill = field._fill..fillRange(0, bands + 2, 0);
    final home = field._home, thr = field._throw, phase = field._phase;
    final screen = field._screen;
    for (var i = 0; i < field.count; i++) {
      final a = i * 3;
      var x = home[a] + thr[a] * thrown;
      var y = home[a + 1] + thr[a + 1] * thrown;
      var z = home[a + 2] + thr[a + 2] * thrown;
      final s = phase[i];
      x += 0.012 * math.sin(t * 0.6 + s * 6.2831 + y);
      y += 0.012 * math.cos(t * 0.5 + s * 12.0 + z);
      z += 0.012 * math.sin(t * 0.4 + s * 3.0 + x);
      final lit = scanning && (x - scanX).abs() < scanHalf;
      final rx = x * cosY + z * sinY;
      final rz = z * cosY - x * sinY;
      final ry = y * cosP - rz * sinP;
      final dist = _camera - (y * sinP + rz * cosP);
      final px = cx + rx * focal / dist, py = cy + ry * focal / dist;
      if (dist < 0.6 ||
          px < -8 ||
          py < -8 ||
          px > size.width + 8 ||
          py > size.height + 8) {
        screen[i * 2] = double.nan; // behind the lens, or off the canvas
        continue;
      }
      screen[i * 2] = px;
      screen[i * 2 + 1] = py;
      final depth = ((dist - 3.0) / 9.0).clamp(0.0, 0.999);
      final b = lit
          ? litBand
          : field._hub[i] == 1
          ? hubBand
          : (depth * bands / 0.75).floor().clamp(0, bands - 1);
      final buf = field._bands[b];
      final n = fill[b];
      buf[n] = px;
      buf[n + 1] = py;
      fill[b] = n + 2;
    }

    final core = math.max(1.4, side * 0.0072);
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;

    // The lattice's edges, under its nodes. Thrown apart they would stretch
    // into long streaks, so they fade out early.
    if (field.hasEdges) {
      final lineA = (1 - thrown * 0.55).clamp(0.0, 1.0) * fade;
      if (lineA > 0.01) _paintEdges(canvas, paint, t, lineA, core);
    }

    // Each band is drawn as a core inside wider, fainter discs, which stack
    // into a soft falloff. A band nearer than the figure's middle is larger
    // and runs hot, a band behind it is smaller, dimmer and cool.
    for (var b = 0; b < bands + 2; b++) {
      if (fill[b] == 0) continue;
      final pts = Float32List.sublistView(field._bands[b], 0, fill[b]);
      final bright = b >= bands;
      // A hub or a scanned point is lit as a point at the figure's middle.
      final depth = bright ? _restDepth : (b + 0.5) * 0.75 / bands;
      final lean = depth - _restDepth;
      final tone = bright
          ? Color.lerp(_copper, _hot, 0.7)!
          : lean > 0
          ? Color.lerp(_copper, _far, (lean * 1.9).clamp(0.0, 1.0))!
          : Color.lerp(_copper, _hot, (-lean * 1.6).clamp(0.0, 1.0))!;
      final alpha =
          (bright ? 1.0 : 0.86) * fade * (1 - math.max(0.0, lean) * 0.9);
      final width =
          core *
          _camera /
          (3.0 + depth * 9.0) *
          (b == hubBand
              ? 1.7
              : b == litBand
              ? 1.35
              : 1.0);
      for (final (spread, share) in b == hubBand ? _hubDiscs : _pointDiscs) {
        canvas.drawRawPoints(
          PointMode.points,
          pts,
          paint
            ..color = tone.withValues(alpha: alpha * share)
            ..strokeWidth = width * spread,
        );
      }
    }
  }

  void _paintEdges(
    Canvas canvas,
    Paint paint,
    double t,
    double lineA,
    double core,
  ) {
    final edges = field._edges, screen = field._screen;
    final lines = field._lines, packets = field._packets;
    var n = 0, p = 0;
    for (var e = 0; e < edges.length; e += 2) {
      final a = edges[e] * 2, b = edges[e + 1] * 2;
      final ax = screen[a], bx = screen[b];
      if (ax.isNaN || bx.isNaN) continue;
      final ay = screen[a + 1], by = screen[b + 1];
      lines[n] = ax;
      lines[n + 1] = ay;
      lines[n + 2] = bx;
      lines[n + 3] = by;
      n += 4;
      // Three edges in ten carry a packet, each on its own phase.
      final seed = field._edgeSeed[e ~/ 2];
      if (still || (seed * 13.7) % 1 < 0.7) continue;
      final at = (t * 0.3 + seed * 7) % 1;
      packets[p] = ax + (bx - ax) * at;
      packets[p + 1] = ay + (by - ay) * at;
      p += 2;
    }
    if (n > 0) {
      canvas.drawRawPoints(
        PointMode.lines,
        Float32List.sublistView(lines, 0, n),
        paint
          ..color = _copper.withValues(alpha: 0.2 * lineA)
          ..strokeWidth = 0.8,
      );
    }
    if (p > 0) {
      final pts = Float32List.sublistView(packets, 0, p);
      final tone = Color.lerp(_copper, _hot, 0.8)!;
      canvas.drawRawPoints(
        PointMode.points,
        pts,
        paint
          ..color = tone.withValues(alpha: 0.16 * lineA)
          ..strokeWidth = core * 2.6,
      );
      canvas.drawRawPoints(
        PointMode.points,
        pts,
        paint
          ..color = tone.withValues(alpha: 0.9 * lineA)
          ..strokeWidth = core * 0.9,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PointScenePainter old) =>
      old.field != field ||
      old.clock != clock ||
      old.scatter != scatter ||
      old.frame != frame ||
      old.scan != scan ||
      old.still != still;
}

/// A figure of the point scene in a box, on its own clock. The settled
/// figure fills the box; points thrown by [scatter] fly beyond it. Under the
/// platform's reduced-motion setting the figure is one still frame.
class PointScene extends StatefulWidget {
  const PointScene({
    super.key,
    required this.field,
    this.scatter,
    this.scan = false,
  });

  final PointField field;

  /// How far the points are thrown, in scene units; an [Animation] serves.
  final ValueListenable<double>? scatter;

  /// A band of light sweeps the figure while this is true.
  final bool scan;

  @override
  State<PointScene> createState() => _PointSceneState();
}

class _PointSceneState extends State<PointScene>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker;
  double _base = 0;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (elapsed) => _clock.value = _base + elapsed.inMicroseconds / 1e6,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = reducedMotionOf(context);
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _base = _clock.value;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: LayoutBuilder(
      builder: (context, box) => CustomPaint(
        size: box.biggest,
        painter: PointScenePainter(
          field: widget.field,
          clock: _clock,
          frame: Offset.zero & box.biggest,
          scatter: widget.scatter,
          scan: widget.scan,
          still: _still,
        ),
      ),
    ),
  );
}
