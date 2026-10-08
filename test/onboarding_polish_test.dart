// The onboarding polish and the Mainnet waiting line. Each case is the gate
// for one change: the seed grids show all 24 words on the 6.9-inch surface
// (430 by 932 logical) without scrolling and scroll on a small one; the
// primary actions are the instrument button, lit only when they can act; the
// Mainnet home explains OFFLINE and the Stagenet home does not; the Android
// capture switch cannot lift FLAG_SECURE outside a debuggable build and is
// never called from lib/.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/auth/risk_disclosure_screen.dart';
import 'package:soqushield/screens/auth/seed_backup_screen.dart';
import 'package:soqushield/screens/auth/seed_restore_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

const _waitingLine =
    'Mainnet opens at launch. Your address is ready to receive.';

/// The 6.9-inch phone's logical surface (the brief's gate) and a small one.
const _large = Size(430, 932);
const _small = Size(375, 667);

/// Twenty-four distinct words, so a found word is the cell it belongs to.
final _words = List.generate(24, (i) => 'word${i + 1}');

WalletState _wallet(SoqNetwork network, String address,
        {bool backupConfirmed = true, SeedPhrase? seed}) =>
    WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: address,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      seedPhrase: seed,
      network: network,
      backupConfirmed: backupConfirmed,
      isInitialized: true,
    );

Widget _scoped(WalletState wallet, Widget child,
        {List<dynamic> extra = const []}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
        ...extra,
      ],
      child: MaterialApp(home: child),
    );

void _surface(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

GridView _grid(WidgetTester tester) =>
    tester.widget<GridView>(find.byType(GridView));

InstrumentButton _button(WidgetTester tester, String caps) =>
    tester.widget<InstrumentButton>(find.widgetWithText(InstrumentButton, caps));

/// Replace the tree so every provider is disposed, then drain any timer the
/// screens arm.
Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

Future<void> _pumpRevealedBackup(WidgetTester tester) async {
  await tester.pumpWidget(_scoped(
    _wallet(SoqNetwork.mainnet, _mainnetAddress,
        backupConfirmed: false, seed: SeedPhrase(words: _words)),
    const SeedBackupScreen(),
  ));
  await tester.pump();
  await tester.tap(find.text('Tap to reveal recovery phrase'));
  await tester.pump();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('seed backup', () {
    testWidgets('shows all 24 words without scrolling on the 6.9-inch surface',
        (tester) async {
      _surface(tester, _large);
      await _pumpRevealedBackup(tester);
      for (var i = 0; i < 24; i++) {
        expect(find.text(_words[i]), findsOneWidget,
            reason: 'word ${i + 1} is on screen');
        expect(find.text('${i + 1}'), findsOneWidget,
            reason: 'cell ${i + 1} is numbered');
      }
      expect(_grid(tester).physics, isA<NeverScrollableScrollPhysics>());
      // The last row sits above the actions, inside the viewport.
      final last = tester.getRect(find.text(_words[23]));
      final copy = tester.getRect(find.text('COPY ALL'));
      expect(last.bottom, lessThan(copy.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolls on a small phone and still reaches word 24',
        (tester) async {
      _surface(tester, _small);
      await _pumpRevealedBackup(tester);
      expect(_grid(tester).physics, isNot(isA<NeverScrollableScrollPhysics>()));
      await tester.scrollUntilVisible(find.text(_words[23]), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(_words[23]), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('continue lights only after the confirmation', (tester) async {
      _surface(tester, _large);
      await _pumpRevealedBackup(tester);
      expect(_button(tester, 'CONTINUE').enabled, isFalse);
      expect(_button(tester, 'CONTINUE').primary, isTrue);
      await tester.tap(find.text(
          'I have written down my recovery phrase and stored it securely'));
      await tester.pump();
      expect(_button(tester, 'CONTINUE').enabled, isTrue);
    });
  });

  group('seed restore', () {
    testWidgets('offers 24 fields on one screen; restore lights once all are filled',
        (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(
          _scoped(_wallet(SoqNetwork.mainnet, ''), const SeedRestoreScreen()));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(24));
      for (var i = 1; i <= 24; i++) {
        expect(find.text('$i'), findsOneWidget, reason: 'field $i is numbered');
      }
      expect(_grid(tester).physics, isA<NeverScrollableScrollPhysics>());
      expect(_button(tester, 'RESTORE WALLET').enabled, isFalse);
      for (var i = 0; i < 24; i++) {
        await tester.enterText(find.byType(TextField).at(i), 'abandon');
      }
      await tester.pump();
      expect(_button(tester, 'RESTORE WALLET').enabled, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no keyboard corrects, suggests or learns the 24 words',
        (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(
          _scoped(_wallet(SoqNetwork.mainnet, ''), const SeedRestoreScreen()));
      await tester.pump();
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.length, 24);
      for (final f in fields) {
        expect(f.autocorrect, isFalse);
        expect(f.enableSuggestions, isFalse);
        expect(f.enableIMEPersonalizedLearning, isFalse);
      }
    });
  });

  group('risk disclosure', () {
    testWidgets('the acknowledgement is a lit primary action', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_scoped(
          _wallet(SoqNetwork.mainnet, _mainnetAddress),
          const RiskDisclosureScreen()));
      await tester.pump();
      for (final t in [
        'Important Information',
        'Price Volatility',
        'Self-Custody',
        'Irreversible Transactions',
        'Post-Quantum Security',
      ]) {
        expect(find.text(t), findsOneWidget, reason: '$t is on screen');
      }
      final button = _button(tester, 'I UNDERSTAND — CONTINUE');
      expect(button.primary, isTrue);
      expect(button.enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('home', () {
    Future<void> pumpHome(WidgetTester tester, SoqNetwork network,
        String address, {required bool reachable}) async {
      await tester.pumpWidget(_scoped(
        _wallet(network, address),
        const HomePilotScreen(),
        extra: [
          networkStatsProvider.overrideWith((ref) => AsyncData(NetworkStats(
              blocks: reachable ? 1234 : 0,
              peers: reachable ? 8 : 0,
              reachable: reachable))),
        ],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Mainnet says why the chain reads OFFLINE', (tester) async {
      await pumpHome(tester, SoqNetwork.mainnet, _mainnetAddress,
          reachable: false);
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsOneWidget);
      expect(find.text(_waitingLine), findsOneWidget);
      await _tearDownTree(tester);
    });

    testWidgets('Stagenet OFFLINE stays bare', (tester) async {
      await pumpHome(tester, SoqNetwork.stagenet, _stagenetAddress,
          reachable: false);
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsOneWidget);
      expect(find.text(_waitingLine), findsNothing);
      await _tearDownTree(tester);
    });

    testWidgets('a live Mainnet carries no waiting line', (tester) async {
      await pumpHome(tester, SoqNetwork.mainnet, _mainnetAddress,
          reachable: true);
      expect(find.text('SOQUCOIN · ML-DSA-44 · LIVE'), findsOneWidget);
      expect(find.text(_waitingLine), findsNothing);
      await _tearDownTree(tester);
    });
  });

  group('instrument language', () {
    test('the first screens no longer use the older palette', () {
      for (final path in [
        'lib/screens/auth/seed_backup_screen.dart',
        'lib/screens/auth/seed_restore_screen.dart',
        'lib/screens/auth/risk_disclosure_screen.dart',
      ]) {
        expect(_read(path), isNot(contains('SoquColors')), reason: path);
        expect(_read(path), contains('InstrumentButton'), reason: path);
      }
    });
  });

  group('android capture switch', () {
    final activity = _read(
        'android/app/src/main/kotlin/org/soqu/soqushield/MainActivity.kt');

    test('the flag is set at create and lifted only inside the debuggable check',
        () {
      expect(activity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
      final set = activity.indexOf('window.setFlags');
      final lift = activity.indexOf('window.clearFlags');
      expect(set, greaterThan(-1));
      expect(lift, greaterThan(set));
      final gate = activity.lastIndexOf('if (debuggable)', lift);
      expect(gate, greaterThan(-1), reason: 'the lift sits under the gate');
      expect(activity, contains('ApplicationInfo.FLAG_DEBUGGABLE'));
    });

    test('nothing under lib/ names the capture channel', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) =>
              f.readAsStringSync().contains('org.soqu.soqushield/capture'))
          .map((f) => f.path)
          .toList();
      expect(hits, isEmpty);
    });
  });
}
