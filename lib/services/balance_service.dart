import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/utxo.dart';
import '../models/wallet_keys.dart';

/// Service for querying wallet data from the ElectrumX-backed REST API.
///
/// This replaces the legacy wallet-API balance endpoint
/// and the broken `listunspent` RPC discovery. The backend is a zero-dependency
/// Node.js service bridging REST ↔ ElectrumX TCP, deployed via Cloudflare Worker
/// for SSL + DDoS protection.
///
/// Architecture:
///   SoquShield → Cloudflare Worker → Node.js REST bridge → ElectrumX → soqucoind
///
/// Phase B1: Network-aware. URLs are derived from [SoqNetwork] and switch
/// when the user toggles between Stagenet and Mainnet in Settings.
class BalanceService {
  // Shared HTTP client (prevents socket leaks per F07)
  final http.Client _client;

  // Network-aware endpoints — set via setNetwork()
  String _primaryBaseUrl;
  String _fallbackBaseUrl;

  BalanceService({
    http.Client? client,
    SoqNetwork network = SoqNetwork.stagenet,
  })  : _client = client ?? http.Client(),
        _primaryBaseUrl = network.electrumApiUrl,
        _fallbackBaseUrl = network.electrumFallbackUrl;

  /// Switch network — updates both primary and fallback URLs.
  /// Follows the same pattern as RpcService.setNetwork().
  void setNetwork(SoqNetwork network) {
    _primaryBaseUrl = network.electrumApiUrl;
    _fallbackBaseUrl = network.electrumFallbackUrl;
    debugPrint('BalanceService: Switched to ${network.displayName} '
        '(primary: $_primaryBaseUrl)');
  }

  /// Fetch SOQ and USDSOQ balances SEPARATELY for any Bech32m address.
  ///
  /// SB-F3: the legacy `/api/v2/balance` endpoint returns `confirmed_soq`
  /// SUMMED across SOQ+USDSOQ, which inflated the SOQ headline and double-counted
  /// USDSOQ (also shown in its own tile). `/api/v2/multi-balance` keeps the two
  /// assets separate:
  ///   soq.confirmed_soq        → SOQ headline
  ///   usdsoq.confirmed_usdsoq  → USDSOQ tile
  /// No `importaddress` needed — ElectrumX indexes ALL addresses.
  Future<BalanceResult> getBalance(String address) async {
    final data = await _get('/api/v2/multi-balance/$address');
    final soq = (data['soq'] as Map<String, dynamic>?) ?? const {};
    final usdsoq = (data['usdsoq'] as Map<String, dynamic>?) ?? const {};
    return BalanceResult(
      confirmedSat: soq['confirmed'] as int? ?? 0,
      unconfirmedSat: soq['unconfirmed'] as int? ?? 0,
      confirmedSoq: (soq['confirmed_soq'] as num?)?.toDouble() ?? 0,
      unconfirmedSoq: (soq['unconfirmed_soq'] as num?)?.toDouble() ?? 0,
      confirmedUsdsoq: (usdsoq['confirmed_usdsoq'] as num?)?.toDouble() ?? 0,
      unconfirmedUsdsoq: (usdsoq['unconfirmed_usdsoq'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Fetch all UTXOs for an address — ready for coin selection.
  /// Returns a list of [Utxo] objects compatible with [UtxoService].
  Future<List<Utxo>> getUtxos(String address) async {
    final data = await _get('/api/v2/utxos/$address');
    final utxoList = data['utxos'] as List<dynamic>? ?? [];

    // Derive the scriptPubKey from the Bech32m address.
    // For witness v1: OP_1 (0x51) + PUSH_32 (0x20) + 32-byte program.
    // This is deterministic — we don't need ElectrumX to return it.
    final spkHex = _addressToScriptPubKeyHex(address);
    // A USDSOQ holding for this address lives at the v7-rekeyed script
    // (OP_7 0x57 + same program). The spending sighash's scriptCode is the
    // input's scriptPubKey, and the node verifies against the real on-chain v7
    // script — so a USDSOQ (v7) UTXO MUST carry the v7 SPK, not the v1 one, or
    // its signature won't validate. (Byte-less CTxOut: asset = witness version.)
    final v7SpkHex = '57${spkHex.substring(2)}';

    return utxoList.map((u) {
      final map = u as Map<String, dynamic>;
      // Forward-compatible: read assetType if the ElectrumX REST bridge
      // returns it (0x00 = SOQ, 0x01 = USDSOQ). Defaults to SOQ if absent.
      final rawAssetType = map['assetType'] as int?;
      final assetType = rawAssetType == 1 ? AssetType.usdsoq : AssetType.soq;
      return Utxo(
        txid: map['txid'] as String,
        vout: map['vout'] as int,
        value: (map['value_soq'] as num).toDouble(),
        valueSat: map['value'] as int,
        scriptPubKey: assetType == AssetType.usdsoq ? v7SpkHex : spkHex,
        address: address,
        confirmations: map['height'] != null && (map['height'] as int) > 0 ? 1 : 0,
        assetType: assetType,
      );
    }).toList();
  }

  /// Fetch a transaction's raw hex — parsed locally to rebuild history
  /// after a seed restore (bead m4f P2).
  Future<String> getRawTransaction(String txid) async {
    final data = await _get('/api/v2/tx/$txid');
    final raw = data['data'] as String?;
    if (raw == null || raw.isEmpty) {
      throw Exception('empty raw tx for $txid');
    }
    return raw;
  }

  /// Fetch full transaction history for the Activity feed.
  Future<List<TxHistoryEntry>> getHistory(String address) async {
    final data = await _get('/api/v2/history/$address');
    final txList = data['transactions'] as List<dynamic>? ?? [];
    return txList.map((t) {
      final map = t as Map<String, dynamic>;
      return TxHistoryEntry(
        txid: map['txid'] as String,
        height: map['height'] as int? ?? 0,
        confirmed: map['confirmed'] as bool? ?? false,
      );
    }).toList();
  }

  /// Get current chain tip height.
  Future<int> getChainTip() async {
    final data = await _get('/api/v2/tip');
    return data['height'] as int? ?? 0;
  }

  /// Broadcast a raw signed transaction.
  Future<String> broadcastTx(String rawTxHex) async {
    final response = await _client.post(
      Uri.parse('$_primaryBaseUrl/api/v2/tx/broadcast'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'raw_tx': rawTxHex}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['txid'] as String;
    }
    throw Exception('Broadcast failed: ${response.statusCode} ${response.body}');
  }

  /// Check API health (ElectrumX connectivity).
  Future<bool> isHealthy() async {
    try {
      final data = await _get('/health');
      return data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Internal: GET with primary/fallback and timeout.
  Future<Map<String, dynamic>> _get(String path) async {
    // Try primary (Cloudflare Worker)
    try {
      final response = await _client.get(
        Uri.parse('$_primaryBaseUrl$path'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('BalanceService: Primary failed ($path): $e');
    }

    // Fallback to direct VPS
    try {
      final response = await _client.get(
        Uri.parse('$_fallbackBaseUrl$path'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('BalanceService: Fallback also failed ($path): $e');
    }

    throw Exception('BalanceService: All backends unreachable for $path');
  }

  /// Convert a Bech32m address (ssq1p...) to a scriptPubKey hex string.
  ///
  /// For witness v1: OP_1 (0x51) + PUSH_32 (0x20) + 32-byte witness program.
  /// This is deterministic — the same address always produces the same
  /// scriptPubKey, so we don't need ElectrumX or the node to tell us.
  ///
  /// Used by getUtxos() to populate the scriptPubKey field that TxBuilder
  /// needs for sighash computation during transaction signing.
  static String _addressToScriptPubKeyHex(String address) {
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final pos = address.lastIndexOf('1');
    final data = address
        .substring(pos + 1)
        .split('')
        .map((c) => charset.indexOf(c))
        .toList();

    // Remove checksum (last 6 chars)
    final payload = data.sublist(0, data.length - 6);

    // Convert from 5-bit to 8-bit (skip witness version byte)
    final witnessVersion = payload[0];
    final program = _convertBits(payload.sublist(1), 5, 8, pad: false);

    // Build scriptPubKey: OP_<version> PUSH_<len> <program>
    final opVersion = witnessVersion == 0 ? 0x00 : 0x50 + witnessVersion;
    final bytes = [opVersion, program.length, ...program];

    // Convert to hex string
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convert between bit-width encodings (5-bit Bech32 ↔ 8-bit bytes).
  static List<int> _convertBits(List<int> data, int fromBits, int toBits,
      {bool pad = true}) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad && bits > 0) {
      result.add((acc << (toBits - bits)) & maxv);
    }

    return result;
  }
}

/// Balance query result with both satoshi and SOQ denomination.
class BalanceResult {
  final int confirmedSat;
  final int unconfirmedSat;
  final double confirmedSoq;
  final double unconfirmedSoq;
  // SB-F3: USDSOQ balance, kept SEPARATE from SOQ (from /api/v2/multi-balance).
  final double confirmedUsdsoq;
  final double unconfirmedUsdsoq;

  const BalanceResult({
    required this.confirmedSat,
    required this.unconfirmedSat,
    required this.confirmedSoq,
    required this.unconfirmedSoq,
    this.confirmedUsdsoq = 0,
    this.unconfirmedUsdsoq = 0,
  });

  double get totalSoq => confirmedSoq + unconfirmedSoq;
  int get totalSat => confirmedSat + unconfirmedSat;
}

/// Transaction history entry from ElectrumX.
class TxHistoryEntry {
  final String txid;
  final int height;
  final bool confirmed;

  const TxHistoryEntry({
    required this.txid,
    required this.height,
    required this.confirmed,
  });
}
