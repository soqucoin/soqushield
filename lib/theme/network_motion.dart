// The Network tab's motion: the copper scanline that reveals the figures as
// they arrive and follows a finger held over them, lighting the row under
// it; and the pool's status dot, breathing, with one flare as an update
// lands. All of it is decorative: it shows nothing that is not already in
// the text, it fires on real events only (an arrival, a refresh, a held
// finger, an update) and it comes to rest. Under reduced motion the line
// stands still under the finger and nothing else moves.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'instrument.dart';
import 'motion.dart';

/// A row the scanner can pick up: its id, the card it sits in and the key
/// of the widget whose bounds it occupies.
class ScanRowEntry {
  final String id;
  final String section;
  final GlobalKey key;
  ScanRowEntry(this.id, this.section)
    : key = GlobalKey(debugLabel: 'scan row $id');
}

/// The rows of a screen and the pick they share. A row registers itself as
/// it builds (the key is stable per id, so a rebuild keeps it) and the
/// scanner asks which row holds a point.
class ScanRegistry {
  final Map<String, ScanRowEntry> _rows = {};

  /// The id of the row under the finger, or null.
  final ValueNotifier<String?> picked = ValueNotifier<String?>(null);

  /// The stable key for [id], registered in [section].
  GlobalKey keyFor(String id, String section) =>
      _rows.putIfAbsent(id, () => ScanRowEntry(id, section)).key;

  Iterable<(ScanRowEntry, Rect)> _laidOut() sync* {
    for (final row in _rows.values) {
      final box = row.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      yield (row, box.localToGlobal(Offset.zero) & box.size);
    }
  }

  /// The row whose bounds hold [global], or null.
  ScanRowEntry? rowAt(Offset global) {
    for (final (row, rect) in _laidOut()) {
      if (rect.contains(global)) return row;
    }
    return null;
  }

  /// The row edge (a top or a bottom) nearest to [globalY] among the rows
  /// that overlap [within] (the overlay's global bounds: a list keeps rows
  /// laid out past its edge, and the line never glides to one of those);
  /// null with no such row.
  double? nearestEdge(double globalY, {required Rect within}) {
    double? best;
    for (final (_, rect) in _laidOut()) {
      if (!rect.overlaps(within)) continue;
      for (final edge in [rect.top, rect.bottom]) {
        if (best == null || (edge - globalY).abs() < (best - globalY).abs()) {
          best = edge;
        }
      }
    }
    return best;
  }

  void dispose() => picked.dispose();
}

/// Hands the registry to the rows below.
class ScanScope extends InheritedWidget {
  final ScanRegistry registry;
  const ScanScope({super.key, required this.registry, required super.child});
  static ScanRegistry? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScanScope>()?.registry;
  @override
  bool updateShouldNotify(ScanScope old) => old.registry != registry;
}

/// Marks [child] as a row the scanner can pick up.
class ScanRowBox extends StatelessWidget {
  final String id;
  final String section;
  final Widget child;
  const ScanRowBox({
    super.key,
    required this.id,
    required this.section,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final registry = ScanScope.of(context);
    if (registry == null) return child;
    return KeyedSubtree(key: registry.keyFor(id, section), child: child);
  }
}

/// A text that lights to [litColor] at once while its row is picked up and
/// settles back to [color] over [MotionTiming.release] (at once under
/// reduced motion). The text and its style are the row's own, with only the
/// colour animated, so the layout is the one the row had without the
/// scanner.
class ScanLit extends StatelessWidget {
  final String id;
  final String text;
  final TextStyle style;
  final Color color;
  final Color litColor;
  const ScanLit({
    super.key,
    required this.id,
    required this.text,
    required this.style,
    required this.color,
    required this.litColor,
  });

  static final ValueNotifier<String?> _none = ValueNotifier<String?>(null);

  @override
  Widget build(BuildContext context) {
    final registry = ScanScope.of(context);
    final duration = reducedMotionOf(context)
        ? Duration.zero
        : MotionTiming.release;
    return ValueListenableBuilder<String?>(
      valueListenable: registry?.picked ?? _none,
      builder: (_, picked, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: picked == id ? litColor : color),
        // The light is immediate, so the row under a moving finger never
        // lags it; only the settle takes the release time.
        duration: picked == id ? Duration.zero : duration,
        curve: Curves.easeOutCubic,
        builder: (_, c, _) => Text(text, style: style.copyWith(color: c)),
      ),
    );
  }
}

/// Where the scanline sits, in the overlay's coordinates: the finger's y,
/// deepened to the reveal's depth while the reveal runs; the reveal's depth
/// alone with no finger; the glide from [from] to [to] after a release
/// ([release] is that controller's progress over the glide and the fade, or
/// below zero at rest); null at rest.
double? scanLineY({
  required double height,
  required double? finger,
  required double reveal,
  required double release,
  required double? from,
  required double? to,
}) {
  final auto = reveal >= 0 ? height * Curves.easeInOut.transform(reveal) : null;
  if (finger != null) return auto == null ? finger : math.max(auto, finger);
  if (release >= 0 && from != null && to != null) {
    final g = (release / _glideShare).clamp(0.0, 1.0);
    return from + (to - from) * Curves.easeOutCubic.transform(g);
  }
  return auto;
}

/// The line's strength: full under a finger or a reveal, fading over
/// [MotionTiming.release] after the glide; nothing at rest.
double scanLineAlpha({
  required double? finger,
  required double reveal,
  required double release,
}) {
  if (finger != null || reveal >= 0) return 1;
  if (release < 0) return 0;
  if (release <= _glideShare) return 1;
  return (1 - (release - _glideShare) / (1 - _glideShare)).clamp(0.0, 1.0);
}

/// The glide's share of the release controller, which runs the glide and
/// then the fade.
final double _glideShare =
    MotionTiming.glide.inMilliseconds /
    (MotionTiming.glide + MotionTiming.release).inMilliseconds;

/// At most one buzz per [MotionTiming.buzzGap].
class BuzzLimiter {
  DateTime? _last;
  bool allow(DateTime now) {
    final last = _last;
    if (last != null && now.difference(last) < MotionTiming.buzzGap) {
      return false;
    }
    _last = now;
    return true;
  }
}

/// The scanline over the figures. The reveal runs once per change of
/// [revealTrigger]: the line sweeps top to bottom over [MotionTiming.reveal]
/// and the figures below it sit dimmed until it passes. A finger held still
/// on the figures for [MotionTiming.arm] takes the line to itself and the
/// row under it lights; a finger that moves before then is a scroll and
/// shows nothing. A held finger during the reveal takes the reveal over (the
/// deeper of the two). The list under it scrolls as before (a [Listener]
/// joins no gesture arena), and the pick follows the rows as they move under
/// a held finger. One buzz as the finger crosses from one card to another,
/// at most one per [MotionTiming.buzzGap]. On release the line glides to the
/// nearest row edge and fades. A plain tap shows nothing.
class ScanOverlay extends StatefulWidget {
  final Widget child;
  final ScanRegistry registry;
  final ValueListenable<int> revealTrigger;
  const ScanOverlay({
    super.key,
    required this.child,
    required this.registry,
    required this.revealTrigger,
  });
  @override
  State<ScanOverlay> createState() => ScanOverlayState();
}

class ScanOverlayState extends State<ScanOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: MotionTiming.reveal,
  );
  late final AnimationController _release = AnimationController(
    vsync: this,
    duration: MotionTiming.glide + MotionTiming.release,
  );
  final ValueNotifier<double?> _finger = ValueNotifier<double?>(null);
  final GlobalKey _box = GlobalKey();
  final BuzzLimiter _buzz = BuzzLimiter();
  Offset? _downAt;
  int? _pointer;
  Timer? _arm;
  bool _armed = false;
  double? _from;
  double? _to;
  String? _section;

  /// The reveal's progress while it runs, else below zero.
  double get reveal => _reveal.isAnimating ? _reveal.value : -1;

  /// True while a held finger has the line.
  bool get fingerDown => _finger.value != null;

  /// True while the release glide and fade run.
  bool get releasing => _release.isAnimating;

  /// Where the line sits now in the overlay's coordinates, or null at rest.
  double? get lineY => scanLineY(
    height: _renderBox?.size.height ?? 0,
    finger: _finger.value,
    reveal: reveal,
    release: _release.isAnimating ? _release.value : -1,
    from: _from,
    to: _to,
  );

  RenderBox? get _renderBox =>
      _box.currentContext?.findRenderObject() as RenderBox?;

  @override
  void initState() {
    super.initState();
    widget.revealTrigger.addListener(_onReveal);
  }

  @override
  void didUpdateWidget(ScanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revealTrigger != widget.revealTrigger) {
      oldWidget.revealTrigger.removeListener(_onReveal);
      widget.revealTrigger.addListener(_onReveal);
    }
  }

  void _onReveal() {
    if (!mounted || reducedMotionOf(context)) return;
    // A glide in flight ends: the reveal's line is the one line.
    _release.stop();
    _release.value = 0;
    _reveal.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-effect: the reveal and the glide end,
    // and the figures show in full.
    if (reducedMotionOf(context)) {
      if (_reveal.isAnimating) {
        _reveal.stop();
        _reveal.value = 0;
      }
      if (_release.isAnimating) {
        _release.stop();
        _release.value = 0;
      }
    }
  }

  void _down(PointerDownEvent e) {
    // One finger at a time: a second pointer is ignored until the first lifts.
    if (_pointer != null && _pointer != e.pointer) return;
    _pointer = e.pointer;
    _release.stop();
    _release.value = 0;
    _downAt = e.position;
    _armed = false;
    _arm?.cancel();
    _arm = Timer(MotionTiming.arm, () {
      final at = _downAt;
      if (mounted && at != null) _take(at);
    });
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final start = _downAt;
    if (start == null) return;
    if (_armed) {
      _take(e.position);
      return;
    }
    // A finger that leaves the slop before the hold is a scroll: the arm
    // timer is cancelled and this pointer shows nothing.
    if ((e.position - start).distance >= 6) {
      _arm?.cancel();
      _arm = null;
      _downAt = null;
    }
  }

  /// The line to [global], and the row under it picked up.
  void _take(Offset global) {
    _armed = true;
    _downAt = global;
    final box = _renderBox;
    if (box == null) return;
    _finger.value = box.globalToLocal(global).dy.clamp(0.0, box.size.height);
    final row = widget.registry.rowAt(global);
    if (widget.registry.picked.value != row?.id) {
      widget.registry.picked.value = row?.id;
    }
    final section = row?.section;
    if (section != null) {
      if (_section != null &&
          section != _section &&
          _buzz.allow(DateTime.now())) {
        HapticFeedback.selectionClick();
      }
      _section = section;
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _arm?.cancel();
    _arm = null;
    _downAt = null;
    final y = _finger.value;
    _finger.value = null;
    widget.registry.picked.value = null;
    _section = null;
    final armed = _armed;
    _armed = false;
    if (y == null || !armed) return;
    if (reducedMotionOf(context)) return;
    // A release while the reveal runs: the reveal's line is the one line.
    if (_reveal.isAnimating) return;
    final box = _renderBox;
    final edge = box == null
        ? null
        : widget.registry.nearestEdge(
            box.localToGlobal(Offset(0, y)).dy,
            within: box.localToGlobal(Offset.zero) & box.size,
          );
    _from = y;
    _to = edge == null || box == null
        ? y
        : box.globalToLocal(Offset(0, edge)).dy.clamp(0.0, box.size.height);
    _release.forward(from: 0);
  }

  bool _onScroll(ScrollUpdateNotification n) {
    // The rows move under a held finger that is still (an overscroll
    // settling back): the pick follows them.
    final at = _downAt;
    if (at != null && _armed) _take(at);
    return false;
  }

  @override
  void dispose() {
    _arm?.cancel();
    widget.revealTrigger.removeListener(_onReveal);
    _reveal.dispose();
    _release.dispose();
    _finger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScroll,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          child: RepaintBoundary(
            child: CustomPaint(
              key: _box,
              foregroundPainter: ScanOverlayPainter(
                reveal: _reveal,
                release: _release,
                finger: _finger,
                from: () => _from,
                to: () => _to,
              ),
              child: RepaintBoundary(child: widget.child),
            ),
          ),
        ),
      );
}

/// Paints the scanline: a dim wash below it while the reveal runs, the
/// glow line itself and a bead at each end. Repaints on the controllers and
/// the finger, so the figures under it stay in their own layer.
class ScanOverlayPainter extends CustomPainter {
  final Animation<double> reveal;
  final Animation<double> release;
  final ValueListenable<double?> finger;
  final double? Function() from;
  final double? Function() to;
  ScanOverlayPainter({
    required this.reveal,
    required this.release,
    required this.finger,
    required this.from,
    required this.to,
  }) : super(repaint: Listenable.merge([reveal, release, finger]));

  double get _revealValue => reveal.isAnimating ? reveal.value : -1;
  double get _releaseValue => release.isAnimating ? release.value : -1;

  /// Where the line is drawn for [size], or null.
  double? lineY(Size size) => scanLineY(
    height: size.height,
    finger: finger.value,
    reveal: _revealValue,
    release: _releaseValue,
    from: from(),
    to: to(),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final y = lineY(size);
    if (y == null) return;
    final alpha = scanLineAlpha(
      finger: finger.value,
      reveal: _revealValue,
      release: _releaseValue,
    );
    if (_revealValue >= 0) {
      canvas.drawRect(
        Rect.fromLTRB(0, y, size.width, size.height),
        Paint()..color = Instrument.void0.withValues(alpha: 0.78),
      );
    }
    paintGlowLine(canvas, Offset(0, y), Offset(size.width, y), 3, alpha);
    paintGlowDot(canvas, Offset(0, y), 7, 0.9 * alpha);
    paintGlowDot(canvas, Offset(size.width, y), 7, 0.9 * alpha);
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter old) =>
      old.reveal != reveal || old.release != release || old.finger != finger;
}

/// The pool's status dot: lit and breathing when the pool is operational,
/// faint otherwise, with one flare as an update lands ([flare] runs once per
/// update over [MotionTiming.poolFlare]).
class PoolDot extends StatelessWidget {
  final bool up;
  final Animation<double> breath;
  final Animation<double> flare;
  const PoolDot({
    super.key,
    required this.up,
    required this.breath,
    required this.flare,
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size(9, 9),
      painter: PoolDotPainter(up: up, breath: breath, flare: flare),
    ),
  );
}

class PoolDotPainter extends CustomPainter {
  final bool up;
  final Animation<double> breath;
  final Animation<double> flare;
  PoolDotPainter({required this.up, required this.breath, required this.flare})
    : super(repaint: Listenable.merge([breath, flare]));

  /// The flare's progress while it runs, else below zero.
  double get flareValue => flare.isAnimating ? flare.value : -1;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    if (!up) {
      canvas.drawCircle(c, 2.5, Paint()..color = Instrument.faint);
      return;
    }
    final breathA = 0.5 + 0.5 * math.sin(breath.value * 2 * math.pi);
    final f = flareValue >= 0
        ? decay(
            flareValue * MotionTiming.poolFlare.inMilliseconds / 1000,
            MotionTiming.flare.inMilliseconds / 1000,
          )
        : 0.0;
    canvas.drawCircle(c, 2.5, Paint()..color = Instrument.signal);
    paintGlowDot(canvas, c, 4.5 + 2 * f, 0.45 + 0.35 * breathA + 0.6 * f);
  }

  @override
  bool shouldRepaint(covariant PoolDotPainter old) =>
      old.up != up || old.breath != breath || old.flare != flare;
}
