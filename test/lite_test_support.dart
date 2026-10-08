// Shared fakes for the lite-build tests: an in-memory secure storage behind the
// plugin's method channel, a device-auth service that always succeeds, and
// provider mocks that arm no timers.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/auth_service.dart';

/// The backing map of the mocked secure storage. Reset by [installSecureStorageMock].
final Map<String, String> secureStore = {};

/// Every call the mocked secure storage received, as `method key`.
final List<String> secureStorageCalls = [];

/// A write to one of these keys waits on its completer before it lands, so a
/// test can switch the network or wipe the wallet while a write is in flight.
final Map<String, Completer<void>> secureStorageWriteHolds = {};

/// The next write to one of these keys is refused with a platform error (the
/// key is removed from the set as it fires), so a test can fail a storage
/// write once, mid-operation.
final Set<String> secureStorageWriteFailures = {};

/// Route the flutter_secure_storage channel to [secureStore].
void installSecureStorageMock() {
  secureStore.clear();
  secureStorageCalls.clear();
  secureStorageWriteHolds.clear();
  secureStorageWriteFailures.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      secureStorageCalls.add('${call.method} ${args['key'] ?? ''}'.trim());
      switch (call.method) {
        case 'read':
          return secureStore[args['key'] as String];
        case 'write':
          if (secureStorageWriteFailures.remove(args['key'] as String)) {
            throw PlatformException(code: 'test', message: 'write refused');
          }
          final hold = secureStorageWriteHolds[args['key'] as String];
          if (hold != null) await hold.future;
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
      }
      return null;
    },
  );
}

/// Device auth that reports an enrolled screen lock and succeeds every time.
/// [prompts] counts the credential requests, so a test can assert a path
/// refused before asking for one.
class FakeAuthService extends AuthService {
  int prompts = 0;
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
  Future<bool> authenticateWithBiometrics() async {
    prompts++;
    return true;
  }
  @override
  Future<void> clearAccount() async {}
}

class MockAuthNotifier extends AsyncNotifier<AuthStatus> implements AuthNotifier {
  final AuthStatus _status;
  MockAuthNotifier(this._status);
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

/// A session that never locks and arms no inactivity timer.
class MockSessionNotifier extends Notifier<SessionConfig> implements SessionNotifier {
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
  Future<void> setTimeoutMinutes(int minutes) async =>
      state = state.copyWith(timeoutMinutes: minutes);
  @override
  Future<void> setLockOnBackground(bool enabled) async =>
      state = state.copyWith(lockOnBackground: enabled);
  @override
  Future<T> whileSystemUi<T>(Future<T> Function() action) => action();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class MockWalletNotifier extends Notifier<WalletState> implements WalletNotifier {
  final WalletState _state;
  MockWalletNotifier(this._state);
  @override
  WalletState build() => _state;
  @override
  Future<void> refreshBalance() async {}
  @override
  Future<void> syncActivity() async {}
  @override
  Future<void> confirmBackup() async {}
  @override
  void clearKeyCache() {}
  @override
  Future<void> setNetwork(network) async => state = state.copyWith(network: network);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
