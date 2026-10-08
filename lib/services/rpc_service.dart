import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/wallet_keys.dart';

/// JSON-RPC client for the Soqucoin node via the selected network's proxy
/// (`_endpoints`): HTTPS to the proxy, which forwards to soqucoind.
///
/// All methods are safe (read-only or tx broadcast) —
/// dangerous methods are blocked at the Worker layer.
class RpcService {
  /// Production RPC endpoints.
  ///
  /// Both hostnames are permanent. At mainnet launch the mainnet-rpc route is
  /// re-homed from the (decommissioned) simulation worker to the real mainnet
  /// soqucoind, so the app toggle works with zero app store update.
  static const Map<SoqNetwork, String> _endpoints = {
    SoqNetwork.stagenet: 'https://staging-rpc.soqu.org',     // LIVE — stagenet Services VPS
    SoqNetwork.mainnet:  'https://mainnet-rpc.soqu.org',  // permanent mainnet RPC hostname (route re-homes to mainnet soqucoind at launch)
  };

  final http.Client _client;
  SoqNetwork _network;
  int _requestId = 0;

  RpcService({
    http.Client? client,
    SoqNetwork network = SoqNetwork.stagenet,
  })  : _client = client ?? http.Client(),
        _network = network;

  /// Switch network
  void setNetwork(SoqNetwork network) => _network = network;

  /// The currently selected network.
  SoqNetwork get network => _network;

  /// Get the current endpoint URL
  String get endpoint => _endpoints[_network]!;

  /// Endpoint hostname for [network] — display surfaces read THIS so settings
  /// tiles can never drift from what the client actually calls (bead m4f P1).
  static String hostFor(SoqNetwork network) =>
      Uri.parse(_endpoints[network]!).host;

  // ── Blockchain Info ──

  /// Get current block count.
  Future<int> getBlockCount() async {
    final result = await _call('getblockcount');
    return result as int;
  }

  /// Get blockchain info (chain, blocks, headers, difficulty, etc.)
  Future<Map<String, dynamic>> getBlockchainInfo() async {
    final result = await _call('getblockchaininfo');
    return result as Map<String, dynamic>;
  }

  /// Get network info (version, subversion, connections, etc.)
  Future<Map<String, dynamic>> getNetworkInfo() async {
    final result = await _call('getnetworkinfo');
    return result as Map<String, dynamic>;
  }

  /// Get best block hash.
  Future<String> getBestBlockHash() async {
    final result = await _call('getbestblockhash');
    return result as String;
  }

  /// Get current difficulty.
  Future<double> getDifficulty() async {
    final result = await _call('getdifficulty');
    return (result as num).toDouble();
  }

  /// Get mining info (hashrate, blocks, difficulty).
  Future<Map<String, dynamic>> getMiningInfo() async {
    final result = await _call('getmininginfo');
    return result as Map<String, dynamic>;
  }

  /// Get mempool info.
  Future<Map<String, dynamic>> getMempoolInfo() async {
    final result = await _call('getmempoolinfo');
    return result as Map<String, dynamic>;
  }

  // ── Blocks ──

  /// Get block hash by height.
  Future<String> getBlockHash(int height) async {
    final result = await _call('getblockhash', [height]);
    return result as String;
  }

  /// Get block by hash (verbose).
  Future<Map<String, dynamic>> getBlock(String hash, {int verbosity = 1}) async {
    final result = await _call('getblock', [hash, verbosity]);
    return result as Map<String, dynamic>;
  }

  // ── Transactions ──

  /// Get raw transaction by txid.
  Future<Map<String, dynamic>> getRawTransaction(String txid, {bool verbose = true}) async {
    final result = await _call('getrawtransaction', [txid, verbose ? 1 : 0]);
    return result as Map<String, dynamic>;
  }

  /// Broadcast a signed raw transaction hex.
  /// Returns the transaction ID on success.
  Future<String> sendRawTransaction(String txHex) async {
    final result = await _call('sendrawtransaction', [txHex]);
    return result as String;
  }

  /// Decode a raw transaction hex without broadcasting.
  Future<Map<String, dynamic>> decodeRawTransaction(String txHex) async {
    final result = await _call('decoderawtransaction', [txHex]);
    return result as Map<String, dynamic>;
  }

  /// Get a specific UTXO.
  Future<Map<String, dynamic>?> getTxOut(String txid, int vout, {bool includeMempool = true}) async {
    final result = await _call('gettxout', [txid, vout, includeMempool]);
    if (result == null) return null;
    return result as Map<String, dynamic>;
  }

  // ── Fee Estimation ──

  /// Estimate smart fee for confirmation within N blocks.
  /// Returns feerate in SOQ/kB, or -1 if no estimate available.
  Future<double> estimateSmartFee(int confTarget) async {
    final result = await _call('estimatesmartfee', [confTarget]) as Map<String, dynamic>;
    final feerate = result['feerate'];
    // FN-12: when the node has no estimate it returns feerate:-1. The old 0.0001
    // SOQ/kB fallback was ~10× below what is actually charged — tx_builder floors
    // every fee at minrelaytxfee (100000 sat/kB = 0.001 SOQ/kB). Return that
    // floor so the displayed fee matches the amount actually deducted.
    if (feerate == null || feerate == -1) return 0.001; // = minrelaytxfee floor
    return (feerate as num).toDouble();
  }

  // ── Address ──

  /// Validate an address.
  Future<Map<String, dynamic>> validateAddress(String address) async {
    final result = await _call('validateaddress', [address]);
    return result as Map<String, dynamic>;
  }

  // ── Health ──

  /// Check if the RPC proxy is reachable.
  Future<bool> isHealthy() async {
    try {
      final response = await _client.get(
        Uri.parse('$endpoint/health'),
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Core JSON-RPC ──

  /// Low-level JSON-RPC 1.0 call.
  Future<dynamic> _call(String method, [List<dynamic>? params]) async {
    _requestId++;
    final body = json.encode({
      'jsonrpc': '1.0',
      'id': 'soqshield-$_requestId',
      'method': method,
      'params': params ?? [],
    });

    try {
      final response = await _client.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 30));

      // Try to parse JSON body regardless of status code.
      // The node returns error details in the body even on 500.
      Map<String, dynamic>? data;
      try {
        data = json.decode(response.body) as Map<String, dynamic>;
      } catch (_) {
        // Body isn't valid JSON (e.g., nginx error page)
      }

      // If we got a parsed JSON error, use the node's message
      if (data != null && data['error'] != null) {
        final errMsg = data['error']['message'] as String? ?? 'Unknown RPC error';
        final errCode = data['error']['code'] as int? ?? -1;
        throw RpcException(code: errCode, message: errMsg);
      }

      // Non-200 with no parseable error body
      if (response.statusCode != 200 && data == null) {
        throw RpcException(
          code: response.statusCode,
          message: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      return data?['result'];
    } on RpcException {
      rethrow;
    } catch (e) {
      throw RpcException(
        code: -1,
        message: 'Network error: $e',
      );
    }
  }

  /// Dispose the HTTP client.
  void dispose() => _client.close();
}

/// RPC error with code and message.
class RpcException implements Exception {
  final int code;
  final String message;

  const RpcException({required this.code, required this.message});

  @override
  String toString() => 'RpcException($code): $message';
}
