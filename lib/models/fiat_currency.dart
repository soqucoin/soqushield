/// The currencies a SOQ balance can be shown in.
///
/// Every code here is one CoinGecko's `simple/price` accepts as a
/// `vs_currencies` value (checked against its supported-currencies endpoint),
/// so adding one is a matter of adding the entry — the price reader passes the
/// code straight through.
///
/// [minorDigits] is how many decimal places the currency's ordinary money
/// voice uses: 2 almost everywhere, 0 for the currencies with no minor unit in
/// daily use (yen, won). It is NOT a display cap — a SOQ balance worth less
/// than one minor unit widens past it rather than reading as zero (see
/// `theme/fmt.dart`).
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

enum FiatCurrency {
  usd('usd', r'$', 'US Dollar'),
  eur('eur', '€', 'Euro'),
  gbp('gbp', '£', 'British Pound'),
  chf('chf', 'CHF ', 'Swiss Franc'),
  jpy('jpy', '¥', 'Japanese Yen', minorDigits: 0),
  cny('cny', 'CN¥', 'Chinese Yuan'),
  inr('inr', '₹', 'Indian Rupee'),
  krw('krw', '₩', 'South Korean Won', minorDigits: 0),
  cad('cad', r'CA$', 'Canadian Dollar'),
  aud('aud', r'A$', 'Australian Dollar'),
  nzd('nzd', r'NZ$', 'New Zealand Dollar'),
  sgd('sgd', r'S$', 'Singapore Dollar'),
  hkd('hkd', r'HK$', 'Hong Kong Dollar'),
  aed('aed', 'AED ', 'UAE Dirham'),
  brl('brl', r'R$', 'Brazilian Real'),
  mxn('mxn', r'MX$', 'Mexican Peso'),
  zar('zar', 'R', 'South African Rand'),
  sek('sek', 'SEK ', 'Swedish Krona'),
  nok('nok', 'NOK ', 'Norwegian Krone'),
  pln('pln', 'zł ', 'Polish Złoty'),
  tryLira('try', '₺', 'Turkish Lira'),
  rub('rub', '₽', 'Russian Ruble');

  const FiatCurrency(this.code, this.symbol, this.label,
      {this.minorDigits = 2});

  /// The ISO-ish code CoinGecko is asked for, lowercase.
  final String code;

  /// What goes in front of the figure. Codes that are not a glyph carry their
  /// own trailing space ("CHF ") so the figure never runs into them.
  final String symbol;

  /// The currency's name, for the picker.
  final String label;

  /// Decimal places in this currency's ordinary money voice.
  final int minorDigits;

  /// The uppercase code, for a label — "USD", "EUR".
  String get display => code.toUpperCase();

  /// The currency stored under [code], or [usd] if it is unknown. Used when
  /// reading a persisted choice, which may name a currency a later build
  /// removed.
  static FiatCurrency fromCode(String? code) => values.firstWhere(
        (c) => c.code == code,
        orElse: () => FiatCurrency.usd,
      );
}
