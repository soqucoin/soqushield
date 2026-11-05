import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart' show kSharedSecureStorage;

/// How an authentication attempt ended.
///
/// The distinction that matters is [unavailable]: the OS refusing to run the
/// check AT ALL is not the user getting it wrong, and must not be counted as
/// a failed attempt. The platform's own biometric lockout arrives this way —
/// counting it would stack the app's backoff on top of the OS's, punishing
/// someone twice for one mistake and pushing an owner toward a 30-minute wait
/// they cannot clear by presenting the right finger.
enum AuthOutcome {
  /// The user authenticated.
  success,

  /// The check ran and did not succeed — a wrong finger/face, or the user
  /// dismissing the prompt. local_auth reports both as a plain `false`, so
  /// they cannot be told apart here.
  failed,

  /// The check could not run: the OS biometric API is locked out, no
  /// credential is enrolled, or the platform refused. Never a failed attempt.
  unavailable,
}

/// Manages local account persistence and biometric authentication.
/// All data stays on-device in encrypted storage.
class AuthService {
  static const _keyAccountName = 'soq_account_name';
  static const _keyCreatedAt = 'soq_account_created';
  static const _keyBiometricEnabled = 'soq_biometric_enabled';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  AuthService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? kSharedSecureStorage,
        _localAuth = localAuth ?? LocalAuthentication();

  // ── Account Management ──

  /// Check if a local account exists.
  Future<bool> hasAccount() async {
    final name = await _storage.read(key: _keyAccountName);
    return name != null && name.isNotEmpty;
  }

  /// Create a new local account.
  Future<void> createAccount(String name) async {
    await _storage.write(key: _keyAccountName, value: name.trim());
    await _storage.write(
      key: _keyCreatedAt,
      value: DateTime.now().toIso8601String(),
    );
    // Enable biometrics by default if available
    final available = await isBiometricAvailable();
    await _storage.write(
      key: _keyBiometricEnabled,
      value: available.toString(),
    );
  }

  /// Get the stored account name.
  Future<String?> getAccountName() async {
    return _storage.read(key: _keyAccountName);
  }

  // ── Biometrics ──

  /// Check if device has enrolled biometrics (face or fingerprint).
  ///
  /// Returns false if:
  ///   - Running on web
  ///   - Device has no biometric hardware
  ///   - Hardware exists but no face/fingerprint is enrolled (simulator)
  ///
  /// This is stricter than `isDeviceSupported()` which returns true even
  /// when only device passcode is available.
  Future<bool> isBiometricAvailable() async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      // Check for actual enrolled biometrics — not just hardware support
      final enrolled = await _localAuth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Check if the device can authenticate AT ALL — biometrics OR device
  /// credential (PIN/pattern/passcode). False means no screen lock is
  /// enrolled, so `authenticate()` can never succeed: the lock screen must
  /// not treat that as a failed attempt, and wallet creation must require
  /// enrollment first (community report: wallet created on a no-screen-lock
  /// device was unopenable after restart — bead agx).
  Future<bool> isDeviceAuthAvailable() async {
    if (kIsWeb) return true; // web has no local lock gate
    try {
      return await _localAuth.isDeviceSupported();
    } catch (e) {
      debugPrint('isDeviceSupported error: $e');
      return false;
    }
  }

  /// Check if user has opted into biometric lock.
  Future<bool> isBiometricEnabled() async {
    if (kIsWeb) return false;
    final val = await _storage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  /// Set biometric preference.
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled.toString());
  }

  /// Trigger Face ID / Touch ID. Returns true on success.
  ///
  /// The boolean form, for the call sites that only gate an action (a send, a
  /// seed reveal, the biometric toggle) and have no backoff to protect. The
  /// lock screen uses [authenticate] instead, because it has to tell a wrong
  /// finger apart from the OS declining to ask.
  Future<bool> authenticateWithBiometrics() async =>
      (await authenticate()) == AuthOutcome.success;

  /// Trigger Face ID / Touch ID, reporting HOW it ended.
  Future<AuthOutcome> authenticate() async {
    if (kIsWeb) return AuthOutcome.success; // Skip on web
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SoquShield',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow passcode fallback
        ),
      );
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } on PlatformException catch (e) {
      debugPrint('Biometric auth error: ${e.code}');
      // The OS could not run the check. Its own lockout already makes the
      // user wait; the app must not add a second, longer wait on top.
      const cannotRun = {
        auth_error.lockedOut,
        auth_error.permanentlyLockedOut,
        auth_error.notAvailable,
        auth_error.notEnrolled,
        auth_error.passcodeNotSet,
      };
      return cannotRun.contains(e.code)
          ? AuthOutcome.unavailable
          : AuthOutcome.failed;
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return AuthOutcome.failed;
    }
  }

  /// Ask the platform to stop a pending credential prompt before a fresh
  /// one is raised. Android drops its dialog; iOS has no such call and the
  /// caller ignores the stale result instead.
  Future<void> cancelAuthentication() async {
    if (kIsWeb) return;
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      debugPrint('stopAuthentication error: $e');
    }
  }

  /// Clear all account data from secure storage. Called during wallet wipe.
  Future<void> clearAccount() async {
    await _storage.delete(key: _keyAccountName);
    await _storage.delete(key: _keyCreatedAt);
    await _storage.delete(key: _keyBiometricEnabled);
  }
}
