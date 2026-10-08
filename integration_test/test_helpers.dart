/// Test helpers for SoquShield integration tests.
///
/// Provides mock provider overrides so integration tests can run
/// headlessly in a simulator without a live backend, against the app's
/// real router and screens.
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/router.dart';
import 'package:soqushield/services/auth_service.dart';
import 'package:soqushield/theme/app_theme.dart';

// ═══════════════════════════════════════════
//  Test App Builder
// ═══════════════════════════════════════════

/// Build the app on its real router, started at [initialRoute].
///
/// Bypasses splash/auth. Overrides the wallet, auth, auth-service and session
/// providers with test-safe mocks.
Widget buildTestApp({
  required String initialRoute,
  WalletState? walletState,
  AuthStatus authStatus = AuthStatus.authenticated,
}) {
  final ws = walletState ?? mockWalletState;
  router.go(initialRoute);
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(() => _MockAuthNotifier(authStatus)),
      authServiceProvider.overrideWithValue(_FakeAuthService()),
      sessionProvider.overrideWith(_MockSessionNotifier.new),
      walletProvider.overrideWith(() => _MockWalletNotifier(ws)),
    ],
    child: MaterialApp.router(
      title: 'SoquShield Test',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    ),
  );
}

// ═══════════════════════════════════════════
//  Mock State Factories
// ═══════════════════════════════════════════

/// Pre-built mainnet wallet state with test data.
WalletState get mockWalletState => WalletState(
      balance: 10000.0,
      pendingBalance: 0,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address:
            'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn',
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: SoqNetwork.mainnet,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
      blockHeight: 42000,
    );

// ═══════════════════════════════════════════
//  Mocks
// ═══════════════════════════════════════════

class _FakeAuthService extends AuthService {
  @override
  Future<bool> hasAccount() async => true;
  @override
  Future<void> createAccount(String name) async {}
  @override
  Future<String?> getAccountName() async => 'Test';
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isDeviceAuthAvailable() async => true;
  @override
  Future<bool> isBiometricEnabled() async => false;
  @override
  Future<void> setBiometricEnabled(bool enabled) async {}
  @override
  Future<bool> authenticateWithBiometrics() async => true;
  @override
  Future<void> clearAccount() async {}
}

class _MockAuthNotifier extends AsyncNotifier<AuthStatus>
    implements AuthNotifier {
  final AuthStatus _status;
  _MockAuthNotifier(this._status);

  @override
  Future<AuthStatus> build() async => _status;
  @override
  void unlock() => state = const AsyncData(AuthStatus.authenticated);
  @override
  Future<void> onAccountCreated() async =>
      state = const AsyncData(AuthStatus.authenticated);
  @override
  Future<void> lock() async => state = const AsyncData(AuthStatus.locked);
  @override
  Future<void> refresh() async => state = AsyncData(_status);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockSessionNotifier extends Notifier<SessionConfig>
    implements SessionNotifier {
  @override
  SessionConfig build() => const SessionConfig();
  @override
  bool get isInLockout => false;
  @override
  bool get isLockedOut => false;
  @override
  Duration get remainingLockout => Duration.zero;
  @override
  void recordActivity() {}
  @override
  void pauseForTransaction() {}
  @override
  void resumeAfterTransaction() {}
  @override
  void onAppBackground() {}
  @override
  void onAppForeground() {}
  @override
  Future<void> recordFailedAttempt() async {}
  @override
  Future<void> resetFailedAttempts() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockWalletNotifier extends Notifier<WalletState>
    implements WalletNotifier {
  final WalletState _state;
  _MockWalletNotifier(this._state);

  @override
  WalletState build() => _state;
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<void> syncActivity() async {}
  @override
  void clearKeyCache() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ═══════════════════════════════════════════
//  Convenience Extensions
// ═══════════════════════════════════════════

extension WidgetTesterX on WidgetTester {
  /// Pump fixed frames (avoids pumpAndSettle hanging on continuous animations).
  Future<void> pumpSteady({int count = 20}) async {
    for (int i = 0; i < count; i++) {
      await pump(const Duration(milliseconds: 100));
    }
  }

  /// Verify that a text widget exists on screen.
  void expectText(String text, {String? reason}) {
    expect(find.text(text), findsWidgets,
        reason: reason ?? 'Expected "$text" on screen');
  }

  /// Verify that a text widget does NOT exist on screen.
  void expectNoText(String text) {
    expect(find.text(text), findsNothing,
        reason: 'Did not expect "$text" on screen');
  }
}
