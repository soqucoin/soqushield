// The three things the owner controls about what the wallet shows: whether
// balances are hidden, which currency figures are in, and whether the screen
// may be captured.
//
// Each has a rule that is easy to get wrong and expensive to get wrong:
// hiding has to be total (a masked balance beside an unmasked money figure is
// not hidden), capture has to default to protected and never extend to the
// recovery phrase, and a currency switch must not leave the old quote on
// screen behind the new symbol.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/fiat_currency.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/price_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/services/price_service.dart';
import 'package:soqushield/services/screen_capture.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/fmt.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _address =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

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

SoqPrice _priceIn(FiatCurrency c, double amount) => SoqPrice(
      available: true,
      currency: c,
      amount: amount,
      change24hPct: 24.4,
      fetchedAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    installCaptureMock();
  });

  group('fmtMoney speaks each currency', () {
    test('the symbol leads and the decimals follow the currency', () {
      expect(fmtMoney(15.976, FiatCurrency.usd), r'$15.98');
      expect(fmtMoney(15.976, FiatCurrency.eur), '€15.98');
      expect(fmtMoney(1234.5, FiatCurrency.gbp), '£1,234.50');
      // A code rather than a glyph carries its own separating space.
      expect(fmtMoney(15.976, FiatCurrency.chf), 'CHF 15.98');
    });

    test('a currency with no minor unit shows none', () {
      // ¥2,410 — not ¥2,410.00, which is not how yen is written.
      expect(fmtMoney(2410.4, FiatCurrency.jpy), '¥2,410');
      expect(fmtMoney(2410.4, FiatCurrency.krw), '₩2,410');
    });

    test('below one minor unit the figure widens rather than reading as zero',
        () {
      expect(fmtMoney(0.0016, FiatCurrency.eur), '€0.0016');
      // For yen one minor unit is 1, so sub-1 is where yen widens.
      expect(fmtMoney(0.42, FiatCurrency.jpy), '¥0.42');
      expect(fmtMoney(1.4, FiatCurrency.jpy), '¥1');
    });

    test('compact says the useful thing about a sub-unit COST', () {
      expect(fmtMoney(0.0000012, FiatCurrency.usd, compact: true), r'<$0.01');
      expect(fmtMoney(0.0000012, FiatCurrency.eur, compact: true), '<€0.01');
      expect(fmtMoney(0.4, FiatCurrency.jpy, compact: true), '<¥1');
    });

    test('the mask wears the currency it is hiding', () {
      expect(maskedMoney(FiatCurrency.usd), r'$••••');
      expect(maskedMoney(FiatCurrency.eur), '€••••');
    });
  });

  group('hiding balances', () {
    ProviderContainer container(DisplayPrefs prefs) {
      final c = ProviderContainer(overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 777, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 11, 3)))),
        soqPriceProvider.overrideWith(
            (ref) => Stream.value(_priceIn(FiatCurrency.usd, 0.00015976))),
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

    testWidgets('hides the SOQ figure AND the money figure beside it',
        (t) async {
      final c = container(const DisplayPrefs(hideBalances: true, loaded: true));
      await pumpHome(t, c);

      expect(find.text('10000.00'), findsNothing);
      expect(find.text(r'$1.60'), findsNothing,
          reason: 'a masked balance whose money figure is still shown is not '
              'masked — the figure hands the balance straight back');
      expect(find.text('••••••'), findsWidgets);
      // The 24h change goes with it: it is a property of the holding.
      expect(
          find.byWidgetPredicate(
              (w) => w is InstrumentFiat && w.change != null),
          findsNothing);
    });

    testWidgets('shown again when the preference is off', (t) async {
      final c = container(const DisplayPrefs(loaded: true));
      await pumpHome(t, c);
      expect(find.text('10000.00'), findsWidgets);
      expect(find.text(r'$1.60'), findsWidgets);
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
      expect(
          find.bySemanticsLabel('Hide balances'), findsOneWidget);

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
  });

  group('choosing a currency', () {
    test('a stored code is read back, and an unknown one falls to USD', () {
      expect(FiatCurrency.fromCode('eur'), FiatCurrency.eur);
      expect(FiatCurrency.fromCode('jpy'), FiatCurrency.jpy);
      expect(FiatCurrency.fromCode(null), FiatCurrency.usd);
      // A currency a later build removed must not break a wallet that stored it.
      expect(FiatCurrency.fromCode('xyz'), FiatCurrency.usd);
    });

    test('the quote is withheld until it is in the chosen currency', () async {
      // Between choosing EUR and its first answer arriving, the dollar quote
      // is still in the stream. Showing it would put a dollar figure behind a
      // euro symbol.
      final c = ProviderContainer(overrides: [
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(
            const DisplayPrefs(currency: FiatCurrency.eur, loaded: true))),
        soqPriceProvider.overrideWith(
            (ref) => Stream.value(_priceIn(FiatCurrency.usd, 0.00015976))),
      ]);
      addTearDown(c.dispose);
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      // Await the quote, or this reads null simply because the stream has not
      // resolved yet — which would pass for entirely the wrong reason.
      final quote = await c.read(soqPriceProvider.future);
      expect(quote.currency, FiatCurrency.usd);

      expect(c.read(livePriceProvider), isNull,
          reason: 'a USD quote must not be shown under a EUR symbol');
    });

    test('a matching quote is handed over', () async {
      final c = ProviderContainer(overrides: [
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(
            const DisplayPrefs(currency: FiatCurrency.eur, loaded: true))),
        soqPriceProvider.overrideWith(
            (ref) => Stream.value(_priceIn(FiatCurrency.eur, 0.00014))),
      ]);
      addTearDown(c.dispose);
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      await c.read(soqPriceProvider.future);

      final price = c.read(livePriceProvider);
      expect(price?.currency, FiatCurrency.eur);
      expect(price?.valueOf(10000), closeTo(1.4, 1e-9));
    });

    test('the price is re-quoted in the currency that was asked for',
        () async {
      final asked = <FiatCurrency>[];
      final c = ProviderContainer(overrides: [
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(
            const DisplayPrefs(currency: FiatCurrency.jpy, loaded: true))),
        priceFetcherProvider.overrideWithValue((currency) async {
          asked.add(currency);
          return _priceIn(currency, 0.024);
        }),
      ]);
      addTearDown(c.dispose);
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      await c.read(soqPriceProvider.future);

      expect(asked, [FiatCurrency.jpy]);
    });
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
