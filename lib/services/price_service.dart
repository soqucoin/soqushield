/// The SOQ price, read from the company's own cached route.
///
/// ⛔ THE APP NEVER CALLS A MARKET API ITSELF. It asks `mainnet-api.soqu.org`
/// for a rate the company already fetched and cached, and nothing else. Going
/// to a market API direct would put a request from every wallet, on every
/// poll, in front of a third party — a usage signal the company does not need
/// to leak and cannot control the retention of. One cached route also means
/// one rate limit instead of one per install.
///
/// The request names no address, no balance and no transaction. It asks what a
/// SOQ is worth and carries nothing else.
///
/// Nothing the wallet DOES is derived from the answer: amounts, fees and coin
/// selection stay in koinu. A price the app cannot read is simply not shown,
/// never a fallback zero.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/fiat_currency.dart';

/// The company's API. Already on the host allowlist in lite_scope_test.dart.
const String kPriceApiHost = 'mainnet-api.soqu.org';

/// The cached-rate route.
const String kPricePath = '/api/v1/price';

/// How often the poll asks for a fresh rate.
const Duration pricePollPeriod = Duration(minutes: 5);

/// How long a rate may go unrefreshed before the app stops showing it.
///
/// The route carries its own [SoqPrice.stale] flag and that is decisive, but
/// a route that stops answering entirely cannot set a flag. This is the
/// backstop for that case: rather than leave a stale number on screen for
/// ever, the money line disappears and the SOQ figure, which is always
/// correct, stands on its own.
const Duration priceMaxAge = Duration(minutes: 30);

/// How long the app waits for the route before giving up on a tick.
const Duration _timeout = Duration(seconds: 8);

/// A rate as the company's route last published it.
@immutable
class SoqPrice {
  /// Whether [amount] holds a real rate.
  final bool available;

  /// The currency [amount] is denominated in.
  final FiatCurrency currency;

  /// Units of [currency] per 1 SOQ. Null when [available] is false.
  final double? amount;

  /// The route's 24-hour average.
  ///
  /// ⛔ PARSED, NEVER RENDERED. It is kept because the route sends it and
  /// throwing away a field makes the model lie about the wire shape, but no
  /// widget may show it: this wallet carries no change figure and no chart.
  final double? average24h;

  /// Where the route got the rate — shown to the owner beside the figure, so
  /// a number on a wallet screen is never presented as the wallet's own
  /// opinion of what their coins are worth.
  final String? source;

  /// When the ROUTE fetched the rate, not when this app received it. The age
  /// the owner is shown is measured from here, because that is the age of the
  /// information rather than the age of the request.
  final DateTime fetchedAt;

  /// The route's own judgement that what it is serving is out of date.
  final bool stale;

  const SoqPrice({
    required this.available,
    required this.currency,
    required this.amount,
    required this.average24h,
    required this.source,
    required this.fetchedAt,
    required this.stale,
  });

  /// No rate: the route did not answer, or answered unusably.
  const SoqPrice.unavailable(DateTime at,
      {FiatCurrency currency = FiatCurrency.usd})
      : this(
            available: false,
            currency: currency,
            amount: null,
            average24h: null,
            source: null,
            fetchedAt: at,
            stale: true);

  /// How old the rate is at [now], by the route's own fetch time.
  Duration ageAt(DateTime now) => now.difference(fetchedAt).abs();

  /// Whether this rate may be shown: it exists, the route does not call it
  /// stale, and it has not aged past [priceMaxAge] while the route was quiet.
  bool isFresh(DateTime now) =>
      available && !stale && ageAt(now) < priceMaxAge;

  /// What [soq] coins are worth at this rate. Null when there is no rate to
  /// apply, so callers render nothing rather than a zero.
  double? valueOf(double soq) {
    final p = amount;
    if (p == null) return null;
    final v = soq * p;
    return v.isFinite ? v : null;
  }
}

/// One GET on the company's cached-rate route, in [currency].
///
/// Never throws. Every failure shape — no network, a timeout, a 5xx, an error
/// page, a body in an unexpected shape, a non-positive rate, a rate quoted in
/// a currency other than the one asked for or in none, a missing fetch time
/// or stale flag — returns [SoqPrice.unavailable],
/// because the caller's only two states are "show the figure" and "don't".
Future<SoqPrice> fetchSoqPrice({
  http.Client? client,
  FiatCurrency currency = FiatCurrency.usd,
}) async {
  final c = client ?? http.Client();
  final now = DateTime.now();
  try {
    final r = await c.get(
      Uri.https(kPriceApiHost, kPricePath, {'currency': currency.code}),
      headers: const {'Accept': 'application/json'},
    ).timeout(_timeout);

    if (r.statusCode != 200) {
      debugPrint('PRICE: route answered ${r.statusCode}');
      return SoqPrice.unavailable(now, currency: currency);
    }

    final body = jsonDecode(r.body);
    if (body is! Map) return SoqPrice.unavailable(now, currency: currency);

    final amount = _positiveDouble(body['price']);
    if (amount == null) return SoqPrice.unavailable(now, currency: currency);

    // ⛔ The route states what it quoted in. If that is not what was asked
    // for, the figure is withheld rather than shown under the wrong symbol:
    // a dollar number behind a euro sign is worse than no number.
    // Compared as the route wrote it, not through FiatCurrency.fromCode:
    // that falls back to USD for a stored preference, so 'btc' or a missing
    // code would pass for dollars.
    final quoted = body['currency'];
    if (quoted is! String || quoted.trim().toLowerCase() != currency.code) {
      debugPrint('PRICE: asked ${currency.code}, got $quoted');
      return SoqPrice.unavailable(now, currency: currency);
    }

    // The age the owner is shown, and the backstop that withdraws a quiet
    // rate, both run from the route's fetch time, and the route's own stale
    // flag is decisive. Without a fetch time the rate would look fresh on
    // every poll, and a non-boolean flag would read as "not stale": either
    // one missing makes the answer unusable.
    final fetchedAt = _time(body['fetched_at']);
    final stale = body['stale'];
    if (fetchedAt == null || stale is! bool) {
      debugPrint('PRICE: no usable fetched_at or stale flag');
      return SoqPrice.unavailable(now, currency: currency);
    }

    return SoqPrice(
      available: true,
      currency: currency,
      amount: amount,
      average24h: _positiveDouble(body['average_24h']),
      source: (body['source'] as String?)?.trim(),
      fetchedAt: fetchedAt,
      stale: stale,
    );
  } catch (e) {
    debugPrint('PRICE: $e');
    return SoqPrice.unavailable(now, currency: currency);
  } finally {
    if (client == null) c.close();
  }
}

double? _positiveDouble(dynamic raw) {
  final v = raw is num ? raw.toDouble() : null;
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

DateTime? _time(dynamic raw) {
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  if (raw is num) {
    // Seconds or milliseconds since the epoch, told apart by magnitude.
    final n = raw.toInt();
    return DateTime.fromMillisecondsSinceEpoch(
        n > 100000000000 ? n : n * 1000);
  }
  return null;
}
