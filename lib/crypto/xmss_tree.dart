/// XMSS-Lite Key Tree — Merkle Tree + Proof Generation
///
/// Generates an XMSS-Lite key tree (multiple WOTS+ keypairs organized
/// in a Merkle tree) and computes authentication paths for each leaf.
///
/// The Merkle root is committed on-chain when opening a vault.
/// Each withdrawal requires the WOTS+ signature + Merkle proof for
/// the current leaf_index.
///
/// Patent: SOQ-P004 #64/035,857 (XMSS-Lite Revolving Vault)
library;

import 'dart:math';
import 'dart:typed_data';
import 'wots_signer.dart';

/// Complete XMSS-Lite key tree with Merkle proofs.
class XmssKeyTree {
  /// All WOTS+ keypairs (2^depth leaves).
  final List<WotsKeypair> keys;

  /// Leaf hashes (public key hashes).
  final List<Uint8List> leaves;

  /// Merkle root hash (32 bytes) — committed on-chain.
  final Uint8List merkleRoot;

  /// Authentication paths for each leaf.
  /// proofs[i] = list of sibling hashes from leaf i to root.
  final List<List<Uint8List>> proofs;

  /// Master seed used to derive all keys (MUST be stored securely).
  final Uint8List masterSeed;

  /// Tree depth (log2 of number of leaves).
  final int depth;

  const XmssKeyTree({
    required this.keys,
    required this.leaves,
    required this.merkleRoot,
    required this.proofs,
    required this.masterSeed,
    required this.depth,
  });

  /// Number of total available signatures.
  int get maxSignatures => 1 << depth;

  /// Get the WOTS+ keypair at [leafIndex].
  WotsKeypair keypairAt(int leafIndex) => keys[leafIndex];

  /// Get the Merkle proof for [leafIndex].
  List<Uint8List> proofAt(int leafIndex) => proofs[leafIndex];

  /// Flatten the WOTS+ signature into a single byte buffer
  /// (for the on-chain `Vec<u8>` parameter).
  static Uint8List flattenSignature(List<Uint8List> signature) {
    final totalLen = signature.fold<int>(0, (sum, s) => sum + s.length);
    final result = Uint8List(totalLen);
    var offset = 0;
    for (final s in signature) {
      result.setRange(offset, offset + s.length, s);
      offset += s.length;
    }
    return result;
  }

  /// Flatten the Merkle proof into a single byte buffer
  /// (for the on-chain `Vec<u8>` parameter).
  static Uint8List flattenProof(List<Uint8List> proof) {
    final totalLen = proof.fold<int>(0, (sum, p) => sum + p.length);
    final result = Uint8List(totalLen);
    var offset = 0;
    for (final p in proof) {
      result.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return result;
  }
}

/// Generate an XMSS-Lite key tree.
///
/// @param depth Tree depth (2^depth leaves). Use 4 for demo (16 keys),
///   10 for production (1024 keys).
/// @param masterSeed Optional 32-byte master seed. Random if not provided.
///   MUST be stored securely — it derives ALL private keys.
XmssKeyTree generateXmssTree(int depth, [Uint8List? masterSeed]) {
  final numLeaves = 1 << depth;
  final seed = masterSeed ?? _secureRandomBytes(32);

  // Generate all WOTS+ keypairs
  final keys = <WotsKeypair>[];
  final leaves = <Uint8List>[];

  for (var i = 0; i < numLeaves; i++) {
    // Derive per-leaf seed: Keccak256(masterSeed || i_LE32)
    final leafSeed = Uint8List(36);
    leafSeed.setRange(0, 32, seed);
    final byteData = ByteData.sublistView(leafSeed);
    byteData.setUint32(32, i, Endian.little);
    final derivedSeed = keccakFull(leafSeed);

    final keypair = generateWotsKeypair(derivedSeed);
    keys.add(keypair);
    leaves.add(keypair.publicKeyHash);
  }

  // Build Merkle tree
  final (root, proofs) = _buildMerkleTree(leaves);

  return XmssKeyTree(
    keys: keys,
    leaves: leaves,
    merkleRoot: root,
    proofs: proofs,
    masterSeed: seed,
    depth: depth,
  );
}

/// Build a Merkle tree and generate authentication paths for all leaves.
(Uint8List root, List<List<Uint8List>> proofs) _buildMerkleTree(
  List<Uint8List> leaves,
) {
  // Pad to power of 2
  final paddedLeaves = List<Uint8List>.from(leaves);
  while (paddedLeaves.length & (paddedLeaves.length - 1) != 0) {
    paddedLeaves.add(Uint8List(fullHashLen)); // zero-padded
  }

  // Build tree layers bottom-up
  final layers = <List<Uint8List>>[
    paddedLeaves.map((l) => Uint8List.fromList(l)).toList(),
  ];

  while (layers.last.length > 1) {
    final prev = layers.last;
    final next = <Uint8List>[];
    for (var i = 0; i < prev.length; i += 2) {
      final combined = Uint8List(prev[i].length + prev[i + 1].length);
      combined.setRange(0, prev[i].length, prev[i]);
      combined.setRange(prev[i].length, combined.length, prev[i + 1]);
      next.add(keccakFull(combined));
    }
    layers.add(next);
  }

  final root = layers.last[0];

  // Generate proofs (authentication paths) for each leaf
  final proofs = <List<Uint8List>>[];
  for (var leafIdx = 0; leafIdx < leaves.length; leafIdx++) {
    final proof = <Uint8List>[];
    var idx = leafIdx;
    for (var layerIdx = 0; layerIdx < layers.length - 1; layerIdx++) {
      final siblingIdx = idx.isEven ? idx + 1 : idx - 1;
      proof.add(Uint8List.fromList(layers[layerIdx][siblingIdx]));
      idx = idx ~/ 2;
    }
    proofs.add(proof);
  }

  return (root, proofs);
}

/// Generate cryptographically secure random bytes.
Uint8List _secureRandomBytes(int length) {
  final rng = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => rng.nextInt(256)),
  );
}
