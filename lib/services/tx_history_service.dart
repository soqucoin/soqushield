import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wallet_keys.dart';
import '../providers/wallet_provider.dart';

/// F14: Persists transaction history across app restarts.
///
/// Uses SharedPreferences to store recent transactions as JSON.
/// Limited to the last 100 transactions to keep storage bounded.
class TxHistoryService {
  static const _maxEntries = 100;

  /// Current network — determines storage partition.
  static SoqNetwork _network = SoqNetwork.stagenet;

  /// Network-aware storage key to isolate tx history per network.
  static String get _key => 'soqshield_tx_history_${_network.name}';

  /// Switch network partition.
  static void setNetwork(SoqNetwork network) {
    _network = network;
  }

  /// Save a list of transactions to persistent storage.
  ///
  /// The partition is fixed when the call is made, not after the first
  /// await: a network switch while the preferences handle is awaited must
  /// not move rows fetched on one network into the other's partition.
  static Future<void> save(List<WalletTransaction> txs) async {
    final key = _key;
    final prefs = await SharedPreferences.getInstance();
    final entries = txs.take(_maxEntries).map((tx) => {
      'txid': tx.txid,
      'type': tx.type.index,
      'amount': tx.amount,
      'timestamp': tx.timestamp.millisecondsSinceEpoch,
      'confirmations': tx.confirmations,
    }).toList();
    await prefs.setString(key, jsonEncode(entries));
  }

  /// Load previously saved transactions.
  static Future<List<WalletTransaction>> load() async {
    final key = _key;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final List<dynamic> entries = jsonDecode(raw);
      return entries.map((e) => WalletTransaction(
        txid: e['txid'] as String? ?? '',
        type: TxType.values[e['type'] as int? ?? 0],
        amount: (e['amount'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          e['timestamp'] as int? ?? 0,
        ),
        confirmations: e['confirmations'] as int? ?? 0,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Append a new transaction and save.
  static Future<void> append(WalletTransaction tx) async {
    final existing = await load();
    existing.insert(0, tx);
    await save(existing);
  }

  /// Clear all stored transactions (used on wallet wipe).
  static Future<void> clear() async {
    final key = _key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
