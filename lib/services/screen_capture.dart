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
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ScreenCapture {
  ScreenCapture._();

  static const _channel = MethodChannel('org.soqu.soqushield/capture');

  /// Whether the platform is currently permitting capture, as last set.
  static bool get allowed => _allowed;
  static bool _allowed = false;

  /// Permit or forbid capture.
  ///
  /// Never throws: a platform that does not implement the channel (a host
  /// test run, a future platform) leaves the app working. It returns false in
  /// that case, so a caller can tell "the platform says no" from "the platform
  /// was not listening" if it ever needs to.
  static Future<bool> setAllowed(bool allow) async {
    try {
      await _channel.invokeMethod<void>('setAllowed', {'allow': allow});
      _allowed = allow;
      return true;
    } on MissingPluginException {
      // Host tests and any platform without the channel.
      _allowed = allow;
      return false;
    } catch (e) {
      debugPrint('ScreenCapture: setAllowed($allow) failed: $e');
      return false;
    }
  }

  /// Protect the screen for the duration of [action], whatever the owner's
  /// setting, then put the setting back.
  ///
  /// ⛔ THE RECOVERY PHRASE IS NOT COVERED BY THE TOGGLE. Someone turns
  /// screenshots on to share a balance or a receive QR; that decision must not
  /// silently extend to the one screen whose contents ARE the wallet. A seed
  /// phrase screenshotted once lives in the camera roll, and from there in
  /// whatever cloud backs the camera roll up, forever. So the seed screens
  /// re-assert protection while they are on screen and restore the owner's
  /// setting when they leave.
  static Future<T> whileProtected<T>(Future<T> Function() action) async {
    final restore = _allowed;
    if (restore) await setAllowed(false);
    try {
      return await action();
    } finally {
      if (restore) await setAllowed(true);
    }
  }
}
