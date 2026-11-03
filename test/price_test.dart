// The dollar figure: what the price reader accepts, what it refuses, and the
// rule that a test coin is never priced.
//
// The refusals matter more than the happy path. Every one of them exists so a
// real balance is never captioned "$0.00" — a figure that reads as "your funds
// are worthless" rather than "the price is unknown".

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soqushield/models/fiat_currency.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/display_prefs_provider.dart';
import 'package:soqushield/providers/price_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/price_service.dart';
import 'package:soqushield/theme/fmt.dart';

import 'lite_test_support.dart';

/// A client answering every request with [body] at [status].
http.Client _client(String body, {int status = 200}) =>
    MockClient((_) async => http.Response(body, status));

String _ok(Object? usd, {Object? change = 24.406629961491845}) => jsonEncode({
      kCoinGeckoId: {
        'usd': usd,
        'usd_24h_change': ?change,
      }
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(r'fmtUsd — a real balance never reads as $0.00', () {
    test('ordinary money is the ordinary money voice', () {
      expect(fmtUsd(15.98), r'$15.98');
      expect(fmtUsd(1234.5), r'$1,234.50');
      expect(fmtUsd(0.16), r'$0.16');
      expect(fmtUsd(0.01), r'$0.01');
    });

    test('sub-cent widens to two significant digits instead of rounding to 0',
        () {
      // 1000 SOQ at the listing price — the 2dp voice would say "$0.00".
      expect(fmtUsd(0.0016), r'$0.0016');
      expect(fmtUsd(0.00016), r'$0.00016');
      expect(fmtUsd(0.0099), r'$0.0099');
      // A koinu-scale figure stops at 8dp rather than running off the row.
      expect(fmtUsd(0.000000001), r'$0.00000000');
    });

    test('exactly zero is the one figure allowed to read as zero', () {
      expect(fmtUsd(0), r'$0.00');
    });

    test('compact turns a sub-cent COST into the thing worth knowing', () {
      // A fee of 0.0076 SOQ at the listing price. The exact figure is noise
      // beside a fee; "<$0.01" is the answer the user wanted.
      expect(fmtUsd(0.0000012, compact: true), r'<$0.01');
      expect(fmtUsd(0.0016, compact: true), r'<$0.01');
      // At and above a cent, compact changes nothing.
      expect(fmtUsd(0.01, compact: true), r'$0.01');
      expect(fmtUsd(15.98, compact: true), r'$15.98');
      expect(fmtUsd(0, compact: true), r'$0.00');
      // A balance keeps its precision — that one IS the user's money.
      expect(fmtUsd(0.0016), r'$0.0016');
    });

    test('negative figures carry a typographic minus, not a hyphen', () {
      expect(fmtUsd(-15.98), '−\$15.98');
      expect(fmtUsd(double.nan), '—');
    });
  });

  group('fmtPct', () {
    test('signs and rounds to 1dp', () {
      expect(fmtPct(24.406629961491845), '+24.4%');
      expect(fmtPct(-3.21), '−3.2%');
      expect(fmtPct(0), '0.0%');
      expect(fmtPct(double.infinity), '—');
    });
  });

  group('fetchSoqPrice — what it accepts', () {
    test('reads the quote and the 24h change', () async {
      final p = await fetchSoqPrice(client: _client(_ok(0.00015976)));
      expect(p.available, isTrue);
      expect(p.amount, 0.00015976);
      expect(p.change24hPct, closeTo(24.4066, 1e-4));
    });

    test('a listing with no 24h history yet still yields a price', () async {
      final p = await fetchSoqPrice(client: _client(_ok(0.00015976, change: null)));
      expect(p.available, isTrue);
      expect(p.amount, 0.00015976);
      expect(p.change24hPct, isNull);
    });
  });

  group('fetchSoqPrice — what it refuses', () {
    Future<void> refuses(String what, http.Client c) async {
      final p = await fetchSoqPrice(client: c);
      expect(p.available, isFalse, reason: what);
      expect(p.amount, isNull, reason: what);
      expect(p.change24hPct, isNull, reason: what);
    }

    test('a rate-limited free tier', () =>
        refuses('429', _client('{}', status: 429)));

    test('an error page where JSON was expected',
        () => refuses('html', _client('<html>502</html>')));

    test('a body in an unexpected shape',
        () => refuses('array', _client('[1,2,3]')));

    test('a coin id that stops resolving',
        () => refuses('renamed listing', _client('{"other":{"usd":1.0}}')));

    test('a null quote', () => refuses('null', _client(_ok(null))));

    // The three that would otherwise put "$0.00" or a nonsense figure under a
    // real balance.
    test('a zero quote', () => refuses('zero', _client(_ok(0))));
    test('a negative quote', () => refuses('negative', _client(_ok(-1))));
    test('a non-numeric quote',
        () => refuses('string', _client(_ok('free'))));

    test('a transport failure', () async {
      await refuses('throws',
          MockClient((_) async => throw const SocketLikeFailure()));
    });
  });

  group('SoqPrice', () {
    final at = DateTime(2026, 11, 3, 12);
    SoqPrice priced(double usd) => SoqPrice(
        available: true,
        currency: FiatCurrency.usd,
        amount: usd,
        change24hPct: null,
        fetchedAt: at);

    test('usdFor converts, and yields null when there is no price', () {
      expect(priced(0.00015976).valueOf(100000), closeTo(15.976, 1e-9));
      expect(SoqPrice.unavailable(at).valueOf(100000), isNull);
    });

    test('a quote goes quiet once it is too old to trust', () {
      expect(priced(1).isFresh(at.add(const Duration(minutes: 29))), isTrue);
      expect(priced(1).isFresh(at.add(priceMaxAge)), isFalse);
      // A device clock that jumped backwards must not resurrect a stale quote.
      expect(priced(1).isFresh(at.subtract(priceMaxAge)), isFalse);
    });

    test('an unavailable price is never fresh', () {
      expect(SoqPrice.unavailable(at).isFresh(at), isFalse);
    });
  });

  group('the test coin is never priced', () {
    late int calls;

    /// A container whose wallet sits on [network], with the price reader
    /// replaced by one that counts how often it is actually called.
    ProviderContainer containerOn(SoqNetwork network) {
      installSecureStorageMock();
      calls = 0;
      return ProviderContainer(overrides: [
        walletProvider.overrideWith(() => MockWalletNotifier(
            WalletState(network: network, isInitialized: true))),
        priceFetcherProvider.overrideWithValue((currency) async {
          calls++;
          return SoqPrice(
              available: true,
              currency: FiatCurrency.usd,
              amount: 0.00015976,
              change24hPct: 24.4,
              fetchedAt: DateTime.now());
        }),
      ]);
    }

    test('stagenet yields no price and never calls out for one', () async {
      final c = containerOn(SoqNetwork.stagenet);
      addTearDown(c.dispose);
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      final price = await c.read(soqPriceProvider.future);
      expect(price.available, isFalse,
          reason: 'tSOQ has no market — a dollar figure beside it would be a '
              'real number read against a test coin');
      expect(c.read(livePriceProvider), isNull);
      expect(calls, 0,
          reason: 'no outbound price call while on the test network');
    });

    test('mainnet does read a price', () async {
      final c = containerOn(SoqNetwork.mainnet);
      addTearDown(c.dispose);
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      final price = await c.read(soqPriceProvider.future);
      expect(price.available, isTrue);
      expect(calls, 1);
      expect(c.read(livePriceProvider)?.valueOf(100000), closeTo(15.976, 1e-9));
    });
  });

  group('livePriceProvider is the one gate', () {
    test('a stale quote collapses to null, as an absent one does', () {
      final stale = SoqPrice(
          available: true,
          currency: FiatCurrency.usd,
          amount: 1.0,
          change24hPct: null,
          fetchedAt: DateTime.now().subtract(priceMaxAge * 2));
      final c = ProviderContainer(overrides: [
        soqPriceProvider.overrideWith((ref) => Stream.value(stale)),
      ]);
      addTearDown(c.dispose);
      // Prime the stream provider, then read the gate.
      c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
      expect(c.read(livePriceProvider), isNull);
    });
  });

  group('a display change is not a price change', () {
  test('hiding a balance costs no price request', () async {
    var calls = 0;
    final c = ProviderContainer(overrides: [
      walletProvider.overrideWith(() => MockWalletNotifier(WalletState(
          keys: WalletKeys(
              publicKey: Uint8List(WalletKeys.pubKeySize),
              address: 'sq1x', derivationPath: 'm', accountIndex: 0,
              createdAt: DateTime(2026)),
          network: SoqNetwork.mainnet, isInitialized: true))),
      displayPrefsProvider.overrideWith(
          () => FixedDisplayPrefs(const DisplayPrefs(loaded: true))),
      priceFetcherProvider.overrideWithValue((cur) async {
        calls++;
        return SoqPrice(available: true, currency: cur, amount: 1.0,
            change24hPct: 1, fetchedAt: DateTime.now());
      }),
    ]);
    addTearDown(c.dispose);
    c.listen(soqPriceProvider, (_, _) {}, fireImmediately: true);
    await c.read(soqPriceProvider.future);
    expect(calls, 1);

    // Toggle hide-balances three times. The currency never changed, so the
    // price has no reason to be re-quoted. This stream used to watch the whole
    // DisplayPrefs object, so each tap re-subscribed it and spent a request
    // from a shared, per-IP rate-limited free tier on nothing.
    for (var i = 0; i < 3; i++) {
      await c.read(displayPrefsProvider.notifier).toggleHideBalances();
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(calls, 1, reason: 'hiding a balance must not re-quote the price');
  });
  });

}

/// A transport-layer failure, as a client would throw it.
class SocketLikeFailure implements Exception {
  const SocketLikeFailure();
}
