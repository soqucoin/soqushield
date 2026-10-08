// The lock of an unlocked wallet is a state change, not a storage read: an
// account read that fails once, or a wallet with no account record beside
// it, must not leave an unlocked wallet unlocked. A launch with no wallet
// still goes to onboarding and a lock there changes nothing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/services/auth_service.dart';

import 'lite_test_support.dart';

/// An account record whose read fails, as a secure-storage read can after a
/// hard process kill.
class _UnreadableAccount extends FakeAuthService {
  @override
  Future<bool> hasAccount() async => throw StateError('storage unreadable');
}

/// A wallet with no account record beside it.
class _NoAccountRecord extends FakeAuthService {
  @override
  Future<bool> hasAccount() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  /// A container whose wallet is present and unlocked, over [service].
  Future<ProviderContainer> unlocked(AuthService service) async {
    secureStore['soq_mnemonic_v2'] = 'word ' * 24;
    final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);
    expect(await container.read(authProvider.future), AuthStatus.locked,
        reason: 'a returning user is locked on launch');
    container.read(authProvider.notifier).unlock();
    expect(container.read(authProvider).value, AuthStatus.authenticated);
    return container;
  }

  test('an account read that fails still locks the unlocked wallet', () async {
    final container = await unlocked(_UnreadableAccount());
    await container.read(authProvider.notifier).lock();
    expect(container.read(authProvider).value, AuthStatus.locked);
  });

  test('a wallet with no account record still locks', () async {
    final container = await unlocked(_NoAccountRecord());
    await container.read(authProvider.notifier).lock();
    expect(container.read(authProvider).value, AuthStatus.locked);
  });

  test('a lock on a locked wallet holds, and a second unlock is the only way back',
      () async {
    final container = await unlocked(FakeAuthService());
    await container.read(authProvider.notifier).lock();
    await container.read(authProvider.notifier).lock();
    expect(container.read(authProvider).value, AuthStatus.locked);
    container.read(authProvider.notifier).unlock();
    expect(container.read(authProvider).value, AuthStatus.authenticated);
  });

  test('no wallet, no lock: onboarding is not sent to the lock screen', () async {
    final container = ProviderContainer(
        overrides: [authServiceProvider.overrideWithValue(_NoAccountRecord())]);
    addTearDown(container.dispose);
    expect(await container.read(authProvider.future), AuthStatus.noAccount);
    await container.read(authProvider.notifier).lock();
    expect(container.read(authProvider).value, AuthStatus.noAccount);
  });
}
