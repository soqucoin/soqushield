import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';

/// Auth state — representing the user's authentication status.
enum AuthStatus {
  /// Initial check in progress
  loading,
  /// No account exists — show welcome/onboarding
  noAccount,
  /// Account exists but not yet authenticated (needs biometric)
  locked,
  /// Authenticated — full app access
  authenticated,
}

/// Singleton auth service provider.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Auth state notifier — manages the authentication lifecycle.
class AuthNotifier extends AsyncNotifier<AuthStatus> {
  @override
  Future<AuthStatus> build() async {
    return _checkAuthState();
  }

  Future<AuthStatus> _checkAuthState() async {
    final service = ref.read(authServiceProvider);

    // Wallet presence is the SOURCE OF TRUTH for a returning user. A transient
    // secure-storage read failure must NEVER route a wallet-holder to onboarding,
    // which offers "create new wallet" and can overwrite an existing wallet. This
    // was the "wallet erased" report: EncryptedSharedPreferences can fail the
    // first read after a hard process kill, so a single account-name read is
    // race-prone. Onboarding is shown ONLY when storage is readable AND empty.
    final walletExists = await _walletExists();
    if (walletExists != false) {
      // Wallet present, or storage unreadable (unknown). Either way, protect it.
      // SB-5: a returning user is ALWAYS locked on launch. Unlocking is handled
      // by the lock screen (biometric or device passcode every time).
      return AuthStatus.locked;
    }

    // Wallet definitively absent. A stray account record still counts as returning.
    bool hasAcc;
    try {
      hasAcc = await service.hasAccount();
    } catch (_) {
      hasAcc = false;
    }
    return hasAcc ? AuthStatus.locked : AuthStatus.noAccount;
  }

  /// Whether a wallet exists on this device.
  ///
  /// Returns `true` if present, `false` if definitively absent (storage readable,
  /// no mnemonic), and `null` if the read could not be completed. Retries once,
  /// because EncryptedSharedPreferences occasionally throws on the first read
  /// after a hard process kill or a crash mid-write.
  Future<bool?> _walletExists() async {
    final storage = SecureStorageService();
    try {
      return await storage.hasWallet();
    } catch (_) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return await storage.hasWallet();
      } catch (_) {
        return null; // unknown — caller treats this as "protect the wallet"
      }
    }
  }

  /// Called after successful biometric auth.
  void unlock() {
    state = const AsyncData(AuthStatus.authenticated);
  }

  /// Called after account creation.
  Future<void> onAccountCreated() async {
    state = const AsyncData(AuthStatus.authenticated);
  }

  /// Called when app returns from background / on inactivity timeout (re-lock).
  ///
  /// SB-5: locks whenever a wallet exists, regardless of the biometric *toggle*.
  /// The lock screen then requires biometric or device passcode to get back in.
  Future<void> lock() async {
    final service = ref.read(authServiceProvider);
    if (await service.hasAccount()) {
      state = const AsyncData(AuthStatus.locked);
    }
  }

  /// Re-check auth state (e.g. after settings change).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _checkAuthState());
  }
}

/// The main auth state provider.
final authProvider = AsyncNotifierProvider<AuthNotifier, AuthStatus>(
  AuthNotifier.new,
);

/// Convenience provider for the account name.
final accountNameProvider = FutureProvider<String?>((ref) async {
  final service = ref.read(authServiceProvider);
  return service.getAccountName();
});
