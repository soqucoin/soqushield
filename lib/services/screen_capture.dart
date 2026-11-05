/// Whether the OS may capture this app's screen.
///
/// ── What the two platforms can actually do ──
/// ANDROID: `FLAG_SECURE` genuinely blocks screenshots, screen recording, and
/// casting/mirroring, and blanks the recents preview. Lifting it lifts all of
/// those at once — which is why the setting that drives this is off by default
/// and says so plainly: the live-mirroring channel is how a remote-support
/// scam watches someone open their wallet.
///
/// iOS: there is NO API that blocks a screenshot. An app can be told one was
/// taken, after the fact, and nothing more. The only capture surface iOS lets
/// an app control is the snapshot the system takes for the app switcher, which
/// the scene delegate covers with a blur. So on iOS this toggle governs the
/// app-switcher blur and nothing else, and the Settings copy says that rather
/// than implying a protection iOS cannot provide.
///
/// ── Two inputs, one rule ──
/// The platform is told one thing: capture is allowed when the owner allows
/// it AND no recovery-phrase screen holds a [CaptureShield]. Both inputs live
/// here, so a preference that finishes loading, or changes, while a phrase
/// screen is open cannot lift protection behind it.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenCapture {
  ScreenCapture._();

  static const _channel = MethodChannel('org.soqu.soqushield/capture');

  /// Whether the platform is currently permitting capture, as last applied.
  static bool get allowed => _applied;
  static bool _applied = false;

  /// The owner's choice, as last accepted.
  static bool get ownerAllows => _ownerAllows;
  static bool _ownerAllows = false;

  /// Phrase screens currently on screen.
  static int _shields = 0;
  static bool get shielded => _shields > 0;

  /// Every change to the platform goes through this chain, in order, and
  /// each step sends the rule as it stands when the step runs.
  static Future<bool> _tail = Future.value(true);

  /// Set the owner's choice.
  ///
  /// Returns true when the choice is accepted: the platform confirmed the
  /// rule it implies, or there is no platform side to tell (a host test run,
  /// the web). Returns false when the platform call failed; the owner's
  /// choice is then left as it was, so a caller can keep its preference
  /// matching the window. Never throws.
  ///
  /// While a phrase screen holds a shield the choice is recorded and the
  /// platform stays protected; the choice is applied when the last shield
  /// goes.
  static Future<bool> setAllowed(bool allow) async {
    final before = _ownerAllows;
    _ownerAllows = allow;
    final ok = await _apply();
    if (!ok && _ownerAllows == allow) _ownerAllows = before;
    return ok;
  }

  /// Protect the screen until the returned shield is released, whatever the
  /// owner's setting.
  ///
  /// ⛔ THE RECOVERY PHRASE IS NOT COVERED BY THE TOGGLE. Someone turns
  /// screenshots on to share a balance or a receive QR; that decision must not
  /// silently extend to the one screen whose contents ARE the wallet. A seed
  /// phrase screenshotted once lives in the camera roll, and from there in
  /// whatever cloud backs the camera roll up, forever. So the seed screens
  /// hold a shield while they are on screen.
  static CaptureShield shield() {
    _shields++;
    final shield = CaptureShield._(_apply());
    return shield;
  }

  /// Protect the screen for the duration of [action], then release.
  static Future<T> whileProtected<T>(Future<T> Function() action) async {
    final s = shield();
    await s.applied;
    try {
      return await action();
    } finally {
      await s.release();
    }
  }

  static Future<bool> _apply() {
    final step = _tail.then((_) async {
      final allow = _ownerAllows && _shields == 0;
      try {
        await _channel.invokeMethod<void>('setAllowed', {'allow': allow});
        _applied = allow;
        return true;
      } on MissingPluginException {
        // Host tests and any platform without the channel.
        _applied = allow;
        return true;
      } catch (e) {
        debugPrint('ScreenCapture: setAllowed($allow) failed: $e');
        return false;
      }
    });
    _tail = step;
    return step;
  }

  /// Back to the launch state: protected, no shields. For tests.
  @visibleForTesting
  static void debugReset() {
    _ownerAllows = false;
    _applied = false;
    _shields = 0;
    _tail = Future.value(true);
  }
}

/// Held by a recovery-phrase screen while it is visible.
class CaptureShield {
  CaptureShield._(this.applied);

  /// Completes once the platform has been told to protect.
  final Future<bool> applied;

  bool _released = false;

  /// Hand the owner's setting back. Safe to call more than once.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    ScreenCapture._shields--;
    await ScreenCapture._apply();
  }
}
