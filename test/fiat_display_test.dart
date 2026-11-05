// The money figure on screen: where it appears, where it must not, what it
// says about where it came from, and what it does when the balance beside it
// is hidden.
//
// Every other widget test stubs the rate away (lite_test_support.quietPrice),
// so this file is the one that pumps a screen WITH a rate and reads what the
// owner would see.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/fiat_currency.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/price_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/services/price_service.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/fmt.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

/// The listing rate at the time of writing: well under a cent, which is the
/// case a 2dp money voice would have rendered as "$0.00".
const _rate = 0.00015976;

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

WalletState _wallet(SoqNetwork network, {double balance = 100000}) =>
    WalletState(
      balance: balance,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address:
            network == SoqNetwork.mainnet ? _mainnetAddress : _stagenetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
      blockHeight: 777,
    );

dynamic _priced({
  double amount = _rate,
  String? source = 'CoinGecko',
  Duration age = Duration.zero,
}) =>
    soqPriceProvider.overrideWith((ref) => Stream.value(SoqPrice(
          available: true,
          currency: FiatCurrency.usd,
          amount: amount,
          average24h: 0.00014,
          source: source,
          fetchedAt: DateTime.now().subtract(age),
          stale: false,
        )));

/// [price] defaults to no rate at all, and [showFiat] to the real default of
/// off, so a test that says nothing reads the screen as an unconfigured
/// wallet sees it.
Widget _scoped(
  WalletState wallet,
  Widget child, {
  dynamic price,
  bool showFiat = false,
  bool hide = false,
}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 777, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith(
            (ref) => Stream.value(ChainWeather.unreachable(DateTime(2026, 11, 3)))),
        price ?? quietPrice,
        displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(
            DisplayPrefs(showFiat: showFiat, hideBalances: hide, loaded: true))),
      ],
      child: child,
    );

Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  group('Home', () {
    testWidgets('100,000 SOQ at a sub-cent rate reads as a real figure',
        (t) async {
      // 100,000 x 0.00015976 = 15.976 -> $15.98. The point of the money voice
      // is that a real holding never reads as "$0.00".
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
        showFiat: true,
      ));
      await t.pump();
      expect(find.text(r'$15.98'), findsWidgets);
      await _tearDownTree(t);
    });

    testWidgets('the figure says where it came from and how old it is',
        (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(age: const Duration(minutes: 4)),
        showFiat: true,
      ));
      await t.pump();
      expect(find.textContaining('CoinGecko'), findsWidgets,
          reason: 'a number with no provenance reads as the wallet\'s own '
              'valuation of the owner\'s coins');
      expect(find.textContaining('4 min ago'), findsWidgets);
      await _tearDownTree(t);
    });

    testWidgets('no change figure appears anywhere', (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
        showFiat: true,
      ));
      await t.pump();
      // The average the route sends is 0.00014 against a 0.00015976 spot;
      // a change figure would be some rendering of that gap.
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      await _tearDownTree(t);
    });

    testWidgets('off by default: an unconfigured wallet shows no figure',
        (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
      ));
      await t.pump();
      expect(find.text(r'$15.98'), findsNothing,
          reason: 'the rate is in the stream, but the line was never asked '
              'for, so nothing may render it');
      await _tearDownTree(t);
    });

    testWidgets('hiding the balance hides the money under it', (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
        showFiat: true,
        hide: true,
      ));
      await t.pump();
      expect(find.text(r'$15.98'), findsNothing,
          reason: 'a masked balance whose money figure is still shown is not '
              'masked — the figure hands the balance straight back');
      expect(find.text(maskedMoney(FiatCurrency.usd)), findsWidgets);
      await _tearDownTree(t);
    });

    testWidgets('stagenet shows no money figure, rate or no rate', (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.stagenet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
        showFiat: true,
      ));
      await t.pump();
      expect(find.byType(InstrumentFiat), findsNothing,
          reason: 'tSOQ has no market; a real number beside it reads as real '
              'money to someone practising');
      await _tearDownTree(t);
    });
  });

  group('Send', () {
    testWidgets('the amount being typed is priced as you type', (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: SendPilotScreen()),
        price: _priced(),
        showFiat: true,
      ));
      await t.pump();
      await t.enterText(find.byType(TextField).at(0), '10000');
      await t.pump();
      // 10,000 x 0.00015976 = 1.5976 -> $1.60
      expect(find.text(r'$1.60'), findsWidgets);
      await _tearDownTree(t);
    });

    testWidgets('stagenet prices nothing, however much is typed', (t) async {
      await t.pumpWidget(_scoped(
        _wallet(SoqNetwork.stagenet),
        const MaterialApp(home: SendPilotScreen()),
        price: _priced(),
        showFiat: true,
      ));
      await t.pump();
      await t.enterText(find.byType(TextField).at(0), '10000');
      await t.pump();
      expect(find.text(r'$1.60'), findsNothing);
      await _tearDownTree(t);
    });
  });

  group('the money voice', () {
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
}
