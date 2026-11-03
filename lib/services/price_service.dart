// What a SOQ is worth right now, in the currency the owner chose, read from
// CoinGecko's public API. Nothing here holds a key, a token or an account: the
// figure is the one anyone can read from the public price endpoint, and the
// app only shows it. The request names the coin and a currency — never an
// address, never a balance.
//
// The wallet's own numbers are never derived from this. A price is a display
// convenience laid over a balance the chain already decided — coin selection,
// fees and every amount that reaches a transaction stay in koinu. A price the
// app could not read simply isn't shown (see [SoqPrice.unavailable]); it never
// degrades to 0.00, which would read as "your funds are worthless" rather than
// "the price is unknown".
//
// Mainnet only. tSOQ is a test coin with no market, so the stagenet wallet
// never shows a figure and never calls out for one — see
// providers/price_provider.dart, which is where that rule is enforced.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/fiat_currency.dart';

/// CoinGecko's public API host. The only price host this app talks to.
const String kPriceApiHost = 'api.coingecko.com';

/// SOQ's CoinGecko coin id — https://www.coingecko.com/en/coins/soqucoin.
const String kCoinGeckoId = 'soqucoin';

/// How long a fetched price stays good. CoinGecko's free tier is rate-limited
/// per IP and shared across every install, so the poll is deliberately slow:
/// a wallet balance is not a trading screen, and a five-minute-old price is
/// accurate enough to tell someone what their holdings are worth.
const Duration pricePollPeriod = Duration(minutes: 5);

/// A price older than this is not shown. It bounds how wrong the figure can be
/// when the endpoint stops answering: rather than leave a stale number on
/// screen indefinitely, the dollar line disappears and the SOQ figure — which
/// is always correct — stands on its own.
const Duration priceMaxAge = Duration(minutes: 30);

/// The SOQ price in one currency, as last read.
///
/// [available] is false when the endpoint did not answer, answered with a body
/// this reader could not take, or quoted a non-positive price; [amount] and
/// [change24hPct] are then null. Callers show nothing in that case.
@immutable
class SoqPrice {
  /// Whether [amount] holds a real quote.
  final bool available;

  /// The currency [amount] is denominated in.
  final FiatCurrency currency;

  /// Units of [currency] per 1 SOQ. Null when [available] is false.
  final double? amount;

  /// Change over the last 24 hours, in percent (+24.4 = up 24.4%). Null when
  /// unavailable, and also null when the endpoint quoted a price but no
  /// change — a fresh listing has no 24-hour history yet.
  final double? change24hPct;

  /// When this app read the figure (device clock).
  final DateTime fetchedAt;

  const SoqPrice({
    required this.available,
    required this.currency,
    required this.amount,
    required this.change24hPct,
    required this.fetchedAt,
  });

  /// No price: the endpoint did not answer, or answered unusably.
  const SoqPrice.unavailable(DateTime at,
      {FiatCurrency currency = FiatCurrency.usd})
      : this(
            available: false,
            currency: currency,
            amount: null,
            change24hPct: null,
            fetchedAt: at);

  /// Whether this quote is still young enough to show. A price the app cannot
  /// refresh goes quiet rather than lingering as a stale number.
  bool isFresh(DateTime now) =>
      available && now.difference(fetchedAt).abs() < priceMaxAge;

  /// What [soq] coins are worth, in [currency], at this price. Null when there
  /// is no price to apply — callers render nothing rather than a zero.
  double? valueOf(double soq) {
    final p = amount;
    if (p == null) return null;
    final v = soq * p;
    return v.isFinite ? v : null;
  }
}

/// One public GET on CoinGecko's simple-price endpoint, in [currency].
///
/// Never throws: every failure shape — no network, a timeout, a 429 from the
/// shared free-tier rate limit, an error page, a body in an unexpected shape,
/// a coin id that stops resolving, a currency it will not quote — returns
/// [SoqPrice.unavailable], because the caller's only two states are "show the
/// figure" and "don't".
Future<SoqPrice> fetchSoqPrice({
  http.Client? client,
  FiatCurrency currency = FiatCurrency.usd,
}) async {
  final c = client ?? http.Client();
  final now = DateTime.now();
  SoqPrice none() => SoqPrice.unavailable(now, currency: currency);
  try {
    final r = await c.get(Uri.https(kPriceApiHost, '/api/v3/simple/price', {
      'ids': kCoinGeckoId,
      'vs_currencies': currency.code,
      'include_24hr_change': 'true',
    })).timeout(const Duration(seconds: 8));

    if (r.statusCode != 200) {
      debugPrint('PRICE: CoinGecko answered ${r.statusCode}');
      return none();
    }

    final body = jsonDecode(r.body);
    if (body is! Map) return none();
    final coin = body[kCoinGeckoId];
    if (coin is! Map) {
      // The id resolves to nothing — the listing moved or was renamed. Quiet,
      // not an error state: the wallet still works, it just shows no figure.
      debugPrint('PRICE: no "$kCoinGeckoId" in the CoinGecko answer');
      return none();
    }

    // The quote comes back keyed by the currency that was asked for; the 24h
    // change rides the same key with a suffix.
    final amount = _positiveDouble(coin[currency.code]);
    if (amount == null) {
      // A null, zero or negative quote is not a price — and a currency the
      // endpoint declines to quote lands here too. Showing it would put
      // "0.00" under a real balance.
      debugPrint('PRICE: unusable ${currency.code} quote ${coin[currency.code]}');
      return none();
    }

    return SoqPrice(
      available: true,
      currency: currency,
      amount: amount,
      change24hPct: _finiteDouble(coin['${currency.code}_24h_change']),
      fetchedAt: now,
    );
  } catch (e) {
    debugPrint('PRICE: CoinGecko unreadable: $e');
    return none();
  } finally {
    if (client == null) c.close();
  }
}

/// A finite double from whatever JSON put there, else null.
double? _finiteDouble(Object? raw) {
  final v = raw is num ? raw.toDouble() : null;
  return (v != null && v.isFinite) ? v : null;
}

/// A finite, strictly positive double, else null.
double? _positiveDouble(Object? raw) {
  final v = _finiteDouble(raw);
  return (v != null && v > 0) ? v : null;
}
