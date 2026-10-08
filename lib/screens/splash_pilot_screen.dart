// PILOT — Splash on the instrument language. The lattice crystallises as the
// app comes online, then routes by auth status (logic preserved verbatim from
// SplashScreen). Old at /splash-classic.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/instrument.dart';
import '../theme/figures.dart';
import '../providers/auth_provider.dart';

class SplashPilotScreen extends ConsumerStatefulWidget {
  const SplashPilotScreen({super.key});
  @override
  ConsumerState<SplashPilotScreen> createState() => _SplashPilotScreenState();
}

class _SplashPilotScreenState extends ConsumerState<SplashPilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  bool _navigated = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    initFigure();
    if (!kIsWeb) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    }
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    // Crystallise on launch, through the guarded start: under reduced motion
    // the first dependency read ends the sweep before the first frame.
    fireFigure(1, haptic: false);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _fadeCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 2500), _navigate);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    disposeFigure();
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
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: figureListenable,
                builder: (_, _) => SizedBox(
                  height: 188,
                  width: 280,
                  child: CustomPaint(
                    painter: CrystallizingLatticePainter(
                      breath: breath.value,
                      pulse: pulseValue,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _fadeAnim,
              child: Text('SOQUSHIELD',
                  style: TextStyle(
                      color: Instrument.readout,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 6)),
            ),
          ],
        ),
      ),
    );
  }
}
