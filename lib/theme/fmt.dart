// Numeral discipline (design audit 2026-07-05 §5): one voice for numbers.
import 'package:intl/intl.dart';

final _n0 = NumberFormat('#,##0');
final _n2 = NumberFormat('#,##0.00');

/// Whole-number counts: block heights, peer counts, raw token counts.
String fmtInt(num v) => _n0.format(v);

/// Monetary/asset amounts: always 2dp, thousands separators.
String fmtAmount(num v) => _n2.format(v);
