// Screen capture is the owner's choice, and the rules around it are easy to
// get wrong and expensive to get wrong: it has to default to protected, a
// change has to reach the platform before it is stored, and it must never
// extend to the recovery phrase.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/services/screen_capture.dart';

import 'lite_test_support.dart';

/// Every `setAllowed` the platform channel was asked for, in order.
late List<bool> captureCalls;

void installCaptureMock() {
  captureCalls = [];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('org.soqu.soqushield/capture'),
    (call) async {
      if (call.method == 'setAllowed') {
        captureCalls.add(
            ((call.arguments as Map)['allow'] as bool?) ?? false);
        return true;
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    installCaptureMock();
  });

  group('screen capture', () {
    test('defaults to protected', () {
      expect(const DisplayPrefs().allowScreenCapture, isFalse,
          reason: 'permitting capture also permits screen recording and '
              'casting — it has to be a decision the owner made');
    });

    test('a stored value other than "true" means protected', () async {
      // A failed read, or a value written by a build without this setting.
      secureStore.remove('soq_allow_capture_v1');
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(displayPrefsProvider, (_, _) {}, fireImmediately: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.read(displayPrefsProvider).allowScreenCapture, isFalse);
    });

    test('a change reaches the platform before it is stored', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(displayPrefsProvider, (_, _) {}, fireImmediately: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      captureCalls.clear();

      await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(true);

      expect(captureCalls, [true]);
      expect(secureStore['soq_allow_capture_v1'], 'true');
      expect(c.read(displayPrefsProvider).allowScreenCapture, isTrue);
    });

    test('whileProtected covers the phrase and hands the setting back',
        () async {
      await ScreenCapture.setAllowed(true);
      captureCalls.clear();

      await ScreenCapture.whileProtected(() async {
        // Inside: protection is on whatever the owner chose.
        expect(captureCalls, [false]);
        expect(ScreenCapture.allowed, isFalse);
      });

      expect(captureCalls, [false, true],
          reason: 'the owner keeps the setting they chose');
      expect(ScreenCapture.allowed, isTrue);
    });

    test('whileProtected leaves a protected wallet protected', () async {
      await ScreenCapture.setAllowed(false);
      captureCalls.clear();
      await ScreenCapture.whileProtected(() async {});
      expect(captureCalls, isEmpty, reason: 'nothing to change, nothing said');
      expect(ScreenCapture.allowed, isFalse);
    });

    test('the setting is restored even when the screen throws', () async {
      await ScreenCapture.setAllowed(true);
      captureCalls.clear();
      await expectLater(
        ScreenCapture.whileProtected(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(ScreenCapture.allowed, isTrue,
          reason: 'a failure must not silently leave capture forbidden');
    });
  });
}
