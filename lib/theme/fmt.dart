// Numeral discipline (design audit 2026-07-05 §5): one voice for numbers.
import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/fiat_currency.dart';

final _n0 = NumberFormat('#,##0');
final _n2 = NumberFormat('#,##0.00');

/// Whole-number counts: block heights, peer counts, raw token counts.
String fmtInt(num v) => _n0.format(v);

/// Monetary/asset amounts: always 2dp, thousands separators.
String fmtAmount(num v) => _n2.format(v);

/// A money figure in [currency], at the precision the figure actually needs.
///
/// One minor unit and up is the ordinary money voice — the currency's own
/// decimal places with thousands separators ($15.98, €1,234.56, ¥2,410).
/// Below that the voice changes: SOQ trades in fractions of a cent, so a small
/// holding at 2dp reads "$0.00", which says "worthless" rather than "small".
/// Under one minor unit this widens to two significant digits instead
/// ($0.0016, $0.00016), so a real balance always shows a real number. Exactly
/// zero keeps the ordinary voice — that one IS zero.
///
/// [compact] flips that rule for figures where the precision is noise rather
/// than information. A BALANCE under a cent is worth stating exactly — it is
/// the owner's money and they may want the real number. A COST under a cent is
/// not: "$0.0000012" beside a fee tells nobody anything, where "<$0.01" says
/// the one thing they wanted to know. Use [compact] for fees and costs.
String fmtMoney(num v, FiatCurrency currency, {bool compact = false}) {
  final value = v.toDouble();
  if (!value.isFinite) return '—';
  final a = value.abs();
  final sign = value < 0 ? '−' : '';
  final sym = currency.symbol;

  // One minor unit: 0.01 where there are cents, 1 where there are none.
  final unit = math.pow(10, -currency.minorDigits).toDouble();

  if (a == 0 || a >= unit) {
    final digits = currency.minorDigits;
    final f = digits == 2
        ? _n2
        : NumberFormat('#,##0${digits > 0 ? '.${'0' * digits}' : ''}');
    return '$sign$sym${f.format(a)}';
  }

  if (compact) return '<$sym${unit.toStringAsFixed(currency.minorDigits)}';

  // Two significant digits: for 0.0016 the first digit sits at 1e-3, so 4dp.
  // Capped at 8dp — a koinu is 1e-8 SOQ, so nothing meaningful lives below it.
  final dp = math.min(8, 1 - (math.log(a) / math.ln10).floor());
  return '$sign$sym${a.toStringAsFixed(dp)}';
}

/// [fmtMoney] in US dollars. Kept for the call sites that are dollars by
/// definition; everything the owner sees goes through [fmtMoney] with their
/// chosen currency.
String fmtUsd(num v, {bool compact = false}) =>
    fmtMoney(v, FiatCurrency.usd, compact: compact);

/// A percentage change, signed, 1dp — "+24.4%", "−3.2%", "0.0%".
///
/// The minus is U+2212, not a hyphen: at mono-font telemetry sizes a hyphen
/// reads as a dash in the middle of a number.
String fmtPct(num v) {
  final value = v.toDouble();
  if (!value.isFinite) return '—';
  final sign = value > 0 ? '+' : (value < 0 ? '−' : '');
  return '$sign${value.abs().toStringAsFixed(1)}%';
}

/// The masked stand-in for a hidden figure, in [currency]'s voice — "$••••".
/// Hiding a balance has to hide its money figure too, or the one hands the
/// other straight back.
String maskedMoney(FiatCurrency currency) => '${currency.symbol}••••';

/// The masked stand-in for a hidden SOQ amount.
const String maskedAmount = '••••';
