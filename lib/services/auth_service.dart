import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart' show kSharedSecureStorage;

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
  Future<bool> authenticateWithBiometrics() async {
    if (kIsWeb) return true; // Skip on web
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access SoquShield',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow passcode fallback
        ),
      );
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return false;
    }
  }

  /// Clear all account data from secure storage. Called during wallet wipe.
  Future<void> clearAccount() async {
    await _storage.delete(key: _keyAccountName);
    await _storage.delete(key: _keyCreatedAt);
    await _storage.delete(key: _keyBiometricEnabled);
  }
}
