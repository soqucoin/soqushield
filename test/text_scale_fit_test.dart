// The pinned layouts at the text-scale limit on narrow phones: every screen
// a holder uses renders on a 375 by 667 and on a 360 by 640 logical surface
// at 130 percent without a row or a column overflowing. The rows that carry
// long telemetry scale their text down to fit, the recovery-phrase words
// scale rather than ellipsise, and the backup screen scrolls as a page when
// the surface is too short for its grid; the test is the gate for the limit
// in main.dart.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/main.dart' show kMaxTextScale;
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/activity/activity_pilot_screen.dart';
import 'package:soqushield/screens/auth/create_account_pilot_screen.dart';
import 'package:soqushield/screens/auth/lock_pilot_screen.dart';
import 'package:soqushield/screens/auth/risk_disclosure_screen.dart';
import 'package:soqushield/screens/auth/seed_backup_screen.dart';
import 'package:soqushield/screens/auth/seed_restore_screen.dart';
import 'package:soqushield/screens/auth/welcome_pilot_screen.dart';
import 'package:soqushield/screens/guide/guide_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/network/network_screen.dart';
import 'package:soqushield/screens/receive/receive_pilot_screen.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/screens/settings/settings_pilot_screen.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/widgets/seed_word_grid.dart';

import 'lite_test_support.dart';

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _surfaces = [Size(375, 667), Size(360, 640)];

/// Twenty-four of the longest words a phrase can carry (eight letters), so
/// the cells are tested at their widest.
final _words = List.generate(24, (i) => 'material');

WalletState _wallet({bool backedUp = true, double balance = 0}) => WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _mainnetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      seedPhrase: backedUp ? null : SeedPhrase(words: _words),
      network: SoqNetwork.mainnet,
      backupConfirmed: backedUp,
      isInitialized: true,
      balance: balance,
      blockHeight: 1234,
    );

/// A credential that never answers, so the lock screen stays put.
class _PendingAuthService extends FakeAuthService {
  @override
  Future<bool> authenticateWithBiometrics() {
    prompts++;
    return Completer<bool>().future;
  }
}

Widget _scoped(WalletState wallet, Widget child) => ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(_PendingAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 1234, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 10, 6)))),
        poolWeatherProvider.overrideWith((ref) => Stream.value(
            PoolWeather(reachable: false, fetchedAt: DateTime(2026, 10, 6)))),
      ],
      child: MaterialApp(home: child),
    );

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = kMaxTextScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  final screens = <String, Widget Function()>{
    'welcome': () => const WelcomePilotScreen(),
    'create account': () => const CreateAccountPilotScreen(),
    'seed backup': () => const SeedBackupScreen(),
    'seed restore': () => const SeedRestoreScreen(),
    'risk disclosure': () => const RiskDisclosureScreen(),
    'lock': () => const LockPilotScreen(),
    'home': () => const HomePilotScreen(),
    'send': () => const SendPilotScreen(),
    'receive': () => const ReceivePilotScreen(),
    'settings': () => const SettingsPilotScreen(),
    'activity': () => const ActivityPilotScreen(),
    'network': () => const NetworkPilotScreen(),
    'field manual': () => const GuideScreen(),
  };

  for (final size in _surfaces) {
    final tag = '${size.width.toInt()} by ${size.height.toInt()}';
    for (final entry in screens.entries) {
      testWidgets('${entry.key} fits $tag at the text-scale limit',
          (tester) async {
        _surface(tester, size);
        // The seed backup screen needs the phrase in state; the home a
        // seven-figure balance, the widest value the readout takes.
        final wallet = entry.key == 'seed backup'
            ? _wallet(backedUp: false)
            : _wallet(balance: entry.key == 'home' ? 1234567.89 : 0);
        await tester.pumpWidget(_scoped(wallet, entry.value()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull,
            reason: '${entry.key} overflows at the limit on $tag');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('the revealed phrase fits $tag at the limit, every word '
        'whole', (tester) async {
      _surface(tester, size);
      await tester.pumpWidget(
          _scoped(_wallet(backedUp: false), const SeedBackupScreen()));
      await tester.pump();
      await tester.tap(find.text('Tap to reveal recovery phrase'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull,
          reason: 'the revealed backup screen overflows on $tag');
      // Every built word is shown whole: it scales inside its cell instead
      // of ending in an ellipsis.
      final words = find.byType(SeedWord);
      expect(words, findsWidgets);
      for (final element in words.evaluate()) {
        final text = find.descendant(
            of: find.byWidget(element.widget), matching: find.byType(Text));
        expect(tester.widget<Text>(text).overflow, isNot(TextOverflow.ellipsis));
        expect(
            find.descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(FittedBox)),
            findsOneWidget);
      }
      expect(find.text('COPY ALL'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
