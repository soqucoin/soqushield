// After a wipe the session is a fresh install's: the defaults, no timer
// armed, nothing carried over in memory. The stored keys go with the wipe
// itself (lite_provider_fixes_test case 3); this is the in-memory side.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/providers/session_provider.dart';

import 'lite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  test('resetToDefaults returns the session to a fresh install', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(sessionProvider.notifier);
    // The notifier loads its stored settings after build, through the
    // storage channel; let that land before changing anything.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    const fresh = SessionConfig();
    await notifier.setTimeoutMinutes(fresh.timeoutMinutes == 2 ? 10 : 2);
    await notifier.setLockOnBackground(!fresh.lockOnBackground);
    expect(container.read(sessionProvider).timeoutMinutes,
        isNot(fresh.timeoutMinutes));
    expect(secureStore.keys, containsAll(SessionNotifier.storedKeys.take(2)),
        reason: 'the settings were stored under the notifier\'s keys');

    notifier.resetToDefaults();
    final after = container.read(sessionProvider);
    expect(after.timeoutMinutes, fresh.timeoutMinutes);
    expect(after.lockOnBackground, fresh.lockOnBackground);
    expect(after.failedAttempts, fresh.failedAttempts);
  });
}
