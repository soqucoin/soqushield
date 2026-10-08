/// XMSS Key Manager — Persistent Vault Key Tree Storage
///
/// Manages the lifecycle of XMSS-Lite key trees:
///   - Generate and store master seed in platform Keychain/Keystore
///   - Track the current leaf_index (one-time key consumption)
///   - Regenerate the full key tree on-demand from the stored seed
///   - Automatic key exhaustion warnings
///
/// Security model:
///   - Master seed: flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences)
///   - Leaf index: flutter_secure_storage (atomic with seed)
///   - Full key tree: held in memory only, regenerated from seed when needed
///   - On wipe: seed is deleted, vault becomes permanently inaccessible
///
/// Patent: SOQ-P004 #64/035,857 (XMSS-Lite Revolving Vault)
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/xmss_tree.dart';

/// Default tree depth — 2^4 = 16 keys (demo). Use 10 for production (1024 keys).
const int kDefaultTreeDepth = 4;

/// Key exhaustion warning threshold — warn when this many keys remain.
const int kKeyExhaustionWarning = 3;

/// Manages XMSS vault key trees with secure persistent storage.
class XmssKeyManager {
  static const _keySeed = 'xmss_vault_seed_v1';
  static const _keyLeafIndex = 'xmss_vault_leaf_index_v1';
  static const _keyTreeDepth = 'xmss_vault_tree_depth_v1';
  static const _keyCreatedAt = 'xmss_vault_created_v1';

  final FlutterSecureStorage _storage;

  /// Cached key tree (memory only — regenerated from seed).
  XmssKeyTree? _cachedTree;

  /// SB-1: serializes leaf-index reservation so two concurrent bridge-outs can
  /// never obtain the same one-time key index.
  Future<void> _reserveMutex = Future<void>.value();

  XmssKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  // ── Vault Lifecycle ────────────────────────────────────────

  /// Check if a vault key tree exists on this device.
  Future<bool> hasVault() async {
    final seed = await _storage.read(key: _keySeed);
    return seed != null && seed.isNotEmpty;
  }

  /// Initialize a new vault key tree.
  ///
  /// Generates a fresh master seed, builds the key tree, persists the seed
  /// and initial leaf index (0) to secure storage.
  ///
  /// Returns the generated key tree (also cached in memory).
  ///
  /// Throws if a vault already exists — call [wipeVault] first if re-creating.
  Future<XmssKeyTree> initializeVault(
      {int depth = kDefaultTreeDepth, Uint8List? masterSeed}) async {
    if (await hasVault()) {
      throw StateError(
        'Vault already exists. Call wipeVault() before re-initializing.',
      );
    }

    // SB-2: derive the tree from the wallet-derived seed when provided so the
    // vault is recoverable from the mnemonic. Falls back to a random seed only
    // when no seed is supplied (legacy path; such a vault is recoverable ONLY
    // via the encrypted backup, never the 24 words).
    final tree = generateXmssTree(depth, masterSeed);

    // Persist seed + metadata
    await _storage.write(
      key: _keySeed,
      value: _bytesToHex(tree.masterSeed),
    );
    await _storage.write(key: _keyLeafIndex, value: '0');
    await _storage.write(key: _keyTreeDepth, value: depth.toString());
    await _storage.write(
      key: _keyCreatedAt,
      value: DateTime.now().toIso8601String(),
    );

    _cachedTree = tree;
    return tree;
  }

  /// Load (or regenerate) the vault key tree.
  ///
  /// The master seed is read from secure storage; the full key tree is
  /// regenerated deterministically in memory. This is intentional —
  /// we never persist private keys, only the seed.
  ///
  /// Returns null if no vault exists.
  Future<XmssKeyTree?> loadVault() async {
    // Return cached tree if available
    if (_cachedTree != null) return _cachedTree;

    final seedHex = await _storage.read(key: _keySeed);
    if (seedHex == null || seedHex.isEmpty) return null;

    final depthStr = await _storage.read(key: _keyTreeDepth);
    final depth = int.tryParse(depthStr ?? '') ?? kDefaultTreeDepth;

    final seed = _hexToBytes(seedHex);
    final tree = generateXmssTree(depth, seed);

    _cachedTree = tree;
    return tree;
  }

  /// Get the current leaf index (next unused key).
  Future<int> getLeafIndex() async {
    final idx = await _storage.read(key: _keyLeafIndex);
    return int.tryParse(idx ?? '0') ?? 0;
  }

  /// SB-1: Atomically RESERVE the next leaf index for a one-time signature.
  ///
  /// A WOTS+/XMSS leaf is single-use — reusing one leaks the vault private key.
  /// So the index is advanced and PERSISTED *before* it is handed out, under a
  /// mutex, and fail-closed: if the persist cannot be confirmed this THROWS and
  /// no index is returned (the caller must not sign). The reserved index is
  /// BURNED regardless of whether the bridge-out later succeeds, fails, or the
  /// app crashes — a skipped leaf is cheap; a reused one is catastrophic.
  /// Callers sign with the returned index and must NOT call [advanceLeafIndex].
  Future<int> reserveLeafIndex() {
    final prev = _reserveMutex;
    final done = Completer<void>();
    _reserveMutex = done.future;
    return prev.then((_) async {
      try {
        final current = await getLeafIndex();

        final depthStr = await _storage.read(key: _keyTreeDepth);
        final depth = int.tryParse(depthStr ?? '') ?? kDefaultTreeDepth;
        if (current >= (1 << depth)) {
          throw StateError(
            'Vault key tree exhausted (leaf $current of ${1 << depth}) — no one-time keys remain',
          );
        }

        final next = current + 1;
        await _storage.write(key: _keyLeafIndex, value: next.toString());

        // Fail-closed: confirm the advance actually persisted before handing the
        // index out. If it didn't, a later sign could reuse `current`.
        final check = await _storage.read(key: _keyLeafIndex);
        if (check != next.toString()) {
          throw StateError(
            'Leaf-index advance did not persist (read back "$check") — '
            'aborting to prevent one-time key reuse',
          );
        }
        return current;
      } finally {
        done.complete();
      }
    });
  }

  /// Deprecated (SB-1): leaf advancement is now atomic with reservation in
  /// [reserveLeafIndex], which burns the index *before* signing. Advancing
  /// *after* a "successful" op left a reuse window on crash/dropped-tx.
  @Deprecated('Use reserveLeafIndex() before signing; do not advance after.')
  Future<int> advanceLeafIndex() async {
    final current = await getLeafIndex();
    final next = current + 1;
    await _storage.write(key: _keyLeafIndex, value: next.toString());
    return next;
  }

  /// Get the number of remaining keys in this vault.
  Future<int> getRemainingKeys() async {
    final depthStr = await _storage.read(key: _keyTreeDepth);
    final depth = int.tryParse(depthStr ?? '') ?? kDefaultTreeDepth;
    final maxKeys = 1 << depth;
    final used = await getLeafIndex();
    return maxKeys - used;
  }

  /// Check if the vault is nearing key exhaustion.
  Future<bool> isKeyExhaustionWarning() async {
    final remaining = await getRemainingKeys();
    return remaining > 0 && remaining <= kKeyExhaustionWarning;
  }

  /// Check if the vault has exhausted all keys.
  Future<bool> isExhausted() async {
    final remaining = await getRemainingKeys();
    return remaining <= 0;
  }

  /// Get the Merkle root (for on-chain vault lookup).
  Future<Uint8List?> getMerkleRoot() async {
    final tree = await loadVault();
    return tree?.merkleRoot;
  }

  /// Get vault metadata for display.
  Future<VaultInfo?> getVaultInfo() async {
    if (!await hasVault()) return null;

    final leafIndex = await getLeafIndex();
    final remaining = await getRemainingKeys();
    final depthStr = await _storage.read(key: _keyTreeDepth);
    final depth = int.tryParse(depthStr ?? '') ?? kDefaultTreeDepth;
    final createdStr = await _storage.read(key: _keyCreatedAt);
    final tree = await loadVault();

    return VaultInfo(
      merkleRoot: tree?.merkleRoot,
      leafIndex: leafIndex,
      maxKeys: 1 << depth,
      remainingKeys: remaining,
      treeDepth: depth,
      createdAt: createdStr != null ? DateTime.tryParse(createdStr) : null,
      isExhausted: remaining <= 0,
      isWarning: remaining > 0 && remaining <= kKeyExhaustionWarning,
    );
  }

  // ── Danger Zone ────────────────────────────────────────────

  /// Wipe the vault from this device. IRREVERSIBLE.
  ///
  /// The master seed is deleted from secure storage. Any pSOQ still
  /// in the on-chain vault becomes permanently inaccessible.
  ///
  /// Only call this when the vault is empty (all pSOQ withdrawn).
  Future<void> wipeVault() async {
    await _storage.delete(key: _keySeed);
    await _storage.delete(key: _keyLeafIndex);
    await _storage.delete(key: _keyTreeDepth);
    await _storage.delete(key: _keyCreatedAt);
    _cachedTree = null;
  }

  // ── Backup (SB-2, Option A) ────────────────────────────────

  /// Export the vault keystate (seed + leaf index + depth) for inclusion in an
  /// encrypted backup, so a vault created with a RANDOM seed (legacy) — or any
  /// vault — is recoverable from the backup file. Returns null if no vault.
  Future<Map<String, String>?> exportVaultMap() async {
    final seed = await _storage.read(key: _keySeed);
    if (seed == null || seed.isEmpty) return null;
    final leaf = await _storage.read(key: _keyLeafIndex) ?? '0';
    final depth =
        await _storage.read(key: _keyTreeDepth) ?? kDefaultTreeDepth.toString();
    final created = await _storage.read(key: _keyCreatedAt) ?? '';
    return {
      'seed': seed,
      'leafIndex': leaf,
      'treeDepth': depth,
      'createdAt': created,
    };
  }

  /// Restore the vault keystate from an encrypted backup. No-op if a vault
  /// already exists on this device (never clobber a live seed) or if the
  /// backup carries no vault.
  Future<void> importVaultMap(Map<String, dynamic> data) async {
    final seed = data['seed'] as String?;
    if (seed == null || seed.isEmpty) return;
    if (await hasVault()) return; // do not overwrite an existing vault
    await _storage.write(key: _keySeed, value: seed);
    await _storage.write(
        key: _keyLeafIndex, value: (data['leafIndex'] as String?) ?? '0');
    await _storage.write(
        key: _keyTreeDepth,
        value: (data['treeDepth'] as String?) ?? kDefaultTreeDepth.toString());
    final created = data['createdAt'] as String?;
    if (created != null && created.isNotEmpty) {
      await _storage.write(key: _keyCreatedAt, value: created);
    }
    _cachedTree = null;
  }

  /// Clear the in-memory cached tree (free memory).
  void clearCache() {
    _cachedTree = null;
  }

  // ── Hex utilities ──────────────────────────────────────────

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Vault metadata for display purposes.
class VaultInfo {
  final Uint8List? merkleRoot;
  final int leafIndex;
  final int maxKeys;
  final int remainingKeys;
  final int treeDepth;
  final DateTime? createdAt;
  final bool isExhausted;
  final bool isWarning;

  const VaultInfo({
    this.merkleRoot,
    required this.leafIndex,
    required this.maxKeys,
    required this.remainingKeys,
    required this.treeDepth,
    this.createdAt,
    required this.isExhausted,
    required this.isWarning,
  });
}
