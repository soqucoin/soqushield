/// WOTS+ (Winternitz One-Time Signature Plus) — Dart Implementation
///
/// Pure Dart port of the JavaScript xmss-client.js used by the XMSS-Lite
/// Revolving Vault (SOQ-P004, Patent #64/035,857).
///
/// This runs OFFLINE (client-side only). The on-chain Solana program
/// verifies signatures via `wots::verify()`.
///
/// Parameters (must match on-chain program exactly):
///   - Hash: Keccak256 truncated to 160 bits (20 bytes)
///   - Full hash: Keccak256 (32 bytes) for Merkle tree
///   - Chains: 32 (NUM_CHAINS)
///   - Winternitz parameter: w=16 (base-16)
///   - Max chain steps: 15 (w-1)
///
/// Security:
///   - 112-bit collision resistance (Keccak-256 truncated)
///   - 224-bit preimage resistance
///   - Quantum-safe (hash-based, no algebraic structure)
///
/// CRITICAL: Each WOTS+ key MUST be used AT MOST ONCE.
/// Using a key twice leaks private key material.
/// The on-chain leaf_index enforces this monotonically.
library;

import 'dart:typed_data';
import 'package:hashlib/hashlib.dart';

// ─── Parameters (match on-chain program) ─────────────────────

/// Truncated hash length in bytes (160 bits).
const int hashLen = 20;

/// Full Keccak256 hash length (256 bits) for Merkle tree.
const int fullHashLen = 32;

/// Number of WOTS+ chains.
const int numChains = 32;

/// Winternitz parameter (base-16).
const int w = 16;

/// Maximum chain hashing steps (w - 1).
const int maxChainSteps = w - 1;

// ─── Hash primitives ─────────────────────────────────────────

/// Truncated Keccak256 → 160-bit (20 bytes).
/// Matches on-chain: `wots::keccak_truncated()`.
Uint8List keccakTruncated(Uint8List data) {
  final full = keccak256.convert(data);
  return Uint8List.fromList(full.bytes.sublist(0, hashLen));
}

/// Full Keccak256 → 256-bit (32 bytes).
/// Matches on-chain: `wots::keccak_full()`.
Uint8List keccakFull(Uint8List data) {
  return Uint8List.fromList(keccak256.convert(data).bytes);
}

/// Hash chain: apply Keccak256 `steps` times.
/// `chain(x, steps) = H(H(H(...H(x)...)))`.
Uint8List hashChain(Uint8List input, int steps) {
  var current = Uint8List.fromList(input);
  for (var i = 0; i < steps; i++) {
    current = keccakTruncated(current);
  }
  return current;
}

// ─── Message encoding ────────────────────────────────────────

/// Convert first 16 bytes of message to base-w (base-16) digits.
/// Each byte → 2 digits (high nibble, low nibble).
/// Matches on-chain: `wots::msg_to_digits()`.
List<int> msgToDigits(Uint8List msg) {
  final digits = List<int>.filled(numChains, 0);
  for (var i = 0; i < 16; i++) {
    digits[i * 2] = (msg[i] >> 4) & 0x0f;
    digits[i * 2 + 1] = msg[i] & 0x0f;
  }
  return digits;
}

// ─── WOTS+ Keypair ───────────────────────────────────────────

/// A single WOTS+ keypair.
class WotsKeypair {
  /// Private key chains (NUM_CHAINS × HASH_LEN bytes each).
  final List<Uint8List> privateKey;

  /// Public key chains (NUM_CHAINS × HASH_LEN bytes each).
  final List<Uint8List> publicKey;

  /// Keccak256(pk[0] || pk[1] || ... || pk[31]) — 32 bytes.
  final Uint8List publicKeyHash;

  const WotsKeypair({
    required this.privateKey,
    required this.publicKey,
    required this.publicKeyHash,
  });
}

/// Generate a single WOTS+ keypair from a 32-byte seed.
///
/// Key derivation:
///   1. For each chain i: sk[i] = Keccak_truncated(seed || i_LE32)
///   2. Public key:        pk[i] = Hash^(w-1)(sk[i])
///   3. Public key hash:   Keccak256(pk[0] || pk[1] || ... || pk[31])
WotsKeypair generateWotsKeypair(Uint8List seed) {
  // A4-03: Use throw instead of assert — assert is stripped in release builds.
  // A wrong-length seed in production would silently produce a wrong keypair.
  if (seed.length != 32) {
    throw ArgumentError('WOTS+ seed must be exactly 32 bytes, got ${seed.length}');
  }

  final privateKey = <Uint8List>[];
  final publicKey = <Uint8List>[];

  for (var i = 0; i < numChains; i++) {
    // Derive chain seed: seed || i (little-endian u32)
    final chainSeed = Uint8List(36);
    chainSeed.setRange(0, 32, seed);
    final byteData = ByteData.sublistView(chainSeed);
    byteData.setUint32(32, i, Endian.little);

    final sk = keccakTruncated(chainSeed);
    privateKey.add(sk);

    // Public key = Hash^(w-1)(private key)
    final pk = hashChain(sk, maxChainSteps);
    publicKey.add(pk);
  }

  // Public key hash = Keccak256(pk[0] || pk[1] || ... || pk[31])
  final pkConcat = Uint8List(publicKey.length * hashLen);
  for (var i = 0; i < publicKey.length; i++) {
    pkConcat.setRange(i * hashLen, (i + 1) * hashLen, publicKey[i]);
  }
  final publicKeyHash = keccakFull(pkConcat);

  return WotsKeypair(
    privateKey: privateKey,
    publicKey: publicKey,
    publicKeyHash: publicKeyHash,
  );
}

// ─── WOTS+ Signing ───────────────────────────────────────────

/// Sign a message with a WOTS+ private key.
///
/// For each chain i: sig[i] = Hash^(digit[i])(sk[i])
/// where digit[i] is the i-th base-16 digit of the message hash.
///
/// @param message HASH_LEN-byte message (already hashed)
/// @param privateKey Array of NUM_CHAINS private key chains
/// @returns Array of NUM_CHAINS signature chains
List<Uint8List> wotsSign(Uint8List message, List<Uint8List> privateKey) {
  // A4-03: Runtime validation — assert is stripped in release builds.
  if (message.length < hashLen) {
    throw ArgumentError('WOTS+ message must be at least $hashLen bytes, got ${message.length}');
  }
  if (privateKey.length != numChains) {
    throw ArgumentError('WOTS+ private key must have $numChains chains, got ${privateKey.length}');
  }

  final digits = msgToDigits(message);
  final signature = <Uint8List>[];

  for (var i = 0; i < numChains; i++) {
    final sig = hashChain(privateKey[i], digits[i]);
    signature.add(sig);
  }

  // SECURITY: Zero private key chains after signing.
  // WOTS+ keys are one-time-use — there is NO reason to keep
  // them in memory after the signature is produced.
  for (final chain in privateKey) {
    chain.fillRange(0, chain.length, 0);
  }

  return signature;
}

/// Verify a WOTS+ signature (client-side — mirrors on-chain verification).
///
/// For each chain i: pk_recovered[i] = Hash^(w-1-digit[i])(sig[i])
/// Then: Keccak256(pk_recovered[0] || ... || pk_recovered[31]) == expectedPkHash
bool wotsVerify(
  Uint8List message,
  List<Uint8List> signature,
  Uint8List expectedPkHash,
) {
  final digits = msgToDigits(message);
  final recovered = <Uint8List>[];

  for (var i = 0; i < numChains; i++) {
    final remaining = maxChainSteps - digits[i];
    final pk = hashChain(signature[i], remaining);
    recovered.add(pk);
  }

  final pkConcat = Uint8List(recovered.length * hashLen);
  for (var i = 0; i < recovered.length; i++) {
    pkConcat.setRange(i * hashLen, (i + 1) * hashLen, recovered[i]);
  }
  final recoveredHash = keccakFull(pkConcat);

  // Constant-time comparison
  if (recoveredHash.length != expectedPkHash.length) return false;
  var diff = 0;
  for (var i = 0; i < recoveredHash.length; i++) {
    diff |= recoveredHash[i] ^ expectedPkHash[i];
  }
  return diff == 0;
}

// ─── Withdrawal message construction ─────────────────────────

/// Construct the withdrawal message that gets WOTS+ signed.
/// Matches on-chain: `construct_withdrawal_message()`.
///
/// Format: Keccak_truncated(amount_LE64 || recipient_32 || leaf_index_LE16)
///
/// @param amount Token amount in raw units (lamports/base units)
/// @param recipientPubkey 32-byte Solana public key of the recipient
/// @param leafIndex Current XMSS leaf index
Uint8List constructWithdrawalMessage(
  int amount,
  Uint8List recipientPubkey,
  int leafIndex,
) {
  // A4-03: Runtime validation — assert is stripped in release builds.
  if (recipientPubkey.length != 32) {
    throw ArgumentError('Recipient pubkey must be 32 bytes, got ${recipientPubkey.length}');
  }

  final buf = Uint8List(42); // 8 + 32 + 2
  final byteData = ByteData.sublistView(buf);

  // amount as little-endian u64
  byteData.setUint64(0, amount, Endian.little);

  // recipient pubkey (32 bytes)
  buf.setRange(8, 40, recipientPubkey);

  // leaf_index as little-endian u16
  byteData.setUint16(40, leafIndex, Endian.little);

  return keccakTruncated(buf);
}
