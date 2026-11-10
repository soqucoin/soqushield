// Lock (device re-auth). The Soqucoin mark rests in points: the keys exist,
// held, locked. A band of light scans it while the device checks the
// credential. Auth + SB-5 anti-brute-force backoff preserved verbatim from
// LockScreen.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/point_scene.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/auth_service.dart' show AuthOutcome;

class LockPilotScreen extends ConsumerStatefulWidget {
  const LockPilotScreen({super.key});
  @override
  ConsumerState<LockPilotScreen> createState() => _LockPilotScreenState();
}

class _LockPilotScreenState extends ConsumerState<LockPilotScreen> {
  // Fewer points than the splash: the figure is smaller here.
  final PointField _mark = PointField.mark(count: 1150);
  bool _authenticating = false;
  bool _failed = false;
  bool _noDeviceAuth = false;
  // The OS could not run the check right now (its own lockout, a request
  // still pending). A credential exists; the owner waits and asks again.
  bool _checkPaused = false;
  Timer? _lockoutTicker;
  // A prompt that has not answered within a few seconds shows a tap to
  // unlock, so a request lost in the return transition never leaves the
  // screen without a way forward.
  bool _slow = false;
  Timer? _slowTimer;
  // Each credential request carries its number; a result that arrives for an
  // earlier number (a request dropped by a tap to unlock) is ignored.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptWhenActive());
  }

  /// Resumed, or unknown: the first frames of a launch report no state yet.
  bool get _resumedNow {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// The automatic prompt waits until the app is active and has stayed
  /// active through a short settle. A lock raised on the return from another
  /// app arrives while the system is still finishing the transition, and a
  /// biometric request made in that window can fail or never answer. Past
  /// ten seconds without a settled active state there is no automatic
  /// prompt; the Unlock button asks on a tap.
  Future<void> _promptWhenActive() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (!_resumedNow) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      if (!_resumedNow) continue;
      debugPrint('LOCK: prompting, lifecycle '
          '${WidgetsBinding.instance.lifecycleState}');
      await _authenticate();
      return;
    }
    debugPrint('LOCK: no automatic prompt, lifecycle '
        '${WidgetsBinding.instance.lifecycleState}');
  }

  /// A tap while a prompt is pending: the pending request is dropped (the
  /// platform is asked to stop it where it can, and its result is ignored by
  /// the attempt number) and a fresh one is raised.
  Future<void> _retry() async {
    _slowTimer?.cancel();
    debugPrint('LOCK: retry by tap');
    // Not awaited: the platform call is a no-op on iOS and must never hold
    // the fresh request back.
    unawaited(ref.read(authServiceProvider).cancelAuthentication());
    setState(() {
      _authenticating = false;
      _slow = false;
    });
    await _authenticate();
  }

  @override
  void dispose() {
    _lockoutTicker?.cancel();
    _slowTimer?.cancel();
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
      _checkPaused = false;
      _slow = false;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _authenticating) setState(() => _slow = true);
    });
    final attempt = ++_attempt;
    debugPrint('LOCK: authenticate start, attempt $attempt');

    final service = ref.read(authServiceProvider);

    // bead agx: with no screen lock enrolled, authenticate() can NEVER
    // succeed (Android ERROR_NOT_AVAILABLE / iOS passcodeNotSet). Don't
    // burn a failed attempt on it — show enrollment guidance instead.
    if (!await service.isDeviceAuthAvailable()) {
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _authenticating = false;
        _noDeviceAuth = true;
      });
      return;
    }

    final outcome = await session.whileSystemUi(service.authenticate);
    if (attempt != _attempt) {
      debugPrint('LOCK: stale result $outcome for attempt $attempt ignored');
      return;
    }
    _slowTimer?.cancel();
    debugPrint('LOCK: authenticate result $outcome');
    if (!mounted) return;

    switch (outcome) {
      case AuthOutcome.success:
        await session.resetFailedAttempts();
        HapticFeedback.mediumImpact();
        ref.read(authProvider.notifier).unlock();
        if (mounted) context.go('/');

      case AuthOutcome.unavailable:
        // The OS declined to run the check right now — its own biometric
        // lockout, or a request still pending. That is not the owner getting
        // it wrong, so it burns no attempt: stacking this app's backoff on
        // the platform's would make an owner wait twice for one mistake, and
        // the second wait cannot be cleared by presenting the right finger.
        // A credential exists, so the guidance is to wait and try again.
        setState(() {
          _authenticating = false;
          _checkPaused = true;
        });

      case AuthOutcome.noCredential:
        // Nothing to check against: the enrollment guidance.
        setState(() {
          _authenticating = false;
          _noDeviceAuth = true;
        });

      case AuthOutcome.failed:
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
              SizedBox(
                height: 184,
                width: double.infinity,
                child: PointScene(field: _mark, scan: _authenticating),
              ),
              const SizedBox(height: 24),
              if (name != null) ...[
                Text('Welcome back',
                    textAlign: TextAlign.center,
                    style: Instrument.heading(size: 22)),
                const SizedBox(height: 8),
                Text(name,
                    style: TextStyle(
                        color: Instrument.label,
                        fontSize: 13,
                        fontFamily: kMono)),
              ] else
                const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: InstrumentWordmark(size: 18)),
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
          if (_slow) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 220,
              child: InstrumentButton(
                key: const Key('lock-retry'),
                label: 'Tap to unlock',
                icon: Icons.fingerprint_rounded,
                primary: true,
                onTap: _retry,
              ),
            ),
          ],
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
    if (_checkPaused) {
      return Column(
        children: [
          Icon(Icons.lock_clock_rounded,
              size: 26, color: const Color(0xFFD9A441)),
          const SizedBox(height: 14),
          Text('CHECK PAUSED',
              style: Instrument.eyebrow(
                  size: 11, color: const Color(0xFFD9A441))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Your device paused its credential check. Wait a moment, '
              'then try again. If it stays paused, unlock your device with '
              'its PIN, pattern or passcode first. Your wallet is intact.',
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
