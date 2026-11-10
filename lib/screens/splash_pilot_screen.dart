// Splash. The Soqucoin mark assembles out of scattered points, as on the
// site's scene, the wordmark follows it in, and the screen routes by auth
// status. Under reduced motion it is one still frame: the mark whole, the
// text in place.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/instrument.dart';
import '../theme/point_scene.dart';
import '../theme/motion.dart';
import '../providers/auth_provider.dart';

class SplashPilotScreen extends ConsumerStatefulWidget {
  const SplashPilotScreen({super.key});
  @override
  ConsumerState<SplashPilotScreen> createState() => _SplashPilotScreenState();
}

class _SplashPilotScreenState extends ConsumerState<SplashPilotScreen>
    with SingleTickerProviderStateMixin {
  bool _navigated = false;

  // Seconds since the splash began: the one clock the mark and the text read.
  final ValueNotifier<double> _clock = ValueNotifier(0);
  // How far the mark's points are still thrown from their places.
  final ValueNotifier<double> _scatter = ValueNotifier(
    PointScenePainter.gatherScatter(0),
  );
  final PointField _field = PointField.mark();
  late final Ticker _ticker;
  double _clockBase = 0;
  bool _still = false;

  // Past every entrance, for the still frame.
  static const double _settled = 60;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
    _ticker = createTicker((elapsed) {
      final t = _clockBase + elapsed.inMicroseconds / 1e6;
      _scatter.value = PointScenePainter.gatherScatter(t);
      _clock.value = t;
    });
    Future.delayed(const Duration(milliseconds: 2500), _navigate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reducedMotionOf(context);
    if (still) {
      _ticker.stop();
      _clock.value = _settled;
      // The still frame is the gathered mark. Should motion come back, the
      // first frame painted before the ticker runs again must be it too.
      _scatter.value = 0;
    } else if (!_ticker.isActive) {
      // First run, or motion allowed again: carry on from where the clock is.
      _clockBase = _still ? PointScenePainter.assembleSeconds : _clock.value;
      _ticker.start();
    }
    _still = still;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _scatter.dispose();
    super.dispose();
  }

  // ── routing preserved verbatim from SplashScreen ──
  void _navigate() {
    if (_navigated || !mounted) return;
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    final authState = ref.read(authProvider);
    authState.when(
      data: (status) => _goToRoute(status),
      loading: () {
        // Auth still loading — listen until it resolves
        ref.listenManual(authProvider, (_, next) {
          next.whenData((status) {
            if (!_navigated && mounted) _goToRoute(status);
          });
        });
        // Hard timeout fallback — never stay stuck on splash. If auth resolved
        // in the meantime, use that; otherwise fall back to the LOCK screen, not
        // onboarding: a wallet-holder must never be shown "create new wallet"
        // just because the auth check was slow. A genuine first-launch user who
        // somehow hits this can relaunch (the check resolves definitively).
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (_navigated || !mounted) return;
          final resolved = ref.read(authProvider).asData?.value;
          _goToRoute(resolved ?? AuthStatus.locked);
        });
      },
      error: (e, st) {
        // Auth check failed (e.g. Keychain briefly unavailable). Do NOT route to
        // onboarding — that risks overwriting an existing wallet. Default to the
        // lock screen, which is safe whether or not a wallet exists.
        debugPrint('Auth provider error: $e');
        _goToRoute(AuthStatus.locked);
      },
    );
  }

  void _goToRoute(AuthStatus status) {
    if (_navigated || !mounted) return;
    if (status == AuthStatus.loading) return;
    _navigated = true;
    switch (status) {
      case AuthStatus.noAccount:
        context.go('/welcome');
      case AuthStatus.locked:
        context.go('/lock');
      case AuthStatus.authenticated:
        context.go('/');
      case AuthStatus.loading:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final pad = MediaQuery.paddingOf(context);
          // Each line gets a box sized from the text scale and fits itself to
          // it, so the heights below are exact at any text size.
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final wordH = 19 * 1.35 * scale;
          final tagH = 10 * 1.6 * scale;
          final footH = 9.5 * 1.6 * scale;
          const lineGap = 12.0;
          final textH = wordH + lineGap + tagH;
          final footTop = h - pad.bottom - 28 - footH;
          // The mark sits a little above the middle, the text under it. On a
          // short screen (a phone on its side, a large text size) the mark
          // shrinks and moves up, so the text always clears the footer.
          final wanted = math.min(math.min(w * 0.66, h * 0.36), 320.0);
          final gap = math.max(20.0, wanted * 0.14);
          final groupEnd =
              footTop - 16; // where the text under the mark must end
          final side = math.max(
            40.0,
            math.min(wanted, groupEnd - textH - gap - pad.top),
          );
          final lowest = groupEnd - textH - gap - side / 2;
          final cy = math.max(pad.top + side / 2, math.min(h * 0.43, lowest));
          final mark = Rect.fromCenter(
            center: Offset(w / 2, cy),
            width: side,
            height: side,
          );
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: PointScenePainter(
                      field: _field,
                      clock: _clock,
                      scatter: _scatter,
                      frame: mark,
                      still: _still,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: mark.bottom + gap,
                child: Column(
                  children: [
                    _Entrance(
                      clock: _clock,
                      from: 1.0,
                      height: wordH,
                      child: const InstrumentWordmark(),
                    ),
                    const SizedBox(height: lineGap),
                    _Entrance(
                      clock: _clock,
                      from: 1.25,
                      height: tagH,
                      child: Text(
                        'SELF-CUSTODIAL · POST-QUANTUM',
                        style: Instrument.eyebrow(size: 10),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: footTop,
                child: _Entrance(
                  clock: _clock,
                  from: 1.5,
                  height: footH,
                  rise: 0,
                  child: Text(
                    'ML-DSA-44 · FIPS 204',
                    style: Instrument.eyebrow(
                      size: 9.5,
                      color: Instrument.faint,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A line of the splash coming in: it fades up over 0.6 s from [from]
/// seconds on the splash clock, rising [rise] points as it does. The line
/// sits in a box [height] tall and scales down to fit it, and the screen's
/// width, on a narrow screen or at a large text size.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.clock,
    required this.from,
    required this.height,
    required this.child,
    this.rise = 6,
  });
  final ValueListenable<double> clock;
  final double from;
  final double height;
  final double rise;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final line = SizedBox(
      height: height,
      child: Center(
        child: FittedBox(fit: BoxFit.scaleDown, child: child),
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: clock,
      child: line,
      builder: (_, t, line) {
        final e = Curves.easeOutCubic.transform(((t - from) / 0.6).clamp(0, 1));
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, rise * (1 - e)),
            child: line,
          ),
        );
      },
    );
  }
}
