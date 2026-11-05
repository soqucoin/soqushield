// Screen capture is the owner's choice, and the rules around it are easy to
// get wrong and expensive to get wrong: it has to default to protected, a
// change has to reach the platform before it is stored, and it must never
// extend to the recovery phrase.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soqushield/main.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/services/screen_capture.dart';
import 'package:soqushield/services/secure_storage_service.dart';
import 'package:soqushield/services/weather_service.dart';

import 'lite_test_support.dart';

/// Every `setAllowed` the platform channel was asked for, in order.
late List<bool> captureCalls;

/// The platform's window state, as the mock last applied it.
late bool nativeAllows;

/// When set, the next `setAllowed` with this value fails on the platform.
bool? failNext;

void installCaptureMock() {
  captureCalls = [];
  nativeAllows = false;
  failNext = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('org.soqu.soqushield/capture'),
    (call) async {
      if (call.method == 'setAllowed') {
        final allow = ((call.arguments as Map)['allow'] as bool?) ?? false;
        if (failNext == allow) {
          failNext = null;
          throw PlatformException(code: 'test', message: 'refused');
        }
        captureCalls.add(allow);
        nativeAllows = allow;
        return true;
      }
      return null;
    },
  );
}

const _key = 'soq_allow_capture_v1';

Future<ProviderContainer> loaded() async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c.listen(displayPrefsProvider, (_, _) {}, fireImmediately: true);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    installCaptureMock();
    ScreenCapture.debugReset();
  });

  group('screen capture', () {
    test('defaults to protected', () {
      expect(const DisplayPrefs().allowScreenCapture, isFalse,
          reason: 'permitting capture also permits screen recording and '
              'casting — it has to be a decision the owner made');
    });

    test('a stored value other than "true" means protected', () async {
      // A failed read, or a value written by a build without this setting.
      secureStore.remove(_key);
      final c = await loaded();
      expect(c.read(displayPrefsProvider).allowScreenCapture, isFalse);
    });

    test('a change reaches the platform before it is stored', () async {
      final c = await loaded();
      captureCalls.clear();

      expect(
          await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(true),
          isTrue);

      expect(captureCalls, [true]);
      expect(secureStore[_key], 'true');
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
      expect(captureCalls.where((a) => a), isEmpty,
          reason: 'nothing ever asks the platform to allow');
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

    test('a stored "allowed" that loads while a phrase screen is open does '
        'not lift protection behind it', () async {
      secureStore[_key] = 'true';
      final hold = Completer<void>();
      secureStorageReadHolds[_key] = hold;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(displayPrefsProvider, (_, _) {}, fireImmediately: true);

      // The recovery phrase opens before the read answers.
      final shield = ScreenCapture.shield();
      await shield.applied;
      hold.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(displayPrefsProvider).allowScreenCapture, isTrue,
          reason: 'the owner\'s choice is read and shown');
      expect(nativeAllows, isFalse,
          reason: 'but the window stays protected while the phrase shows');

      await shield.release();
      expect(nativeAllows, isTrue,
          reason: 'and the choice applies once the phrase screen leaves');
    });

    test('a change made while a phrase screen is open waits for it to leave',
        () async {
      final c = await loaded();
      final shield = ScreenCapture.shield();
      await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(true);
      expect(nativeAllows, isFalse);
      await shield.release();
      expect(nativeAllows, isTrue);
    });

    test('a choice made while the stored value is loading is not overwritten '
        'by the late read', () async {
      secureStore[_key] = 'false';
      final hold = Completer<void>();
      secureStorageReadHolds[_key] = hold;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(displayPrefsProvider, (_, _) {}, fireImmediately: true);
      await Future<void>.delayed(Duration.zero);

      final set =
          c.read(displayPrefsProvider.notifier).setAllowScreenCapture(true);
      hold.complete();
      expect(await set, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(c.read(displayPrefsProvider).allowScreenCapture, isTrue);
      expect(secureStore[_key], 'true');
      expect(nativeAllows, isTrue);
    });

    test('a platform that fails to protect leaves the preference as it was',
        () async {
      secureStore[_key] = 'true';
      final c = await loaded();
      expect(nativeAllows, isTrue);

      failNext = false;
      final ok =
          await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(false);

      expect(ok, isFalse);
      expect(c.read(displayPrefsProvider).allowScreenCapture, isTrue,
          reason: 'the switch shows what the window does: still capturable');
      expect(secureStore[_key], 'true');
      expect(ScreenCapture.ownerAllows, isTrue);
    });

    test('a protect that is not stored keeps protection on and reports it',
        () async {
      secureStore[_key] = 'true';
      final c = await loaded();

      secureStorageWriteFailures.add(_key);
      final ok =
          await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(false);

      expect(ok, isFalse, reason: 'the caller tells the owner it was not saved');
      expect(nativeAllows, isFalse);
      expect(c.read(displayPrefsProvider).allowScreenCapture, isFalse);
    });

    test('an allow that is not stored puts protection back', () async {
      final c = await loaded();

      secureStorageWriteFailures.add(_key);
      final ok =
          await c.read(displayPrefsProvider.notifier).setAllowScreenCapture(true);

      expect(ok, isFalse);
      expect(nativeAllows, isFalse,
          reason: 'storage still says protected, and the next launch would');
      expect(c.read(displayPrefsProvider).allowScreenCapture, isFalse);
    });

    test('a wipe returns the window to protected and deletes the stored '
        'choice by name', () async {
      secureStore[_key] = 'true';
      final c = await loaded();
      expect(nativeAllows, isTrue);

      await c.read(displayPrefsProvider.notifier).resetToDefaults();
      await SecureStorageService().wipeWallet();

      expect(nativeAllows, isFalse);
      expect(c.read(displayPrefsProvider).allowScreenCapture, isFalse);
      expect(secureStorageCalls, contains('delete $_key'),
          reason: 'on iOS the wallet\'s deleteAll does not reach an item '
              'written with the default accessibility');
      expect(SecureStorageService.displayKeys,
          containsAll(DisplayPrefsNotifier.storedKeys));
    });

    testWidgets('the stored choice reaches the platform at launch, before '
        'Settings is ever opened', (tester) async {
      SharedPreferences.setMockInitialValues({});
      secureStore[_key] = 'true';
      final wallet = WalletState(
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
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider
              .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
          authServiceProvider.overrideWithValue(FakeAuthService()),
          sessionProvider.overrideWith(MockSessionNotifier.new),
          walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
          networkStatsProvider.overrideWith((ref) => const AsyncData(
              NetworkStats(blocks: 1234, peers: 8, reachable: true))),
          chainWeatherProvider.overrideWith((ref) =>
              Stream.value(ChainWeather.unreachable(DateTime(2026, 10, 6)))),
        ],
        child: const SoquShieldApp(),
      ));
      await tester.pump(const Duration(seconds: 3)); // past the splash
      await tester.pump();
      // The capture channel answers outside the fake clock.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(nativeAllows, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
