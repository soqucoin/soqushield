// Hiding balances has to be TOTAL and it has to PERSIST.
//
// It was local state on Home, so it came undone on the next tab and on the
// next launch — which is useless, because the reason to hide a balance is to
// hand someone the phone. It is a stored preference now, and the eye beside
// the label is the affordance that makes it findable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _address =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

WalletState _wallet({double balance = 10000}) => WalletState(
      balance: balance,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _address,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: SoqNetwork.mainnet,
      backupConfirmed: true,
      isInitialized: true,
      blockHeight: 777,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  ProviderContainer container(DisplayPrefs prefs) {
    final c = ProviderContainer(overrides: [
      authProvider
          .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
      authServiceProvider.overrideWithValue(FakeAuthService()),
      sessionProvider.overrideWith(MockSessionNotifier.new),
      walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
      networkStatsProvider.overrideWith((ref) => const AsyncData(
          NetworkStats(blocks: 777, peers: 8, reachable: true))),
      chainWeatherProvider.overrideWith(
          (ref) => Stream.value(ChainWeather.unreachable(DateTime(2026, 11, 3)))),
      displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(prefs)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpHome(WidgetTester t, ProviderContainer c) async {
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: HomePilotScreen()),
    ));
    await t.pump();
    addTearDown(() async {
      await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await t.pump(const Duration(minutes: 1));
    });
  }

  group('hiding balances', () {
    testWidgets('the holdings figure and the asset row both go', (t) async {
      final c = container(const DisplayPrefs(hideBalances: true, loaded: true));
      await pumpHome(t, c);

      expect(find.text('10000.00'), findsNothing,
          reason: 'one unmasked copy of the figure hands the balance back');
      expect(find.text('••••••'), findsWidgets);
    });

    testWidgets('shown again when the preference is off', (t) async {
      final c = container(const DisplayPrefs(loaded: true));
      await pumpHome(t, c);
      expect(find.text('10000.00'), findsWidgets);
    });

    testWidgets('the eye beside the label toggles, and names its action',
        (t) async {
      final c = container(const DisplayPrefs(loaded: true));
      await pumpHome(t, c);

      // Visible: the icon offers the action "hide", and says so in words for
      // anyone who cannot read an eye glyph.
      final eye = find.byType(InstrumentEye);
      expect(eye, findsOneWidget);
      expect(t.widget<InstrumentEye>(eye).hidden, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.bySemanticsLabel('Hide balances'), findsOneWidget);

      await t.tap(eye);
      await t.pump();

      expect(c.read(hideBalancesProvider), isTrue);
      expect(find.text('••••••'), findsWidgets);
      // Hidden: the icon now offers "show".
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.bySemanticsLabel('Show balances'), findsOneWidget);

      await t.tap(find.byType(InstrumentEye));
      await t.pump();
      expect(c.read(hideBalancesProvider), isFalse);
    });

    testWidgets('tapping the figure still works, for anyone who reaches for it',
        (t) async {
      // The old behaviour was local state on Home: switching tabs undid it.
      // The gesture now writes the preference, which is what persists.
      final c = container(const DisplayPrefs(loaded: true));
      await pumpHome(t, c);
      expect(c.read(hideBalancesProvider), isFalse);

      await t.tap(find.text('10000.00').first);
      await t.pump();

      expect(c.read(hideBalancesProvider), isTrue,
          reason: 'the tap must change the stored preference, not a field on '
              'this screen that dies with it');
      expect(find.text('••••••'), findsWidgets);
    });

    test('the stored value survives, and anything but "true" is shown',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(displayPrefsProvider.notifier);
      await notifier.setHideBalances(true);
      expect(c.read(hideBalancesProvider), isTrue);
      await notifier.toggleHideBalances();
      expect(c.read(hideBalancesProvider), isFalse);
    });
  });
}
