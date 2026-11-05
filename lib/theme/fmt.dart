// Numeral discipline (design audit 2026-07-05 §5): one voice for numbers.
import 'package:intl/intl.dart';

final _n0 = NumberFormat('#,##0');
final _n2 = NumberFormat('#,##0.00');
final _n8 = NumberFormat('#,##0.00######');

/// Whole-number counts: block heights, peer counts, raw token counts.
String fmtInt(num v) => _n0.format(v);

/// Monetary/asset amounts: always 2dp, thousands separators.
String fmtAmount(num v) => _n2.format(v);

/// Below this many SOQ (2^26) adjacent doubles are less than a satoshi apart,
/// so an amount carried as a double rounds back to its exact satoshi at 8dp.
/// At and above it, some satoshi values have no double of their own.
const double kSatoshiExactLimit = 67108864;

/// An asset amount for a detail view: to the satoshi (2 to 8dp) below
/// [kSatoshiExactLimit], and at 2dp, as [fmtAmount], at or above it.
String fmtDetailAmount(num v) =>
    v.abs() < kSatoshiExactLimit ? _n8.format(v) : _n2.format(v);

/// The masked stand-in for a hidden SOQ amount.
const String maskedAmount = '••••';
