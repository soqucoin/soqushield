import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/utxo.dart';
import '../models/transaction.dart';
import '../models/wallet_keys.dart';
import 'rpc_service.dart';
import 'secure_storage_service.dart' show kSharedSecureStorage;

/// Manages UTXO tracking for the wallet.
///
/// Since Soqucoin (Dogecoin-derived) doesn't expose `scantxoutset` or
/// `listunspent` via public RPC, UTXOs are tracked client-side:
///   1. When we receive a tx, we add the UTXO
///   2. When we spend a tx, we remove the consumed UTXOs and add change
///   3. Each UTXO is verified against the node via `gettxout` before spending
///
/// For initial wallet recovery (restore from seed), a future block explorer
/// integration will scan historical transactions.
class UtxoService {
  final RpcService _rpc;
  final FlutterSecureStorage _storage;

  /// Current network — determines storage partition.
  SoqNetwork _network;

  /// Network-aware storage key to isolate UTXOs per network.
  String get _storageKey => 'soq_utxo_set_${_network.name}';

  /// In-memory UTXO set.
  final List<Utxo> _utxos = [];

  /// SB-8: outpoints ("txid:vout") reserved for an in-flight send. TRANSIENT —
  /// never persisted, so a crash/restart clears all reservations (no risk of
  /// permanently stranding coins).
  final Set<String> _reserved = {};

  UtxoService(this._rpc, {FlutterSecureStorage? storage, SoqNetwork network = SoqNetwork.stagenet})
      : _storage = storage ?? kSharedSecureStorage,
        _network = network;

  /// Switch network partition. Clears in-memory UTXOs and reloads
  /// from the new network's storage key.
  Future<void> setNetwork(SoqNetwork network) async {
    if (network == _network) return;
    _network = network;
    _utxos.clear();
    await load();
    debugPrint('UtxoService: Switched to ${network.name} '
        '(${_utxos.length} UTXOs loaded)');
  }

  /// Set network partition without reloading — use during boot when
  /// [load] is called separately immediately after.
  void setNetworkSync(SoqNetwork network) {
    _network = network;
  }

  /// All tracked UTXOs for the current wallet.
  List<Utxo> get utxos => List.unmodifiable(_utxos);

  /// Spendable UTXOs (unlocked + confirmed + not reserved for an in-flight send).
  List<Utxo> get spendable =>
      _utxos.where((u) =>
          !u.locked &&
          u.confirmations >= 1 &&
          !_reserved.contains('${u.txid}:${u.vout}')).toList();

  /// SB-8: reserve UTXOs (by outpoint) so a concurrent selection skips them.
  void reserveUtxos(Iterable<Utxo> utxos) {
    for (final u in utxos) {
      _reserved.add('${u.txid}:${u.vout}');
    }
  }

  /// SB-8: release a prior reservation — call on send completion OR failure.
  void releaseUtxos(Iterable<Utxo> utxos) {
    for (final u in utxos) {
      _reserved.remove('${u.txid}:${u.vout}');
    }
  }

  /// Spendable SOQ-only UTXOs.
  List<Utxo> get spendableSoq =>
      spendable.where((u) => u.isSoq).toList();

  /// Spendable USDSOQ-only UTXOs.
  List<Utxo> get spendableUsdsoq =>
      spendable.where((u) => u.isUsdsoq).toList();

  /// Total confirmed balance in SOQ (all assets combined).
  double get balance => Utxo.totalValue(spendable);

  /// Total confirmed balance in koinu (all assets combined).
  int get balanceSat => Utxo.totalValueSat(spendable);

  /// SOQ-only balance.
  double get soqBalance => Utxo.totalValue(spendableSoq);

  /// SOQ-only balance in koinu.
  int get soqBalanceSat => Utxo.totalValueSat(spendableSoq);

  /// USDSOQ balance.
  double get usdsoqBalance => Utxo.totalValue(spendableUsdsoq);

  /// Total unconfirmed balance (0-conf UTXOs).
  double get pendingBalance =>
      Utxo.totalValue(_utxos.where((u) => u.confirmations == 0).toList());

  /// Load UTXO set from secure storage.
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return;

      final list = json.decode(raw) as List<dynamic>;
      _utxos.clear();
      _utxos.addAll(list.map(
          (j) => Utxo.fromJson(j as Map<String, dynamic>)));
      debugPrint('UtxoService: Loaded ${_utxos.length} UTXOs');
      await _healAssetTags();
    } catch (e) {
      debugPrint('UtxoService: Load error: $e');
    }
  }

  /// Heal asset tags corrupted by the old gettxout field-name mismatch
  /// (bead y60): a definitive witness program in the stored scriptPubKey
  /// (v7 = USDSOQ, v1 = SOQ) overrides a contradicting persisted tag.
  Future<void> _healAssetTags() async {
    var healed = 0;
    for (var i = 0; i < _utxos.length; i++) {
      final u = _utxos[i];
      final definitive = _definitiveAssetFromScript(u.scriptPubKey);
      if (definitive != null && u.assetType != definitive) {
        debugPrint('UtxoService: Healing asset tag for ${u.outpoint}: '
            '${u.assetType.name} → ${definitive.name}');
        _utxos[i] = u.copyWith(assetType: definitive);
        healed++;
      }
    }
    if (healed > 0) {
      await save();
      debugPrint('UtxoService: Healed $healed corrupted asset tags');
    }
  }

  /// Test hook for the heal pass (normally runs inside [load]).
  @visibleForTesting
  Future<void> debugHealAssetTags() => _healAssetTags();

  /// Persist UTXO set to secure storage.
  Future<void> save() async {
    try {
      final raw = json.encode(_utxos.map((u) => u.toJson()).toList());
      await _storage.write(key: _storageKey, value: raw);
    } catch (e) {
      debugPrint('UtxoService: Save error: $e');
    }
  }

  /// Verify all tracked UTXOs against the node.
  /// Removes spent UTXOs and updates confirmations + asset type from chain.
  ///
  /// Q1 COMPLIANCE: assetType is set from the node's `gettxout` response,
  /// not from client-side cache. The blockchain is the source of truth for
  /// asset classification (SOQ vs USDSOQ). This makes the app self-healing —
  /// a fresh install or cache wipe recovers USDSOQ balances automatically.
  ///
  /// [cancelled] is read after every awaited node answer and before the save:
  /// a network switch or a wipe during the verification must leave the set
  /// as it found it. The pass walks a copy of the set, since a switch clears
  /// the live list under it.
  Future<void> refresh({bool Function()? cancelled}) async {
    final toRemove = <Utxo>[];
    var updated = false;
    bool stop() => cancelled?.call() ?? false;

    for (final utxo in List.of(_utxos)) {
      try {
        final result = await _rpc.getTxOut(utxo.txid, utxo.vout);
        if (stop()) return;
        if (result == null) {
          // UTXO no longer exists — it was spent
          toRemove.add(utxo);
        } else {
          // Update confirmations AND asset type from chain (source of truth).
          // gettxout emits all-lowercase `assettype` (unlike camelCase
          // getrawtransaction) — read both, OR'd with script-level v7
          // detection. With no chain evidence at all, PRESERVE the local
          // tag: defaulting to SOQ here re-tagged every USDSOQ UTXO and
          // stuck (bead y60).
          final confs = result['confirmations'] as int? ?? 0;
          final assetRaw =
              (result['assettype'] ?? result['assetType']) as int?;
          final spkHex = ((result['scriptPubKey']
                  as Map<String, dynamic>?)?['hex'] as String?) ??
              utxo.scriptPubKey;
          final chainAssetType = (assetRaw == null && spkHex.isEmpty)
              ? utxo.assetType
              : classifyAsset(assetRaw, spkHex);
          final idx = _utxos.indexOf(utxo);
          if (idx >= 0) {
            final needsUpdate = utxo.confirmations != confs ||
                                utxo.assetType != chainAssetType;
            if (needsUpdate) {
              _utxos[idx] = utxo.copyWith(
                confirmations: confs,
                assetType: chainAssetType,
              );
              updated = true;
              if (utxo.assetType != chainAssetType) {
                debugPrint('UtxoService: Asset type corrected for '
                    '${utxo.outpoint}: ${utxo.assetType.name} → '
                    '${chainAssetType.name}');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('UtxoService: Refresh error for ${utxo.outpoint}: $e');
      }
    }

    if (stop()) return;
    for (final u in toRemove) {
      _utxos.remove(u);
    }

    if (toRemove.isNotEmpty || updated) {
      if (toRemove.isNotEmpty) {
        debugPrint('UtxoService: Pruned ${toRemove.length} spent UTXOs');
      }
      await save();
    }
  }

  /// Add a UTXO to the tracked set (e.g., after receiving a payment).
  Future<void> addUtxo(Utxo utxo) async {
    final idx = _utxos.indexWhere(
        (u) => u.txid == utxo.txid && u.vout == utxo.vout);
    if (idx >= 0) {
      // Already tracked — but update confirmations if newer data is available.
      // This ensures bridge-minted UTXOs (initially 0-conf) get promoted
      // when ElectrumX later returns the same UTXO with a block height.
      if (utxo.confirmations > _utxos[idx].confirmations) {
        _utxos[idx] = _utxos[idx].copyWith(confirmations: utxo.confirmations);
        await save();
      }
      return;
    }
    _utxos.add(utxo);
    await save();
  }

  /// Remove a UTXO from the tracked set (e.g., after spending).
  Future<void> removeUtxo(String txid, int vout) async {
    _utxos.removeWhere((u) => u.txid == txid && u.vout == vout);
    await save();
  }

  /// Record the result of a sent transaction:
  ///   - Remove consumed inputs from UTXO set
  ///   - Add any change outputs to UTXO set
  Future<void> recordSentTransaction(
    SoqTransaction tx,
    String myAddress,
  ) async {
    // Remove spent UTXOs (inputs)
    for (final input in tx.inputs) {
      _utxos.removeWhere(
          (u) => u.txid == input.txid && u.vout == input.vout);
    }

    // Add change outputs (any output back to our address)
    for (final output in tx.outputs) {
      if (output.addresses.contains(myAddress)) {
        final changeUtxo = Utxo(
          txid: tx.txid,
          vout: output.n,
          value: output.value,
          valueSat: output.valueSat,
          scriptPubKey: output.scriptPubKey,
          address: myAddress,
          confirmations: 0, // Just broadcast
          assetType: _assetTypeFromInt(output.assetType),
          visibility: _visibilityFromInt(output.visibility),
        );
        _utxos.add(changeUtxo);
      }
    }

    await save();
    debugPrint('UtxoService: Recorded tx ${tx.txid.substring(0, 12)}...');
  }

  /// Record a received transaction.
  /// Scans outputs for our address and adds matching UTXOs.
  Future<void> recordReceivedTransaction(
    SoqTransaction tx,
    String myAddress,
  ) async {
    for (final output in tx.outputs) {
      if (output.addresses.contains(myAddress)) {
        final utxo = Utxo(
          txid: tx.txid,
          vout: output.n,
          value: output.value,
          valueSat: output.valueSat,
          scriptPubKey: output.scriptPubKey,
          address: myAddress,
          confirmations: tx.confirmations,
          assetType: classifyAsset(output.assetType, output.scriptPubKey),
          visibility: _visibilityFromInt(output.visibility),
        );
        await addUtxo(utxo);
      }
    }
  }

  /// Select UTXOs for spending the given amount (in koinu).
  /// Uses a simple largest-first selection with target overshoot.
  ///
  /// Returns null if insufficient funds.
  List<Utxo>? selectUtxos(int targetSat, int feeSat,
      {AssetType assetType = AssetType.soq}) {
    final needed = targetSat + feeSat;
    final available = List<Utxo>.from(
      spendable.where((u) => u.assetType == assetType),
    )..sort((a, b) => b.valueSat.compareTo(a.valueSat)); // largest first

    final selected = <Utxo>[];
    var accumulated = 0;

    for (final utxo in available) {
      selected.add(utxo);
      accumulated += utxo.valueSat;
      if (accumulated >= needed) return selected;
    }

    // Insufficient funds
    return null;
  }

  /// Merge remote UTXOs with local state.
  ///
  /// ── Asset tags come from the remote source, which is authoritative ──
  /// The v2 REST bridge (`/api/v2/utxos`) classifies each UTXO by the
  /// scripthash it lives at — v1 = SOQ, v7-rekeyed = USDSOQ — which is the
  /// definition of the asset model, so [getUtxos]'s assetType is ground truth.
  ///
  /// This supersedes the old "F1 FIX: preserve local assetType" behaviour.
  /// Preserving the local tag turned a transient mislabel into a permanent one:
  /// if a freshly-minted USDSOQ (v7) UTXO was ever synced while it was tagged
  /// SOQ (the bridge's now-fixed n_asset_type lag), the preserve branch kept it
  /// SOQ forever, so coin selection found no USDSOQ inputs and every post-swap
  /// USDSOQ send failed with "insufficient funds" while the balance displayed
  /// correctly (bead usdsoq-send-post-swap-assettag). Reconciling toward remote
  /// self-heals any wallet already stuck in that state on its next sync.
  Future<void> syncFromRemote(List<Utxo> remoteUtxos) async {
    // Build a set of remote outpoints for fast lookup
    final remoteSet = <String>{};
    for (final u in remoteUtxos) {
      remoteSet.add('${u.txid}:${u.vout}');
    }

    // Remove local UTXOs that are no longer in the remote set (spent)
    _utxos.removeWhere((local) {
      final key = '${local.txid}:${local.vout}';
      if (!remoteSet.contains(key)) {
        debugPrint('UtxoService: Pruning spent UTXO ${local.outpoint} '
            '(${local.assetType.name})');
        return true;
      }
      return false;
    });

    // Add/update from remote
    for (final remote in remoteUtxos) {
      final idx = _utxos.indexWhere(
          (u) => u.txid == remote.txid && u.vout == remote.vout);
      if (idx >= 0) {
        // Already tracked — update confirmations, and reconcile the asset tag
        // (+ its matching scriptPubKey) toward the authoritative remote value.
        final local = _utxos[idx];
        if (local.assetType != remote.assetType) {
          debugPrint('UtxoService: Correcting asset tag for ${local.outpoint}: '
              '${local.assetType.name} → ${remote.assetType.name}');
        }
        _utxos[idx] = local.copyWith(
          confirmations: remote.confirmations,
          assetType: remote.assetType,
          scriptPubKey: remote.scriptPubKey,
        );
      } else {
        // New UTXO — add with remote's (authoritative) asset type.
        _utxos.add(remote);
      }
    }

    await save();
    debugPrint('UtxoService: Synced from ElectrumX — ${_utxos.length} UTXOs '
        '(${spendableUsdsoq.length} USDSOQ, ${spendableSoq.length} SOQ)');
  }

  /// Wipe all tracked UTXOs.
  Future<void> clear() async {
    _utxos.clear();
    await _storage.delete(key: _storageKey);
  }

  /// Wipe every network's partition through this instance. Its items were
  /// written with this instance's options, so a delete from here matches
  /// them on every platform; a `deleteAll` from another instance may not.
  Future<void> clearAll() async {
    _utxos.clear();
    for (final n in SoqNetwork.values) {
      await _storage.delete(key: 'soq_utxo_set_${n.name}');
    }
  }
}

// ── Helpers ──

AssetType _assetTypeFromInt(int raw) => raw == 1 ? AssetType.usdsoq : AssetType.soq;
UtxoVisibility _visibilityFromInt(int raw) => raw == 1 ? UtxoVisibility.confidential : UtxoVisibility.transparent;

/// A 34-byte witness program pins the asset: OP_7 = USDSOQ, OP_1 = SOQ.
/// Anything else (empty/unknown script) is not definitive evidence.
AssetType? _definitiveAssetFromScript(String hex) {
  if (hex.length != 68) return null;
  if (hex.startsWith('5720')) return AssetType.usdsoq;
  if (hex.startsWith('5120')) return AssetType.soq;
  return null;
}
