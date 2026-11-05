// The money figure is an extra the owner asks for, read from a rate the
// company caches. Four rules decide whether a number appears, and each one is
// cheap to break and expensive to break:
//
//   off by default   a wallet nobody configured makes no price request at all
//   mainnet only     tSOQ has no market, so a number beside it would be a lie
//   fresh only       a stale rate goes quiet rather than lingering as a number
//   right currency   a dollar figure behind a euro symbol is worse than none
//
// The fetcher is a seam so "no request" can be asserted as an absence of
// calls, not inferred.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/fiat_currency.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/price_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/price_service.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _address =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

WalletState _wallet(SoqNetwork network) => WalletState(
      balance: 10000,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _address,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
      blockHeight: 777,
    );

SoqPrice _rate({
  FiatCurrency currency = FiatCurrency.usd,
  double amount = 0.00015976,
  bool stale = false,
  Duration age = Duration.zero,
  String? source = 'CoinGecko',
}) =>
    SoqPrice(
      available: true,
      currency: currency,
      amount: amount,
      average24h: 0.00014,
      source: source,
      fetchedAt: DateTime.now().subtract(age),
      stale: stale,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  /// A container whose fetcher counts its calls.
  (ProviderContainer, List<FiatCurrency>) harness({
    required DisplayPrefs prefs,
    SoqNetwork network = SoqNetwork.mainnet,
    SoqPrice? answer,
  }) {
    final calls = <FiatCurrency>[];
    final c = ProviderContainer(overrides: [
      walletProvider.overrideWith(() => MockWalletNotifier(_wallet(network))),
      displayPrefsProvider.overrideWith(() => FixedDisplayPrefs(prefs)),
      priceFetcherProvider.overrideWithValue((cur) async {
        calls.add(cur);
        return answer ?? _rate(currency: cur);
      }),
    ]);
    addTearDown(c.dispose);
    return (c, calls);
  }

  group('the request is not made unless it is wanted', () {
    test('a wallet nobody configured asks for nothing', () async {
      // showFiat defaults to false. This is the case that matters most: it is
      // every install until someone goes into Settings.
      final (c, calls) = harness(prefs: const DisplayPrefs(loaded: true));
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty, reason: 'off by default means no call at all');
      expect(c.read(livePriceProvider), isNull);
    });

    test('stagenet asks for nothing even with the line on', () async {
      final (c, calls) = harness(
        prefs: const DisplayPrefs(showFiat: true, loaded: true),
        network: SoqNetwork.stagenet,
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty, reason: 'a test coin has no market to ask about');
      expect(c.read(livePriceProvider), isNull);
    });

    test('nothing is asked before the stored preferences load', () async {
      final (c, calls) = harness(prefs: const DisplayPrefs(showFiat: true));
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty,
          reason: 'firing on the defaults spends a request on a currency the '
              'owner did not choose');
    });

    test('mainnet with the line on asks once, in the chosen currency',
        () async {
      final (c, calls) = harness(
        prefs: const DisplayPrefs(
            showFiat: true, currency: FiatCurrency.eur, loaded: true),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(calls, [FiatCurrency.eur]);
    });
  });

  group('what is handed over', () {
    test('a fresh rate in the right currency is shown', () async {
      final (c, _) = harness(
        prefs: const DisplayPrefs(showFiat: true, loaded: true),
        answer: _rate(),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final p = c.read(livePriceProvider);
      expect(p, isNotNull);
      expect(p!.source, 'CoinGecko');
      expect(p.valueOf(10000), closeTo(1.5976, 0.0001));
    });

    test('the route calling its own rate stale withholds it', () async {
      final (c, _) = harness(
        prefs: const DisplayPrefs(showFiat: true, loaded: true),
        answer: _rate(stale: true),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(livePriceProvider), isNull,
          reason: 'the route knows its own rate is out of date');
    });

    test('a rate that aged out while the route was quiet withholds', () async {
      final (c, _) = harness(
        prefs: const DisplayPrefs(showFiat: true, loaded: true),
        answer: _rate(age: priceMaxAge + const Duration(minutes: 1)),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(livePriceProvider), isNull,
          reason: 'a route that stops answering cannot set a stale flag');
    });

    test('a rate in the currency the owner just left withholds', () async {
      // The owner switches to EUR; the USD answer is still in the stream.
      final (c, _) = harness(
        prefs: const DisplayPrefs(
            showFiat: true, currency: FiatCurrency.eur, loaded: true),
        answer: _rate(currency: FiatCurrency.usd),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(livePriceProvider), isNull,
          reason: 'a dollar figure behind a euro symbol is worse than none');
    });

    test('turning the line off withholds whatever the stream holds', () async {
      final (c, _) = harness(
        prefs: const DisplayPrefs(loaded: true),
        answer: _rate(),
      );
      c.listen(soqPriceProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(livePriceProvider), isNull);
    });
  });

  group('no change figure and no chart', () {
    test('the money widget takes no change parameter at all', () {
      // Enforced by the type, not by a call-site convention: a delta cannot
      // be passed in without editing InstrumentFiat itself.
      const w = InstrumentFiat(value: r'$1.60', source: 'CoinGecko');
      expect(w.value, r'$1.60');
      expect(w.source, 'CoinGecko');
    });

    test('the 24-hour average is parsed but is not a display field', () {
      // It rides the model because the route sends it; nothing renders it.
      final p = _rate();
      expect(p.average24h, isNotNull);
    });

    test('the age reads coarsely', () {
      expect(InstrumentFiat.ageLabel(const Duration(seconds: 20)), 'just now');
      expect(InstrumentFiat.ageLabel(const Duration(minutes: 4)), '4 min ago');
      expect(InstrumentFiat.ageLabel(const Duration(hours: 2)), '2 hr ago');
    });
  });
}
