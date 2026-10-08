// The first frame and the text size. A cold start draws the app's own ground
// on both platforms before Flutter paints (no white flash on a light-themed
// device), iOS system UI renders dark to match the app, and the system text
// scale is honoured up to the pinned layouts' limit.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/main.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/services/weather_service.dart';

import 'lite_test_support.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the first frame', () {
    test('Android draws the app ground behind the launch and the window, in '
        'one theme for both system settings', () {
      const res = 'android/app/src/main/res';
      expect(_read('$res/values/colors.xml'),
          contains('<color name="launch_background">#0B0D10</color>'));
      for (final d in ['drawable', 'drawable-v21']) {
        expect(_read('$res/$d/launch_background.xml'),
            contains('@color/launch_background'),
            reason: '$d: the launch screen is the app ground');
        expect(_read('$res/$d/launch_background.xml'),
            isNot(contains('@android:color/white')));
      }
      final styles = _read('$res/values/styles.xml');
      expect('Theme.Black.NoTitleBar'.allMatches(styles).length, 2,
          reason: 'both themes are dark');
      expect(styles, isNot(contains('Theme.Light')));
      expect(styles, contains('@color/launch_background'),
          reason: 'the window behind the Flutter view is the app ground');
      expect(File('$res/values-night/styles.xml').existsSync(), isFalse,
          reason: 'one theme serves both settings');
    });

    test('iOS draws the app ground on the launch screen and renders its '
        'system UI dark', () {
      final storyboard = _read('ios/Runner/Base.lproj/LaunchScreen.storyboard');
      expect(storyboard, isNot(contains('red="1" green="1" blue="1"')),
          reason: 'no white launch screen');
      expect(storyboard, contains('red="0.043" green="0.051" blue="0.063"'));
      final plist = _read('ios/Runner/Info.plist');
      expect(plist, contains('<key>UIUserInterfaceStyle</key>'));
      expect(
          RegExp(r'<key>UIUserInterfaceStyle</key>\s*<string>Dark</string>')
              .hasMatch(plist),
          isTrue);
    });
  });

  testWidgets('the system text scale is honoured up to the pinned layouts\' '
      'limit, on a narrow phone', (tester) async {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
    final home = tester.element(find.byType(HomePilotScreen));
    expect(MediaQuery.textScalerOf(home).scale(10), closeTo(10 * kMaxTextScale, 0.01),
        reason: 'a 200 percent system setting reaches the screens as the limit');
    expect(tester.takeException(), isNull, reason: 'nothing overflows at the limit');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
