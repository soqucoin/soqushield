import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/fiat_currency.dart';
import '../models/wallet_keys.dart';
import '../services/price_service.dart';
import 'display_prefs_provider.dart';
import 'wallet_provider.dart';

/// The SOQ rate from the company's cached route, polled every
/// [pricePollPeriod] while something watches it.
///
/// ⛔ OFF UNLESS ASKED FOR. The money line is opt-in and off by default, so a
/// wallet whose owner never turned it on makes no price request at all, ever.
///
/// ⛔ MAINNET ONLY. tSOQ is a test coin on a separate chain with no market, so
/// a money figure beside a stagenet balance would be a lie — someone
/// practising with test coins would read a real number against them. On
/// stagenet this yields [SoqPrice.unavailable] once and stops, which also
/// means no outbound call while the owner is on the test network.
///
/// Not autoDispose: the rate is read on Home, Send and Activity, and a fresh
/// fetch on every tab change would be waste. With no watcher the poll pauses
/// on its last figure; a watcher returning after a long pause reads that
/// figure until the next tick, and [SoqPrice.isFresh] hides it if it has gone
/// stale meanwhile.
final soqPriceProvider = StreamProvider<SoqPrice>((ref) async* {
  final network = ref.watch(walletProvider.select((w) => w.network));

  // ⛔ SELECT the fields that matter, never the whole DisplayPrefs. Watching
  // the object re-subscribes this stream on ANY preference change, so every
  // tap of the hide-balances eye would fire a fresh request. Hiding a figure
  // is a display concern and must cost nothing.
  final show = ref.watch(displayPrefsProvider.select((p) => p.showFiat));
  final currency = ref.watch(fiatCurrencyProvider);
  final loaded = ref.watch(displayPrefsProvider.select((p) => p.loaded));

  // Wait for the stored preferences before asking for anything. Until they
  // load, `show` is the default false and `currency` the USD default; firing
  // on those would either skip a fetch the owner wanted or spend one on a
  // currency they did not choose.
  if (!loaded) return;

  if (!show) {
    yield SoqPrice.unavailable(DateTime.now(), currency: currency);
    return;
  }

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

/// The reader the poll calls. A seam, so a test can count the calls: "never
/// call out when the line is off, or for a test coin" is only a real
/// guarantee if a test can observe the call not happening.
final priceFetcherProvider =
    Provider<Future<SoqPrice> Function(FiatCurrency)>(
        (ref) => (currency) => fetchSoqPrice(currency: currency));

/// The rate to show right now, or null when there is nothing to show.
///
/// This is the single gate every money figure in the app passes through, so
/// "no price" means the same thing on every screen: the line being off, the
/// loading tick before the first answer, an unreachable route, a stagenet
/// wallet, a rate the route marks stale, a rate that aged out while the route
/// was quiet, and a rate still denominated in the currency the owner just
/// switched away from all collapse to null, and callers render nothing.
final livePriceProvider = Provider<SoqPrice?>((ref) {
  // ⛔ The opt-in and mainnet rules live HERE, not at each call site.
  // [soqPriceProvider] already refuses to FETCH in those cases; this refuses
  // to HAND OVER a rate whatever the stream holds, so a screen cannot forget
  // and the two cannot drift apart.
  if (!ref.watch(displayPrefsProvider.select((p) => p.showFiat))) return null;
  if (ref.watch(walletProvider.select((w) => w.network)) !=
      SoqNetwork.mainnet) {
    return null;
  }

  final price = ref.watch(soqPriceProvider).asData?.value;
  if (price == null) return null;
  // Covers both the route's own stale flag and the age backstop.
  final now = DateTime.now();
  if (!price.isFresh(now)) return null;
  // A rate carries the currency it was quoted in. Between the owner choosing
  // a new currency and its first answer arriving, the old one is still in the
  // stream — showing it would put a dollar figure behind a euro symbol.
  if (price.currency != ref.watch(fiatCurrencyProvider)) return null;
  // The clock is not a dependency: nothing would recompute this when the
  // rate crosses priceMaxAge between polls, and every reader would keep the
  // cached answer. So the answer carries its own expiry.
  final expiry = Timer(priceMaxAge - price.ageAt(now), ref.invalidateSelf);
  ref.onDispose(expiry.cancel);
  return price;
});
