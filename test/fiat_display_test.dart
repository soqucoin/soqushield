// The dollar figure on screen: where it appears, where it must not, and what
// it does when the balance beside it is hidden.
//
// Every other widget test stubs the price away (lite_test_support.quietPrice),
// so this file is the one that pumps a screen WITH a price and reads what the
// user would see.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soqushield/models/fiat_currency.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/price_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/activity/activity_pilot_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/services/price_service.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

/// The listing price at the time of writing: well under a cent, which is the
/// case the 2dp money voice would have rendered as "$0.00".
const _price = 0.00015976;

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

WalletState _wallet(
  SoqNetwork network, {
  double balance = 100000,
  List<WalletTransaction> txs = const [],
}) =>
    WalletState(
      balance: balance,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: network == SoqNetwork.mainnet
            ? _mainnetAddress
            : _stagenetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
      blockHeight: 777,
      recentTransactions: txs,
    );

/// A live quote, as the provider would hand it over.
dynamic _priced({double usd = _price, double? change = 24.4}) =>
    soqPriceProvider.overrideWith((ref) => Stream.value(SoqPrice(
          available: true,
          currency: FiatCurrency.usd,
          amount: usd,
          change24hPct: change,
          fetchedAt: DateTime.now(),
        )));

/// [price] defaults to no price at all, so a test that says nothing about the
/// price reads the screen as it was before fiat existed. Exactly one price
/// override reaches the scope — two would be a duplicate-override assertion.
Widget _scoped(WalletState wallet, Widget child, {dynamic price}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 777, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 11, 3)))),
        price ?? quietPrice,
 quietDisplayPrefs,
      ],
      child: child,
    );

/// Replace the tree so every provider is disposed, then drain kept timers.
Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('Home', () {
    testWidgets('100,000 SOQ at a sub-cent price reads as a real figure',
        (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, balance: 100000),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
      ));
      await tester.pump();

      // 100000 × 0.00015976 = 15.976 → the ordinary money voice.
      expect(find.text(r'$15.98'), findsWidgets);
      await _tearDownTree(tester);
    });

    testWidgets('the 24h change rides beside it', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(change: 24.4),
      ));
      await tester.pump();

      expect(
          find.byWidgetPredicate((w) =>
              w is InstrumentFiat && w.change == '+24.4%' && w.up == true),
          findsOneWidget);
      await _tearDownTree(tester);
    });

    testWidgets('a fall is encoded as a fall, not as a rise', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(change: -8.25),
      ));
      await tester.pump();

      expect(
          find.byWidgetPredicate((w) =>
              w is InstrumentFiat && w.change == '−8.3%' && w.up == false),
          findsOneWidget);
      await _tearDownTree(tester);
    });

    testWidgets('masking the balance masks the dollars under it',
        (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, balance: 100000),
        const MaterialApp(home: HomePilotScreen()),
        price: _priced(),
      ));
      await tester.pump();
      expect(find.text(r'$15.98'), findsWidgets);

      // Tap the holdings readout — the gesture that hides the balance.
      await tester.tap(find.text('100000.00').first);
      await tester.pump();

      expect(find.text(r'$15.98'), findsNothing,
          reason: 'a masked balance that still shows its dollar value is not '
              'masked — the figure hands the balance straight back');
      // The change is suppressed too: it is a property of the holding.
      expect(
          find.byWidgetPredicate(
              (w) => w is InstrumentFiat && w.change != null),
          findsNothing);
      await _tearDownTree(tester);
    });

    testWidgets('stagenet shows no dollar figure anywhere', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.stagenet, balance: 100000),
        const MaterialApp(home: HomePilotScreen()),
        // Even handed a live quote, the screen must refuse to price tSOQ.
        price: _priced(),
      ));
      await tester.pump();

      expect(find.byType(InstrumentFiat), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      await _tearDownTree(tester);
    });

    testWidgets('no price at all leaves the screen as it was', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, balance: 100000),
        const MaterialApp(home: HomePilotScreen()),
      ));
      await tester.pump();

      expect(find.byType(InstrumentFiat), findsNothing);
      expect(find.text('100000.00'), findsWidgets,
          reason: 'the SOQ figure is always right, with or without a price');
      await _tearDownTree(tester);
    });
  });

  group('Send', () {
    testWidgets('the amount being typed is priced as you type', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, balance: 200000),
        const MaterialApp(home: SendPilotScreen()),
        price: _priced(),
      ));
      await tester.pump();

      // Nothing typed yet: the slot is reserved, but it holds no figure —
      // "$0.00" under an empty amount field is noise, not information.
      expect(find.byType(InstrumentFiat), findsNothing);

      await tester.enterText(find.byType(TextField).at(0), '100000');
      await tester.pump();

      expect(find.text(r'$15.98'), findsOneWidget);
      await _tearDownTree(tester);
    });

    testWidgets('stagenet prices nothing, however much is typed',
        (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.stagenet, balance: 200000),
        const MaterialApp(home: SendPilotScreen()),
        price: _priced(),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '100000');
      await tester.pump();

      expect(find.byType(InstrumentFiat), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      await _tearDownTree(tester);
    });
  });

  group('Activity', () {
    WalletTransaction tx(double amount) => WalletTransaction(
          txid: 'a' * 64,
          type: TxType.received,
          amount: amount,
          timestamp: DateTime.now(),
          confirmations: 3,
        );

    testWidgets('a row carries its dollar figure and the price caveat',
        (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, txs: [tx(100000)]),
        const MaterialApp(home: ActivityPilotScreen()),
        price: _priced(),
      ));
      await tester.pump();

      expect(find.text(r'$15.98'), findsOneWidget);
      expect(
          find.textContaining('not the price at the time'), findsOneWidget,
          reason: 'the figure is today\'s price on an old amount — the row '
              'must not pass as a record of what the payment was worth then');
      await _tearDownTree(tester);
    });

    testWidgets('with no price, neither the figure nor the caveat appears',
        (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.mainnet, txs: [tx(100000)]),
        const MaterialApp(home: ActivityPilotScreen()),
      ));
      await tester.pump();

      expect(find.textContaining('not the price at the time'), findsNothing,
          reason: 'nothing to qualify');
      await _tearDownTree(tester);
    });

    testWidgets('stagenet rows carry no dollar figure', (tester) async {
      await tester.pumpWidget(_scoped(
        _wallet(SoqNetwork.stagenet, txs: [tx(100000)]),
        const MaterialApp(home: ActivityPilotScreen()),
        price: _priced(),
      ));
      await tester.pump();

      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('not the price at the time'), findsNothing);
      await _tearDownTree(tester);
    });
  });
}
