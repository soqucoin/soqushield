// PILOT — Lock (biometric re-auth) on the instrument language.
//
// Wave 3. Figure: the CRYSTALLIZING LATTICE, settled — your keys exist, held,
// locked. Auth + SB-5 anti-brute-force backoff preserved verbatim from
// LockScreen. Old at /lock-classic.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/figures.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';

class LockPilotScreen extends ConsumerStatefulWidget {
  const LockPilotScreen({super.key});
  @override
  ConsumerState<LockPilotScreen> createState() => _LockPilotScreenState();
}

class _LockPilotScreenState extends ConsumerState<LockPilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  bool _authenticating = false;
  bool _failed = false;
  bool _noDeviceAuth = false;
  Timer? _lockoutTicker;

  @override
  void initState() {
    super.initState();
    initFigure();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    disposeFigure();
    super.dispose();
  }

  // ── preserved verbatim from LockScreen._authenticate (SB-5) ──
  Future<void> _authenticate() async {
    if (_authenticating) return;

    final session = ref.read(sessionProvider.notifier);
    if (session.isInLockout) {
      setState(() => _failed = true);
      _startLockoutTicker();
      return;
    }

    setState(() {
      _authenticating = true;
      _failed = false;
      _noDeviceAuth = false;
    });

    final service = ref.read(authServiceProvider);

    // bead agx: with no screen lock enrolled, authenticate() can NEVER
    // succeed (Android ERROR_NOT_AVAILABLE / iOS passcodeNotSet). Don't
    // burn a failed attempt on it — show enrollment guidance instead.
    if (!await service.isDeviceAuthAvailable()) {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _noDeviceAuth = true;
      });
      return;
    }

    final success =
        await session.whileSystemUi(service.authenticateWithBiometrics);
    if (!mounted) return;

    if (success) {
      await session.resetFailedAttempts();
      HapticFeedback.mediumImpact();
      ref.read(authProvider.notifier).unlock();
      if (mounted) context.go('/');
    } else {
      await session.recordFailedAttempt();
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _failed = true;
      });
      if (session.isInLockout) _startLockoutTicker();
    }
  }

  void _startLockoutTicker() {
    _lockoutTicker?.cancel();
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !ref.read(sessionProvider.notifier).isInLockout) {
        t.cancel();
        if (mounted) setState(() {});
        return;
      }
      setState(() {});
    });
  }

  void _debugBypass() {
    if (!kDebugMode) return;
    ref.read(authProvider.notifier).unlock();
    context.go('/');
  }

  String _fmt(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.read(sessionProvider.notifier);
    final inLockout = session.isInLockout;
    final remaining = session.remainingLockout;
    final name = ref.watch(accountNameProvider).asData?.value;

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: figureListenable,
                  builder: (_, _) => SizedBox(
                    height: 168,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: CrystallizingLatticePainter(
                        breath: breath.value,
                        pulse: pulseValue,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(name != null ? 'Welcome back' : 'SOQUSHIELD',
                  style: TextStyle(
                      color: Instrument.readout,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      letterSpacing: name != null ? 0.5 : 4)),
              if (name != null) ...[
                const SizedBox(height: 6),
                Text(name,
                    style: TextStyle(
                        color: Instrument.label,
                        fontSize: 13,
                        fontFamily: kMono)),
              ],
              const Spacer(flex: 3),
              _status(inLockout, remaining),
              const Spacer(flex: 2),
              if (kDebugMode) ...[
                TextButton(
                  onPressed: _debugBypass,
                  child: Text('debug bypass',
                      style: TextStyle(
                          color: Instrument.faint,
                          fontSize: 11,
                          fontFamily: kMono)),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _status(bool inLockout, Duration remaining) {
    if (_authenticating) {
      return Column(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Instrument.signalDim),
          ),
          const SizedBox(height: 16),
          Text('AUTHENTICATING', style: Instrument.eyebrow(size: 11)),
        ],
      );
    }
    if (_noDeviceAuth) {
      // bead agx: no screen lock enrolled — guide instead of failing.
      return Column(
        children: [
          Icon(Icons.phonelink_lock_rounded,
              size: 26, color: const Color(0xFFD9A441)),
          const SizedBox(height: 14),
          Text('NO SCREEN LOCK SET',
              style: Instrument.eyebrow(
                  size: 11, color: const Color(0xFFD9A441))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'SoquShield uses your device screen lock to protect your '
              'wallet. Set a PIN, pattern or passcode in your device '
              'settings, then return here. Your wallet is intact.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Instrument.faint, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: 220,
            child: InstrumentButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              primary: true,
              onTap: _authenticate,
            ),
          ),
        ],
      );
    }
    if (inLockout) {
      return Column(
        children: [
          Icon(Icons.lock_clock_rounded,
              size: 26, color: const Color(0xFFD9A441)),
          const SizedBox(height: 14),
          Text('TOO MANY ATTEMPTS',
              style: Instrument.eyebrow(
                  size: 11, color: const Color(0xFFD9A441))),
          const SizedBox(height: 8),
          Text('Try again in ${_fmt(remaining)}',
              style: TextStyle(color: Instrument.faint, fontSize: 12)),
        ],
      );
    }
    // failed (not locked out) or idle → offer unlock
    return Column(
      children: [
        if (_failed) ...[
          Text('AUTHENTICATION FAILED',
              style: Instrument.eyebrow(
                  size: 11, color: const Color(0xFFD96A6A))),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: 220,
          child: InstrumentButton(
            label: 'Unlock',
            icon: Icons.fingerprint_rounded,
            primary: true,
            onTap: _authenticate,
          ),
        ),
      ],
    );
  }
}
