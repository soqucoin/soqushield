// SoquShield design language — "Instrument-grade. Quantum-austere."
//
// The shared foundation extracted from the first instrument pilot (the screen signed
// off: "perfect, just brilliant"). This is the system the whole app rolls onto
// — so every screen is one instrument panel in a coherent set, not a one-off.
//
// What lives here:
//   • Instrument  — the palette ("the void + one signal").
//   • kMono       — the telemetry typeface constant.
//   • Instrument widgets — the proven, reusable parts of the pilot:
//       InstrumentStatusBar, InstrumentReadout, InstrumentTrustBadge,
//       InstrumentButton, instrumentDot, InstrumentDivider.
//   • FigureMotion + InstrumentFigureMixin — the FIGURE MOTION CONTRACT. Every
//     hero figure (the NTT butterfly and any future figure) inherits the exact
//     same motion: a resting breath, and on an event a directional wavefront
//     with a sharp leading edge + trailing glow, lit on a single heat ramp.
//     New figures supply their own geometry; the FEEL is shared. (The brief: "if we
//     use any other figures we should take cues from how this NTT works.")
//
// Design dir: design-log/DL-SOQUSHIELD-DESIGN-LANGUAGE.md
//             design-log/DL-INSTRUMENT-ROLLOUT-MAP.md
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';

/// The palette: a deep cold void + ONE electric signal. No warm tones, no
/// decorative gradients — contrast, size and spacing carry the hierarchy.
class Instrument {
  Instrument._();

  // FOUNDRY (2026-07-05, the ruling: "fully on Foundry, one ecosystem skin"):
  // tokens are soqupool's NEW design EXACTLY — soqupool/redesign/foundry.css +
  // FOUNDRY_DESIGN_RATIONALE.md. A pool is a foundry; a wallet pours value.
  //   • Ground = iron, seams = welded hairlines, ZERO border-radius.
  //   • COPPER is the pour: live data + primary action ONLY, never decoration.
  //   • The metals are the asset encoding: SOQ violet ("the new element"),
  //     brass and silver reserved for the pool side.
  //   • Labels are MUTED slate (not accent-coloured) — copper stays scarce.
  static const void0 = Color(0xFF0B0D10); // iron-950 — equipment, not a void
  static const void2 = Color(0xFF141922); // iron-850 — raised panel
  static const signal = Color(0xFFD96F32); // COPPER — the pour (live/action only)
  static const signalDim = Color(0xFF8A4A26); // copper-dim (figure idle tone)
  static const readout = Color(0xFFE9EDF2); // text-hi (data/values)
  static const label = Color(0xFFAAB4C0); // text-mid (keys, labels)
  static const faint = Color(0xFF717D8B); // text-lo (tertiary)
  static const line = Color(0xFF232C38); // seam hairline
  static const lineHi = Color(0xFF313D4C); // seam-hi — button borders, hover seams
  static const leadEdge = Color(0xFFF0A36E); // copper-hot — a wavefront's crest

  // The SOQ metal — a cold quantum-violet, foundry --soq ("the new element");
  // the SOQ asset mark and the key nodes of the custody line ride it.
  static const soq = Color(0xFF8E7CF0);

  // Reject / failure — warm-cold red.
  static const threat = Color(0xFFD96A5B); // foundry --down (desaturated, encoding only)

  /// soqupool's `.label` class, ported — the treatment that makes its section
  /// markers read finished: small, UPPERCASE (caller supplies caps), tracking
  /// locked to .16em OF THE SIZE (not a magic number), and ACCENT-coloured so
  /// the label lifts off the canvas instead of blending into it. Default tone
  /// is the label accent; pass [color] to re-purpose (threat red on a failed
  /// state, label-taupe for quiet secondary chips).
  static TextStyle eyebrow({
    double size = 11,
    Color color = label, // foundry: labels are muted slate; copper = live/action only
    FontWeight weight = FontWeight.w500,
  }) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontFamily: kLabel,
        letterSpacing: size * 0.16,
        fontWeight: weight,
      );
}

/// Data typeface — every number the app reports (foundry --font-mono).
const String kMono = 'MartianMono';

/// Display/body typeface — foundry --font-display. Set as the app default in
/// app_theme so most Text inherits it; named here for explicit uses.
const String kSans = 'Archivo';


/// Small-label typeface — the iOS system font (SF Pro). iOS hints its own font
/// razor-sharp at any point size, where a bundled font (Plex Mono) aliases /
/// stairsteps at ~10px label sizes. Use for the small uppercase eyebrow labels
/// (SECTION HEADERS, telemetry, trust chips), which lean on tracking, not a mono
/// grid, for their "technical" feel. Android falls back to Roboto (its own
/// system font) automatically. Data columns keep kMono for digit alignment.
const String kLabel = '.SF Pro Text';

// ─────────────────────────────────────────────────────────────────────────────
// Instrument widgets — the proven, reusable parts of the first instrument pilot.
// ─────────────────────────────────────────────────────────────────────────────

/// A small glowing status dot (live/active indicator).
Widget instrumentDot(Color c, {double size = 5}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );

/// A hairline divider — the austere language uses these, never cards.
class InstrumentDivider extends StatelessWidget {
  final double inset;
  const InstrumentDivider({super.key, this.inset = 0});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Container(height: 0.6, color: Instrument.line),
      );
}

/// Top status line: a live dot + a mono telemetry string. Left-aligned so the
/// shell's network badge owns the right corner.
class InstrumentStatusBar extends StatelessWidget {
  final String text;
  final Color dotColor;
  final double inset;
  const InstrumentStatusBar({
    super.key,
    required this.text,
    this.dotColor = Instrument.signal,
    this.inset = 22,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Row(
          children: [
            instrumentDot(dotColor),
            const SizedBox(width: 8),
            // The telemetry string stays whole on a narrow phone or a large
            // system text size: it scales down rather than clipping.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(text, style: Instrument.eyebrow(size: 10.5)),
              ),
            ),
          ],
        ),
      );
}

/// The instrument readout — a mono label over a big, exact numeral + unit. The
/// hero number on every screen (balance, hashrate, supply, rate…). The value is
/// pre-formatted by the caller so this stays a pure presentation widget.
class InstrumentReadout extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final double valueSize;
  final Color valueColor;
  final Color unitColor;
  const InstrumentReadout({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.valueSize = 62,
    this.valueColor = Instrument.readout,
    this.unitColor = Instrument.signal,
  });
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: Instrument.eyebrow()),
          const SizedBox(height: 14),
          // A value wider than the panel (a seven-figure balance on a small
          // phone, a large system text size) scales down to fit rather than
          // overflowing: the readout always shows the whole number.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: TextStyle(
                          color: valueColor,
                          fontSize: valueSize,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1.5,
                          height: 1.0)),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(unit,
                        style: TextStyle(
                            color: unitColor.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2.0)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

/// A quiet, recurring reassurance chip — "YOU HOLD THE KEYS", "QUANTUM-SIGNED",
/// "1:1 RESERVED". Confidence, never a warning.
class InstrumentTrustBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const InstrumentTrustBadge({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: Instrument.signalDim),
          const SizedBox(width: 7),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, style: Instrument.eyebrow(size: 10)),
            ),
          ),
        ],
      );
}

/// Instrument bezel button with a real press state (scale + brighten on
/// tap-down), and a 1px resting edge so it reads as tappable before touch.
/// [primary] gets the signal fill/border; secondary is a raised void surface
/// with a teal-whisper edge. [enabled] false is the "not yet" state (a seam
/// hairline, tertiary text, no fill, no press), clearly apart from the lit
/// slab it becomes the moment it can act.
class InstrumentButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final bool enabled;
  final VoidCallback onTap;
  const InstrumentButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
    this.enabled = true,
  });
  @override
  State<InstrumentButton> createState() => _InstrumentButtonState();
}

class _InstrumentButtonState extends State<InstrumentButton> {
  bool _down = false;
  void _set(bool v) => setState(() => _down = v);

  @override
  void didUpdateWidget(InstrumentButton old) {
    super.didUpdateWidget(old);
    // Disabled under a finger, the button gets no tap-up: drop the press.
    if (!widget.enabled) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    // foundry.css .btn / .btn-pour, exactly: primary = a SOLID copper slab
    // with iron-ink text (hover/press -> copper-hot); secondary = transparent
    // with a seam-hi border and text-hi. Uppercase mono, 0.1em tracking,
    // square. (The old tinted-outline ghost read retro.)
    final primary = widget.primary;
    final enabled = widget.enabled;
    final down = _down && enabled;
    final fill = !enabled
        ? Colors.transparent
        : primary
            ? (down ? Instrument.leadEdge : Instrument.signal)
            : Colors.transparent;
    final edge = !enabled
        ? Instrument.line
        : primary
            ? (down ? Instrument.leadEdge : Instrument.signal)
            : (down ? Instrument.faint : Instrument.lineHi);
    final fg = !enabled
        ? Instrument.faint
        : primary
            ? const Color(0xFF16100A)
            : Instrument.readout;
    return GestureDetector(
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: down ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 54,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: edge, width: 1),
          ),
          child: Center(
            // The label scales down on a narrow button or a large system
            // text size rather than clipping.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 15, color: fg),
                    const SizedBox(width: 10),
                    Text(widget.label.toUpperCase(),
                        style: TextStyle(
                            color: fg,
                            fontSize: 13,
                            fontFamily: kMono,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 13 * 0.1)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The primary button's in-flight state: a spinner and a mono eyebrow in the
/// dimmed copper frame (the create screen's GENERATING KEYS moment).
class InstrumentBusyButton extends StatelessWidget {
  final String label;
  const InstrumentBusyButton({super.key, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: Instrument.signal.withValues(alpha: 0.10),
          border: Border.all(
              color: Instrument.signal.withValues(alpha: 0.5), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Instrument.signal),
              ),
              const SizedBox(width: 12),
              Text(label, style: Instrument.eyebrow(size: 12)),
            ],
          ),
        ),
      );
}

/// Where a system share sheet anchors: the global rectangle of the control
/// that raised it. On an iPad the sheet is a popover and the plugin refuses
/// to open one without an anchor; elsewhere the anchor is ignored. Null when
/// the control has no size yet.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// A small secondary action ("COPY ALL", "PASTE FROM CLIPBOARD"): an icon and
/// an eyebrow in a hairline box, for the actions that must not compete with
/// the screen's one primary button.
class InstrumentActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const InstrumentActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Instrument.lineHi, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Instrument.label),
              const SizedBox(width: 8),
              // The label scales down when the chip shares a narrow row.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label.toUpperCase(),
                      style: Instrument.eyebrow(size: 10.5)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The top bar of a pushed or onboarding screen: the back arrow and the
/// screen's eyebrow, at the geometry Receive and Settings use. [onBack] null
/// hides the arrow and keeps the eyebrow on the content inset.
class InstrumentTopBar extends StatelessWidget {
  final String label;
  final VoidCallback? onBack;
  const InstrumentTopBar({super.key, required this.label, this.onBack});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 22, 2),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Instrument.label, size: 20),
                  onPressed: onBack,
                ),
                const SizedBox(width: 2),
              ] else
                const SizedBox(width: 14),
              Text(label, style: Instrument.eyebrow(size: 11)),
            ],
          ),
        ),
      );
}

class FigureMotion {
  final double breath; // 0..1 ambient loop
  final double pulse; // 0..1 sweep progress, or < 0 when idle
  final int dir; // +1 outward (L→R), -1 inward (R→L)
  final double left;
  final double right;
  final Color accent; // the lit tone (idle nodes ramp from accentDim → accent)
  final Color accentDim;

  static const double lead = 26.0; // sharp leading edge width
  static const double trail = 92.0; // soft trailing glow length

  late final double breathA;
  late final double _frontX;
  late final double _endFade;

  FigureMotion({
    required this.breath,
    required this.pulse,
    required this.dir,
    required this.left,
    required this.right,
    this.accent = Instrument.signal,
    this.accentDim = Instrument.signalDim,
  }) {
    breathA = 0.5 + 0.5 * math.sin(breath * 2 * math.pi);
    final travel = (right - left) + lead + trail * 1.7;
    _frontX = pulse < 0
        ? double.nan
        : (dir > 0 ? left - lead + pulse * travel : right + lead - pulse * travel);
    _endFade = pulse < 0
        ? 0.0
        : (pulse < 0.75 ? 1.0 : (1 - (pulse - 0.75) / 0.25).clamp(0.0, 1.0));
  }

  bool get active => pulse >= 0;
  double get frontX => _frontX;

  /// 0..1, fades to 0 over the last quarter of the sweep — multiply a figure's
  /// leading-edge glow line by this so it dies out cleanly like the butterfly's.
  double get endFade => _endFade;

  /// Glow intensity 0..1 at scene-x [x]: a sharp quadratic leading rise ahead of
  /// the front, an exponential trailing glow behind it, faded out at the end.
  double wavefront(double x) {
    if (pulse < 0) return 0.0;
    final passed = dir > 0 ? _frontX - x : x - _frontX; // >0 = already swept
    if (passed < -lead) return 0.0; // ahead of the front
    final base = passed < 0
        ? (1 + passed / lead) * (1 + passed / lead) // sharp leading rise
        : math.exp(-passed / trail); // trailing glow
    return base * _endFade;
  }

  /// The single heat ramp: idle teal → cyan → near-white at the crest. [a] is the
  /// base alpha; [extra] adds glow-proportional alpha (brighter where it's lit).
  Color heat(double g, double a, {double extra = 0.0}) {
    final c = g > 0.62
        ? Color.lerp(accent, Instrument.leadEdge, (g - 0.62) / 0.38)!
        : Color.lerp(accentDim, accent, (g / 0.62).clamp(0.0, 1.0))!;
    return c.withValues(alpha: (a + g * extra).clamp(0.0, 1.0));
  }
}

/// The shared animation rig for a figure screen: a 6s ambient breath, a 1200ms
/// event pulse, and a direction. Mix into a `State` that also has
/// `TickerProviderStateMixin`; call `initFigure()` in `initState` and
/// `disposeFigure()` in `dispose`. Fire an event with `fireFigure(+1|-1)`.
/// Under the platform's reduced-motion setting the breath holds at its peak
/// and an event shows its end state at once (the haptic still confirms it).
mixin InstrumentFigureMixin<T extends StatefulWidget> on State<T>
    implements TickerProvider {
  late final AnimationController breath;
  late final AnimationController pulse;
  int figureDir = 1;

  /// The platform's reduced-motion setting, read from the media query each
  /// time the dependencies change.
  bool reducedMotion = false;

  void initFigure() {
    breath = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  }

  void disposeFigure() {
    breath.dispose();
    pulse.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = reducedMotionOf(context);
    if (reduced == reducedMotion) return;
    reducedMotion = reduced;
    if (reduced) {
      breath.stop();
      breath.value = 0.25; // the peak of the breath: fully lit, still
      pulse.stop();
      pulse.value = 0; // an event in flight shows its end state, and repaints
    } else {
      breath.repeat();
    }
  }

  /// The signature moment: fire a wavefront in [dir] (+1 outward / -1 inward).
  /// [haptic] adds the mechanical confirmation buzz (off for ambient sweeps like
  /// a screen "coming online"). Pair with a telemetry insert in the screen.
  void fireFigure(int dir, {bool haptic = true}) {
    if (haptic) HapticFeedback.mediumImpact();
    figureDir = dir;
    if (reducedMotion) return; // the rest state is the end state
    pulse.forward(from: 0);
  }

  /// Pulse progress for a painter: the live value while animating, else -1 (idle).
  double get pulseValue => pulse.isAnimating ? pulse.value : -1.0;

  /// Merge of both controllers for a single `AnimatedBuilder`.
  Listenable get figureListenable => Listenable.merge([breath, pulse]);
}
