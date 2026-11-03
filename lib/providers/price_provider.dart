import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fiat_currency.dart';
import '../models/wallet_keys.dart';
import '../services/price_service.dart';
import 'display_prefs_provider.dart';
import 'wallet_provider.dart';

/// The SOQ price, polled every [pricePollPeriod] while something watches it;
/// watch() re-subscribes on a network switch and on a currency change.
///
/// ⛔ MAINNET ONLY. tSOQ is a test coin on a separate chain with no market, so
/// a money figure beside a stagenet balance would be a lie — someone
/// practising with test coins would read a real number against them. On
/// stagenet this yields [SoqPrice.unavailable] once and stops, which also
/// means the app makes no outbound call to CoinGecko at all while the user is
/// on the test network.
///
/// Not autoDispose: the price is read on Home, Send and Activity, and a fresh
/// fetch on every tab change would burn the shared free-tier rate limit for no
/// gain. With no watcher the poll pauses on its last figure; a watcher
/// returning after a long pause reads that figure until the next tick, and
/// [SoqPrice.isFresh] hides it if it has gone stale in the meantime.
/// Re-subscribes on a currency change too, so switching to EUR in Settings
/// re-quotes immediately rather than showing dollars under a euro symbol
/// until the next five-minute tick.
final soqPriceProvider = StreamProvider<SoqPrice>((ref) async* {
  final network = ref.watch(walletProvider.select((w) => w.network));

  // ⛔ SELECT the two fields that matter, never the whole DisplayPrefs.
  // Watching the object re-subscribes this stream on ANY preference change,
  // so every tap of the hide-balances eye fired a fresh CoinGecko request —
  // three taps, three requests, against a shared free tier that rate-limits
  // per IP. Hiding a figure is a display concern and must cost nothing.
  final currency = ref.watch(fiatCurrencyProvider);
  final loaded = ref.watch(displayPrefsProvider.select((p) => p.loaded));

  // Wait for the stored preferences before asking for anything. Until they
  // load, `currency` is the USD default — firing on that would spend a request
  // on a currency the owner did not choose, then immediately fire again on the
  // right one, with a flash of the wrong symbol in between.
  if (!loaded) return;

  if (network != SoqNetwork.mainnet) {
    yield SoqPrice.unavailable(DateTime.now(), currency: currency);
    return;
  }

  final fetch = ref.read(priceFetcherProvider);
  yield await fetch(currency);
  await for (final _ in Stream.periodic(pricePollPeriod)) {
    yield await fetch(currency);
  }
});

/// The reader the poll calls. A seam, so a test can count the calls: the
/// stagenet rule above is "never call out for a test coin", and that is only
/// a real guarantee if a test can observe the call not happening.
final priceFetcherProvider =
    Provider<Future<SoqPrice> Function(FiatCurrency)>(
        (ref) => (currency) => fetchSoqPrice(currency: currency));

/// The price to show right now, or null when there is nothing to show.
///
/// This is the single gate every money figure in the app passes through, so
/// "no price" means the same thing on every screen: the loading tick before
/// the first answer, an unreachable endpoint, a stagenet wallet, a quote that
/// has gone stale and a quote still denominated in the currency the owner just
/// switched away from all collapse to null, and callers render nothing.
final livePriceProvider = Provider<SoqPrice?>((ref) {
  // ⛔ The mainnet rule lives HERE, not at each call site. [soqPriceProvider]
  // already refuses to FETCH on stagenet; this refuses to HAND OVER a price
  // there whatever the stream holds, so a screen that reads a price cannot
  // forget that tSOQ has no market and the two rules cannot drift apart. A
  // widget test proved the need: with the stream overridden to a live quote,
  // the asset row and the Activity rows — which read this provider and did
  // their own network check nowhere — priced a stagenet balance in dollars.
  if (ref.watch(walletProvider.select((w) => w.network)) !=
      SoqNetwork.mainnet) {
    return null;
  }

  final price = ref.watch(soqPriceProvider).asData?.value;
  if (price == null) return null;
  if (!price.isFresh(DateTime.now())) return null;
  // A quote carries the currency it was asked in. During the moment between
  // the owner choosing a new currency and its first answer arriving, the old
  // quote is still in the stream — showing it would put a dollar figure
  // behind a euro symbol. Withhold it until the currencies agree.
  if (price.currency != ref.watch(fiatCurrencyProvider)) return null;
  return price;
});
