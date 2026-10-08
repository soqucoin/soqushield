// ignore_for_file: unused_element
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:convert/convert.dart';
import 'package:hashlib/hashlib.dart';
import '../crypto/dilithium_ffi_bindings.dart';
import '../models/utxo.dart';
import '../models/transaction.dart';
import '../services/rpc_service.dart';
import '../models/wallet_keys.dart';
import '../services/utxo_service.dart';

/// Asset type byte for multi-asset output construction.
/// Matches CTxOut::nAssetType in the L1 consensus.
const int kAssetTypeSoq = 0x00;
const int kAssetTypeUsdsoq = 0x01;

/// Witness version opcodes (OP_N = 0x50 + N for N >= 1; OP_0 = 0x00).
const int kOpWitnessV1 = 0x51; // Dilithium single-key
const int kOpWitnessV7 = 0x57; // USDSOQ holding (0x50 + 7)

/// Witness versions this wallet will send funds to.
///
/// ⛔ WHY AN ALLOWLIST AND NOT JUST A LENGTH CHECK. Every Soqucoin witness
/// version shares the same HRP (`sq` / `ssq`), so checking only the HRP and the
/// 32-byte program length accepts an address for a version this chain does not
/// spend. A witness version with no active consensus rule is anyone-can-spend
/// under BIP-141, so paying one is a LOSS-OF-FUNDS path: the payment confirms
/// and any observer can then sweep it.
///
/// This is the same defence the mining pool already applies
/// (soqupool-server/bitcoin/soqucoin.go, bead gp9): "Other witness versions
/// share the same HRP but are anyone-can-spend on mainnet, so an HRP-only check
/// would wave loss-of-funds addresses through."
///
///   v1 — Dilithium single-key. The primary spendable form.
///   v5 — USDSOQ authority marker.  } only usable where the USDSOQ
///   v7 — USDSOQ holding.           } deployment is active.
///
/// ⛔ Do NOT widen this set because a version "exists" or because an opcode for
/// it is active. Add one only when its consensus rule makes outputs of that
/// version require a real authorization to spend. v2 (PAT attestation) must
/// never be added: PAT commits to signatures rather than verifying them, so a
/// v2 output authorizes nothing (bead pat-v2-anyone-can-spend-ae6u).
const Set<int> kSupportedWitnessVersions = {1, 5, 7};

/// Whether this wallet will send funds to the given witness version.
bool isSupportedWitnessVersion(int witnessVersion) =>
    kSupportedWitnessVersions.contains(witnessVersion);

/// Builds and signs Soqucoin transactions using ML-DSA-44 (Dilithium).
///
/// Transaction format follows BIP141 segwit serialization with witness v1:
///   - Signatures go in the witness data section, not scriptSig
///   - BIP143 sighash algorithm (commits to amount, prevouts, sequences)
///   - CTxOut includes nVisibility and nAssetType (Soqucoin extension)
///   - ML-DSA-44 signatures are 2420 bytes (vs ECDSA ~72 bytes)
///
/// The scriptSig for a PQ spend is:
///   [2420-byte DilithiumSig] [1312-byte DilithiumPubKey]
///
/// The scriptPubKey for a PQ address is:
///   OP_DUP OP_HASH160 [20-byte pubKeyHash] OP_EQUALVERIFY OP_CHECKSIG
///
/// Note: The node's PQ-aware OP_CHECKSIG validates ML-DSA-44 signatures.
///
class TxBuilder {
  final RpcService _rpc;
  final UtxoService _utxoService;

  TxBuilder(this._rpc, this._utxoService);

  /// Build, sign, and broadcast a transaction.
  ///
  /// Returns the transaction ID on success, or throws on failure.
  Future<String> sendTransaction({
    required String toAddress,
    required double amountSoq,
    required Uint8List secretKey,
    required Uint8List publicKey,
    required String myAddress,
    double? feePerKb,
    AssetType assetType = AssetType.soq,
    bool confidential = false,
  }) async {
    final amountSat = (amountSoq * 100000000).round();

    // 1. Estimate fee rate (returned as SOQ/kB from the node)
    final feeRateSoqPerKb = feePerKb ?? await _estimateFee();
    // Convert to satoshis/kB for integer arithmetic
    final feeRateSatPerKb = (feeRateSoqPerKb * 100000000).round();
    
    // Estimate tx size for fee calculation:
    // Base tx overhead: ~10 bytes (version + locktime + vin/vout counts)
    // Each input: ~3746 bytes (txid:32 + vout:4 + scriptSig:~3732 + seq:4)
    //   scriptSig = push(sig:2420) + push(pubkey:1312) = ~3734 + varint headers
    // Each output: ~34 bytes (value:8 + scriptPubKey:~26)
    // PQ transactions are significantly larger than ECDSA ones
    final estimatedInputs = 2; // Conservative estimate
    final estimatedSize = 10 + (estimatedInputs * 3750) + (2 * 34);
    // Fee = (rate_sat_per_kB * size_bytes) / 1000, floor at minrelaytxfee
    var feeSat = ((feeRateSatPerKb * estimatedSize) / 1000).ceil();
    // Ensure fee meets minrelaytxfee (0.001 SOQ/kB = 100,000 sat/kB)
    // For a ~4kB Dilithium TX, minimum = ~400,000 sat = 0.004 SOQ
    final minFeeSat = ((100000 * estimatedSize) / 1000).ceil();
    if (feeSat < minFeeSat) feeSat = minFeeSat;

    // 2. Select UTXOs. USDSOQ requires ASSET ISOLATION: the USDSOQ inputs fund
    // the USDSOQ recipient + USDSOQ change and must be CONSERVED exactly
    // (USDSOQ_in == USDSOQ_out); the miner fee is paid from SEPARATE SOQ inputs
    // with SOQ change. (Mirrors the signer's BuildSendUSDSOQTransaction. The old
    // single-asset path deducted the SOQ fee out of the USDSOQ value → a
    // non-conserving tx the node rejects — and crashed pre-fix nodes.)
    final isUsdsoq = assetType == AssetType.usdsoq;
    final List<Utxo> selected;
    List<Utxo> usdsoqInputs = const [];
    List<Utxo> soqFeeInputs = const [];
    if (isUsdsoq) {
      final u = _utxoService.selectUtxos(amountSat, 0, assetType: AssetType.usdsoq);
      if (u == null) {
        throw InsufficientFundsException(
          available: _utxoService.usdsoqBalance, requested: amountSoq);
      }
      final s = _utxoService.selectUtxos(feeSat, 0, assetType: AssetType.soq);
      if (s == null) {
        throw InsufficientFundsException(
          available: _utxoService.balanceSat / 100000000,
          requested: feeSat / 100000000);
      }
      usdsoqInputs = u;
      soqFeeInputs = s;
      selected = [...u, ...s];
    } else {
      final sel = _utxoService.selectUtxos(amountSat, feeSat, assetType: AssetType.soq);
      if (sel == null) {
        throw InsufficientFundsException(
          available: _utxoService.balanceSat / 100000000, requested: amountSoq);
      }
      selected = sel;
    }

    // SB-8: reserve the selected coins for the duration of this send so a
    // concurrent selection (e.g. a parallel bridge/send flow) can't pick the
    // same UTXOs and double-spend. Reservation is in-memory only (cleared on
    // crash/restart) and released in the finally below — on success the inputs
    // are also removed from the tracker by recordSentTransaction.
    _utxoService.reserveUtxos(selected);
    try {
      // Recalculate fee with actual input count (USDSOQ sends have up to 3
      // outputs: USDSOQ recipient + USDSOQ change + SOQ change).
      final actualSize = 10 + (selected.length * 3750) + (3 * 34);
      var actualFeeSat = ((feeRateSatPerKb * actualSize) / 1000).ceil();
      final actualMinFee = ((100000 * actualSize) / 1000).ceil();
      if (actualFeeSat < actualMinFee) actualFeeSat = actualMinFee;

      final outputs = <_RawOutput>[];
      final outputVisibility = confidential ? 0x01 : 0x00;
      final recipientSpk = _addressToScriptPubKey(toAddress);
      final changeSpk = _addressToScriptPubKey(myAddress);

      if (isUsdsoq) {
        final usdsoqIn = Utxo.totalValueSat(usdsoqInputs);
        final soqIn = Utxo.totalValueSat(soqFeeInputs);
        final usdsoqChange = usdsoqIn - amountSat; // conservation remainder
        final soqChange = soqIn - actualFeeSat;
        if (usdsoqChange < 0) {
          throw InsufficientFundsException(
            available: usdsoqIn / 100000000, requested: amountSoq);
        }
        if (soqChange < 0) {
          throw InsufficientFundsException(
            available: soqIn / 100000000, requested: actualFeeSat / 100000000);
        }
        // USDSOQ recipient (re-key OP_1 → OP_7 v7 holding). Confidential USDSOQ
        // is not supported yet, so these stay transparent.
        outputs.add(_RawOutput(
          valueSat: amountSat,
          scriptPubKey: _rekeyToV7Holding(recipientSpk),
          visibility: 0x00,
          assetType: kAssetTypeUsdsoq,
        ));
        // USDSOQ change — ALWAYS emitted when non-zero (conservation is exact,
        // NOT subject to the dust threshold; dropping it would destroy USDSOQ).
        if (usdsoqChange > 0) {
          outputs.add(_RawOutput(
            valueSat: usdsoqChange,
            scriptPubKey: _rekeyToV7Holding(changeSpk),
            visibility: 0x00,
            assetType: kAssetTypeUsdsoq,
          ));
        }
        // SOQ fee change (subject to dust).
        if (soqChange > 100000) {
          outputs.add(_RawOutput(
            valueSat: soqChange,
            scriptPubKey: changeSpk,
            visibility: 0x00,
            assetType: kAssetTypeSoq,
          ));
        }
      } else {
        final totalInputSat = Utxo.totalValueSat(selected);
        final changeSat = totalInputSat - amountSat - actualFeeSat;
        if (changeSat < 0) {
          throw InsufficientFundsException(
            available: totalInputSat / 100000000,
            requested: amountSoq + (actualFeeSat / 100000000),
          );
        }
        outputs.add(_RawOutput(
          valueSat: amountSat,
          scriptPubKey: recipientSpk,
          visibility: outputVisibility,
          assetType: kAssetTypeSoq,
        ));
        if (changeSat > 100000) {
          outputs.add(_RawOutput(
            valueSat: changeSat,
            scriptPubKey: changeSpk,
            visibility: outputVisibility,
            assetType: kAssetTypeSoq,
          ));
        }
      }

      // 4. Build unsigned transaction
      final unsignedTx = _buildUnsignedTx(selected, outputs);

      // 5. Sign each input
      final signedTx = _signTransaction(
        unsignedTx,
        selected,
        secretKey,
        publicKey,
      );

      // 6. Broadcast
      debugPrint('TxBuilder: Broadcasting ${signedTx.length ~/ 2} bytes');
      debugPrint('TxBuilder: Raw hex (first 200): ${signedTx.substring(0, signedTx.length.clamp(0, 200))}...');

      // SB-6: once sendRawTransaction returns a txid, the funds have MOVED — the
      // send has succeeded. Broadcast is its own try/catch; only a broadcast
      // failure may propagate as a failed send.
      final String txid;
      try {
        txid = await _rpc.sendRawTransaction(signedTx);
        debugPrint('TxBuilder: Broadcast success — txid=$txid');
      } catch (e) {
        debugPrint('TxBuilder: Broadcast FAILED — $e');
        debugPrint('TxBuilder: Full hex length=${signedTx.length ~/ 2}');
        rethrow;
      }

      // 7. Record in UTXO tracker — best-effort bookkeeping, in a SEPARATE
      // try/catch that can ONLY log. A decode/record error here must never flip
      // an already-broadcast tx to "failed" — that mislead users into retrying
      // and double-spending (SS-05).
      try {
        final decodedTx = await _rpc.decodeRawTransaction(signedTx);
        final soqTx = SoqTransaction.fromRpc(decodedTx);
        await _utxoService.recordSentTransaction(soqTx, myAddress);
      } catch (e) {
        debugPrint('TxBuilder: post-broadcast bookkeeping failed (non-fatal — '
            'txid=$txid is already broadcast): $e');
      }

      return txid;
    } finally {
      // SB-8: release the reservation on every exit (success, throw, or
      // insufficient-change) so the coins aren't stranded as unspendable.
      _utxoService.releaseUtxos(selected);
    }
  }

  /// The scriptPubKey an address pays to (the history sync compares outputs
  /// against it).
  Uint8List scriptPubKeyForAddress(String address) => _addressToScriptPubKey(address);

  /// Estimate fee rate (SOQ/kB).
  Future<double> _estimateFee() async {
    try {
      return await _rpc.estimateSmartFee(6); // Target 6-block confirm
    } catch (_) {
      return 0.01; // 0.01 SOQ/kB fallback (generous for Soqucoin)
    }
  }

  /// Convert a Bech32m address to a scriptPubKey.
  ///
  /// Version-aware: the decoded witness version determines the OP_N opcode.
  ///   - v1 → OP_1 (0x51) — Dilithium single-key (SOQ or legacy USDSOQ)
  ///   - v5 → OP_5 (0x55) — USDSOQ authority marker
  ///   - v7 → OP_7 (0x57) — USDSOQ v7 holding
  ///
  /// See: soqucoin-build/src/wallet/rpcwallet.cpp:145
  ///      WitnessV1ScriptHash dest(pubkeyHash);
  Uint8List _addressToScriptPubKey(String address) {
    // Decode Bech32m to get the witness program (32-byte SHA-256 hash)
    final decoded = _decodeBech32m(address);
    final witnessProgram = decoded.program;

    if (witnessProgram.length != 32) {
      throw ArgumentError(
        'Invalid witness program: expected 32 bytes, got ${witnessProgram.length}. '
        'Address may be using old BLAKE2b-160 format (SOQ-INFRA-009).',
      );
    }

    // Defence in depth: validateAddress already rejects unsupported versions,
    // but this is the function that actually mints the scriptPubKey, so it
    // refuses too. Never build a script for a version this chain cannot spend.
    final witVer = decoded.witnessVersion;
    if (!isSupportedWitnessVersion(witVer)) {
      throw ArgumentError(
        'Refusing to build a scriptPubKey for witness v$witVer: this chain does '
        'not spend that version, so the output would be anyone-can-spend '
        '(bead pat-v2-anyone-can-spend-ae6u). Supported: '
        '${kSupportedWitnessVersions.join(", ")}.',
      );
    }

    // Build scriptPubKey: OP_N + PUSH_32 (0x20) + 32-byte program
    // OP_0 = 0x00, OP_N = 0x50 + N for N >= 1
    final opcode = witVer == 0 ? 0x00 : 0x50 + witVer;
    final script = Uint8List(34);
    script[0] = opcode;
    script[1] = 0x20; // Push 32 bytes
    script.setRange(2, 34, witnessProgram);
    return script;
  }

  /// Re-key a witness-v1 Dilithium scriptPubKey to a v7 USDSOQ holding.
  ///
  /// Input:  OP_1 (0x51) || PUSH_32 (0x20) || [32-byte pubkey hash]
  /// Output: OP_7 (0x57) || PUSH_32 (0x20) || [same 32-byte hash]
  ///
  /// Mirrors Go's V7HoldingFromRecipientScript (v7_holding.go) and
  /// C++ rpc/usdsoq.cpp:usdsoqmint. Only v1 inputs are accepted;
  /// v7 inputs pass through unchanged (already a holding).
  Uint8List _rekeyToV7Holding(Uint8List spk) {
    if (spk.length != 34 || spk[1] != 0x20) {
      throw ArgumentError(
        'USDSOQ holding requires a 34-byte witness program, got ${spk.length}',
      );
    }
    // Already v7 — pass through (spending an existing v7 holding's change)
    if (spk[0] == kOpWitnessV7) return spk;
    // Must be v1 — reject other versions
    if (spk[0] != kOpWitnessV1) {
      throw ArgumentError(
        'USDSOQ destination must be witness v1 (Dilithium), '
        'got 0x${spk[0].toRadixString(16)}',
      );
    }
    final v7 = Uint8List.fromList(spk);
    v7[0] = kOpWitnessV7;
    return v7;
  }

  /// The BIP143 scriptCode used when SIGNING [input].
  ///
  /// A v7 USDSOQ holding must be signed against its real on-chain scriptPubKey
  /// OP_7`<program>` — that is what the node uses as the scriptCode when it verifies.
  /// The UTXO tracker can hold the v1 form OP_1`<program>` for a USDSOQ coin (refresh()
  /// updates assetType from the chain but not the stored SPK), so the correct scriptCode
  /// is derived from the input's ASSET TYPE, not the stored prefix. This is the single
  /// source of truth for step 5 of _computeBip143Sighash.
  Uint8List _scriptCodeForInput(Utxo input) {
    final storedSpk = Uint8List.fromList(hex.decode(input.scriptPubKey));
    return input.assetType == AssetType.usdsoq
        ? _rekeyToV7Holding(storedSpk)
        : storedSpk;
  }

  // ── Test hooks (CTxOut migration Phase 3) ──
  // The v7 send-path re-keying helpers are private; these @visibleForTesting wrappers
  // let test/v7_holding_test.dart behaviour-test them. Not for normal callers.
  @visibleForTesting
  Uint8List debugRekeyToV7Holding(Uint8List spk) => _rekeyToV7Holding(spk);
  @visibleForTesting
  Uint8List debugScriptCodeForInput(Utxo input) => _scriptCodeForInput(input);
  @visibleForTesting
  Uint8List debugAddressToScriptPubKey(String address) =>
      _addressToScriptPubKey(address);

  /// Build an unsigned transaction (raw bytes).
  Uint8List _buildUnsignedTx(List<Utxo> inputs, List<_RawOutput> outputs) {
    final buf = BytesBuilder();

    // Version (little-endian uint32) — v2 enables BIP68/BIP112 (CSV)
    buf.add(_uint32LE(2));

    // Input count (varint)
    buf.add(_varint(inputs.length));

    // Inputs
    for (final input in inputs) {
      // Previous txid (reversed — internal byte order)
      buf.add(_hexToReversed(input.txid));
      // Previous vout (little-endian uint32)
      buf.add(_uint32LE(input.vout));
      // ScriptSig (empty for unsigned)
      buf.add(_varint(0));
      // Sequence
      buf.add(_uint32LE(0xFFFFFFFF));
    }

    // Output count (varint)
    buf.add(_varint(outputs.length));

    // Outputs (Soqucoin CTxOut: value + scriptPubKey + nVisibility + nAssetType)
    for (final output in outputs) {
      // Value (little-endian int64)
      buf.add(_int64LE(output.valueSat));
      // ScriptPubKey
      buf.add(_varint(output.scriptPubKey.length));
      buf.add(output.scriptPubKey);
      // Phase 4: CTxOut is byte-less — no nVisibility/nAssetType (asset/visibility = witness version).
    }

    // Lock time
    buf.add(_uint32LE(0));

    return buf.toBytes();
  }

  /// The txid (display order) of a tx from its NON-witness serialization. For a
  /// segwit tx the witness data doesn't affect the txid, so the unsigned form
  /// ([_buildUnsignedTx] — empty scriptSigs) IS the txid preimage. Computed
  /// locally (sha256d, reversed) so the unbroadcast funding flow needs no RPC
  /// (the node's `decoderawtransaction` is rejected by the proxy backend).
  String _txidFromUnsigned(Uint8List unsignedTx) {
    final first = sha256.convert(unsignedTx);
    final second = sha256.convert(first.bytes);
    return hex.encode(second.bytes.reversed.toList());
  }

  /// Sign all inputs of the transaction.
  ///
  /// For each input, we:
  ///   1. Create a BIP143 sighash (witness v0 sighash algorithm)
  ///   2. Sign the sighash with ML-DSA-44
  ///   3. Build the witness stack: [sig||hashtype, 0x00||pubkey]
  String _signTransaction(
    Uint8List unsignedTx,
    List<Utxo> inputs,
    Uint8List secretKey,
    Uint8List publicKey,
  ) {
    final pubBytes = publicKey;
    // Witness pubkey is prefixed with 0x00 (NIST FIPS 204 Table 3)
    final witnessPubkey = Uint8List(pubBytes.length + 1);
    witnessPubkey[0] = 0x00;
    witnessPubkey.setRange(1, witnessPubkey.length, pubBytes);

    // Precompute BIP143 components
    final hashPrevouts = _computeHashPrevouts(inputs);
    final hashSequence = _computeHashSequence(inputs);
    final hashOutputs = _computeHashOutputs(unsignedTx, inputs.length);

    debugPrint('TxBuilder: hashPrevouts=${hex.encode(hashPrevouts)}');
    debugPrint('TxBuilder: hashSequence=${hex.encode(hashSequence)}');
    debugPrint('TxBuilder: hashOutputs=${hex.encode(hashOutputs)}');
    debugPrint('TxBuilder: witnessPubkey len=${witnessPubkey.length}');

    final witnessStacks = <List<Uint8List>>[];
    final native = DilithiumNative.instance;

    for (var i = 0; i < inputs.length; i++) {
      // BIP143 sighash for this input
      final sighash = _computeBip143Sighash(
        inputs, i, hashPrevouts, hashSequence, hashOutputs, unsignedTx,
      );

      debugPrint('TxBuilder: sighash[$i]=${hex.encode(sighash)}');
      debugPrint('TxBuilder: input[$i] txid=${inputs[i].txid} vout=${inputs[i].vout} valueSat=${inputs[i].valueSat}');
      debugPrint('TxBuilder: input[$i] scriptPubKey=${inputs[i].scriptPubKey}');

      // Sign with native FIPS 204 ML-DSA-44 (same C code as the node)
      final sigBytes = native.sign(sighash, secretKey);

      // Append SIGHASH_ALL byte
      final sigWithHashType = Uint8List(sigBytes.length + 1);
      sigWithHashType.setRange(0, sigBytes.length, sigBytes);
      sigWithHashType[sigBytes.length] = 0x01; // SIGHASH_ALL

      // Witness stack: [sig+hashtype, pubkey_with_prefix]
      witnessStacks.add([sigWithHashType, witnessPubkey]);
    }

    // Build segwit serialized transaction
    return _buildWitnessTxHex(inputs, unsignedTx, witnessStacks);
  }

  /// Compute hashPrevouts for BIP143 (double SHA-256 of all outpoints)
  Uint8List _computeHashPrevouts(List<Utxo> inputs) {
    final buf = BytesBuilder();
    for (final input in inputs) {
      buf.add(_hexToReversed(input.txid));
      buf.add(_uint32LE(input.vout));
    }
    final first = sha256.convert(buf.toBytes());
    final second = sha256.convert(first.bytes);
    return Uint8List.fromList(second.bytes);
  }

  /// Compute hashSequence for BIP143 (double SHA-256 of all sequences)
  Uint8List _computeHashSequence(List<Utxo> inputs) {
    final buf = BytesBuilder();
    for (var i = 0; i < inputs.length; i++) {
      buf.add(_uint32LE(0xFFFFFFFF));
    }
    final first = sha256.convert(buf.toBytes());
    final second = sha256.convert(first.bytes);
    return Uint8List.fromList(second.bytes);
  }

  /// Compute hashOutputs for BIP143 (double SHA-256 of all serialized outputs).
  /// Per BIP143: each output is serialized as value+scriptPubKey+nVisibility+nAssetType.
  /// The output count varint is NOT included (matches node's `for(txout: vout) ss<<txout`).
  Uint8List _computeHashOutputs(Uint8List unsignedTx, int inputCount) {
    final outputs = _parseOutputs(unsignedTx, inputCount);
    final buf = BytesBuilder();
    for (final output in outputs) {
      buf.add(_int64LE(output.valueSat));
      // scriptPubKey with CompactSize length prefix
      buf.add(_varint(output.scriptPubKey.length));
      buf.add(output.scriptPubKey);
      // Phase 4: byte-less CTxOut — no nVisibility/nAssetType in the BIP143 output commitment.
    }
    final first = sha256.convert(buf.toBytes());
    final second = sha256.convert(first.bytes);
    return Uint8List.fromList(second.bytes);
  }

  /// Compute BIP143 sighash for a witness v1 input.
  ///
  /// BIP143 preimage:
  ///   1. nVersion (4)
  ///   2. hashPrevouts (32)
  ///   3. hashSequence (32)
  ///   4. outpoint being spent (36)
  ///   5. scriptCode of the input (serialized as script)
  ///   6. value of the output being spent (8)
  ///   7. nSequence of the input (4)
  ///   8. hashOutputs (32)
  ///   9. nLockTime (4)
  ///  10. sighash type (4)
  Uint8List _computeBip143Sighash(
    List<Utxo> inputs,
    int inputIndex,
    Uint8List hashPrevouts,
    Uint8List hashSequence,
    Uint8List hashOutputs,
    Uint8List unsignedTx,
  ) {
    final buf = BytesBuilder();

    // 1. nVersion (must match TX version for valid sighash)
    buf.add(_uint32LE(2));

    // 2. hashPrevouts
    buf.add(hashPrevouts);

    // 3. hashSequence
    buf.add(hashSequence);

    // 4. outpoint (txid + vout)
    buf.add(_hexToReversed(inputs[inputIndex].txid));
    buf.add(_uint32LE(inputs[inputIndex].vout));

    // 5. scriptCode — the scriptPubKey of the output being spent, length-prefixed.
    //    CRITICAL (v7 USDSOQ): the node verifies a v7 holding against its ACTUAL on-chain
    //    scriptPubKey OP_7<program> (interpreter.cpp CheckSig passes the v7 SPK as the
    //    scriptCode). The UTXO tracker can hand us the v1 form OP_1<program> for a USDSOQ
    //    coin — refresh() updates assetType from the chain but does NOT re-key the stored
    //    scriptPubKey — so we must derive the scriptCode from the input's ASSET TYPE, not
    //    the stored prefix. Signing a v7 input with the v1 scriptCode differs by exactly
    //    one byte (0x51 vs 0x57) → wrong sighash → NULLFAIL at block validation: the tx
    //    relays and sits in the mempool but can NEVER be mined (empty blocks). Verified
    //    against the live failing tx daf9fd85 (node NULLFAIL; sig verifies only under the
    //    v1 scriptCode — proving the app signed the v7 input with OP_1).
    final scriptCode = _scriptCodeForInput(inputs[inputIndex]);
    buf.add(_varint(scriptCode.length));
    buf.add(scriptCode);

    // 6. value of the output being spent (satoshis, int64 LE)
    buf.add(_int64LE(inputs[inputIndex].valueSat));

    // 7. nSequence
    buf.add(_uint32LE(0xFFFFFFFF));

    // 8. hashOutputs
    buf.add(hashOutputs);

    // 9. nLockTime
    buf.add(_uint32LE(0));

    // 10. sighash type
    buf.add(_uint32LE(1)); // SIGHASH_ALL

    // Double SHA-256
    final first = sha256.convert(buf.toBytes());
    final second = sha256.convert(first.bytes);
    return Uint8List.fromList(second.bytes);
  }

  /// Extract the output section from an unsigned transaction.
  Uint8List _extractOutputSection(Uint8List tx, int inputCount) {
    var offset = 4; // Skip version

    // Skip input count varint
    final (inCount, inCountLen) = _readVarint(tx, offset);
    offset += inCountLen;

    // Skip all inputs
    for (var i = 0; i < inCount; i++) {
      offset += 32; // txid
      offset += 4;  // vout
      final (scriptLen, scriptLenSize) = _readVarint(tx, offset);
      offset += scriptLenSize + scriptLen; // scriptSig
      offset += 4;  // sequence
    }

    // Everything from here to locktime is outputs
    final outputStart = offset;
    final outputEnd = tx.length - 4; // Exclude locktime
    return tx.sublist(outputStart, outputEnd);
  }

  /// Parse outputs from unsigned tx for rebuilding.
  List<_RawOutput> _parseOutputs(Uint8List tx, int inputCount) {
    var offset = 4; // skip version

    // Skip input count
    final (_, inCountLen) = _readVarint(tx, offset);
    offset += inCountLen;

    // Skip inputs
    for (var i = 0; i < inputCount; i++) {
      offset += 36; // txid + vout
      final (scriptLen, scriptLenSize) = _readVarint(tx, offset);
      offset += scriptLenSize + scriptLen + 4; // scriptSig + sequence
    }

    // Read output count
    final (outCount, outCountLen) = _readVarint(tx, offset);
    offset += outCountLen;

    final outputs = <_RawOutput>[];
    for (var i = 0; i < outCount; i++) {
      final valueSat = _readInt64LE(tx, offset);
      offset += 8;
      final (spkLen, spkLenSize) = _readVarint(tx, offset);
      offset += spkLenSize;
      final spk = tx.sublist(offset, offset + spkLen);
      offset += spkLen;
      // Phase 4: CTxOut is byte-less (no nVisibility/nAssetType) — output ends at the script.
      outputs.add(_RawOutput(
        valueSat: valueSat,
        scriptPubKey: spk,
      ));
    }

    return outputs;
  }

  /// Build the signed transaction in segwit (BIP141) serialization format.
  ///
  /// Format: version + marker(0x00) + flag(0x01) + inputs (empty scriptSig)
  ///         + outputs + witness data + locktime
  String _buildWitnessTxHex(
    List<Utxo> inputs,
    Uint8List unsignedTx,
    List<List<Uint8List>> witnessStacks,
  ) {
    final buf = BytesBuilder();
    final outputs = _parseOutputs(unsignedTx, inputs.length);

    // Version — v2 for BIP68/BIP112 (CSV) support
    buf.add(_uint32LE(2));

    // Segwit marker + flag
    buf.addByte(0x00); // marker
    buf.addByte(0x01); // flag

    // Inputs (scriptSig is EMPTY for witness inputs)
    buf.add(_varint(inputs.length));
    for (var i = 0; i < inputs.length; i++) {
      buf.add(_hexToReversed(inputs[i].txid));
      buf.add(_uint32LE(inputs[i].vout));
      buf.add(_varint(0)); // empty scriptSig
      buf.add(_uint32LE(0xFFFFFFFF));
    }

    // Outputs (Phase 4: byte-less CTxOut — value + scriptPubKey, no nVisibility/nAssetType)
    buf.add(_varint(outputs.length));
    for (final output in outputs) {
      buf.add(_int64LE(output.valueSat));
      buf.add(_varint(output.scriptPubKey.length));
      buf.add(output.scriptPubKey);
    }

    // Witness data — one stack per input
    for (final stack in witnessStacks) {
      buf.add(_varint(stack.length)); // number of items
      for (final item in stack) {
        buf.add(_varint(item.length)); // item length
        buf.add(item);
      }
    }

    // Lock time
    buf.add(_uint32LE(0));

    return hex.encode(buf.toBytes());
  }

  // ── Bech32m Decoding (BIP350 compliant) ──

  /// Valid Bech32m character set.
  static const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  /// Expected HRP for each network — 'sq' on mainnet, 'ssq' on stagenet.
  /// Network-scoped so a stagenet address can never be paid from a mainnet
  /// wallet (or vice-versa): coins sent across networks are unrecoverable.
  static String _expectedHrp(SoqNetwork network) =>
      network == SoqNetwork.stagenet ? 'ssq' : 'sq';

  /// Validate a Soqucoin address without decoding.
  ///
  /// Returns `null` if valid, or an error message if invalid.
  /// Use this in the UI before calling [sendTransaction].
  static String? validateAddress(String address, SoqNetwork network) {
    if (address.isEmpty) return 'Address is empty';
    if (address.length < 14) return 'Address too short';
    if (address.length > 90) return 'Address too long'; // BIP173 limit

    // Must be all lowercase or all uppercase (not mixed)
    if (address != address.toLowerCase() && address != address.toUpperCase()) {
      return 'Mixed case not allowed in Bech32m';
    }
    final addr = address.toLowerCase();

    // Find separator
    final sepPos = addr.lastIndexOf('1');
    if (sepPos < 1 || sepPos + 7 > addr.length) {
      return 'Invalid address format';
    }

    // Validate HRP against the wallet's current network
    final hrp = addr.substring(0, sepPos);
    if (hrp != _expectedHrp(network)) {
      if (hrp == 'sq' && network == SoqNetwork.stagenet) {
        return 'This is a mainnet address — you are on stagenet';
      }
      if (hrp == 'ssq' && network == SoqNetwork.mainnet) {
        return 'This is a stagenet (test) address — you are on mainnet';
      }
      return 'Unknown address prefix: $hrp';
    }

    // Validate data characters
    final dataPart = addr.substring(sepPos + 1);
    for (final c in dataPart.codeUnits) {
      if (!_bech32Charset.contains(String.fromCharCode(c))) {
        return 'Invalid character in address: ${String.fromCharCode(c)}';
      }
    }

    // Verify Bech32m checksum
    final data = dataPart.split('').map((c) => _bech32Charset.indexOf(c)).toList();
    if (!_verifyBech32mChecksum(hrp, data)) {
      return 'Invalid checksum — address may be mistyped';
    }

    // Validate witness program length
    final payload = data.sublist(0, data.length - 6);
    if (payload.isEmpty) return 'Missing witness version';
    final program = _convertBitsStatic(payload.sublist(1), 5, 8, pad: false);
    if (program.length != 32) {
      return 'Invalid witness program length: ${program.length} (expected 32)';
    }

    // Reject witness versions this chain does not spend. A well-formed address
    // at an unsupported version is NOT a valid Soqucoin destination: paying it
    // creates an anyone-can-spend output whose funds any observer can sweep.
    // Caught here, at validation time, so nothing reaches script construction.
    final witnessVersion = payload[0];
    if (!isSupportedWitnessVersion(witnessVersion)) {
      return 'Unsupported address type (witness v$witnessVersion). '
          'Sending here would lose your funds. Soqucoin addresses are witness v1.';
    }

    return null; // Valid
  }

  /// Bech32m polymod per BIP350.
  static int _bech32Polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final b = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        chk ^= ((b >> i) & 1) != 0 ? gen[i] : 0;
      }
    }
    return chk;
  }

  /// Expand HRP for checksum calculation per BIP173/350.
  static List<int> _bech32HrpExpand(String hrp) {
    final result = <int>[];
    for (final c in hrp.codeUnits) {
      result.add(c >> 5);
    }
    result.add(0);
    for (final c in hrp.codeUnits) {
      result.add(c & 31);
    }
    return result;
  }

  /// Verify Bech32m checksum (BIP350: constant = 0x2bc830a3).
  static bool _verifyBech32mChecksum(String hrp, List<int> data) {
    const bech32mConst = 0x2bc830a3;
    final values = _bech32HrpExpand(hrp) + data;
    return _bech32Polymod(values) == bech32mConst;
  }

  /// Static version of _convertBits for use in validateAddress.
  static List<int> _convertBitsStatic(List<int> data, int fromBits, int toBits,
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

  _Bech32mDecoded _decodeBech32m(String address) {
    final addr = address.toLowerCase();

    // Validate before decoding — catches all malformed addresses and
    // enforces the network-HRP match on the tx-build path as well.
    final error = validateAddress(addr, _rpc.network);
    if (error != null) {
      throw ArgumentError('Invalid Soqucoin address: $error');
    }

    final pos = addr.lastIndexOf('1');
    final hrp = addr.substring(0, pos);
    final data = addr
        .substring(pos + 1)
        .split('')
        .map((c) => _bech32Charset.indexOf(c))
        .toList();

    // Remove checksum (last 6 chars) — already verified by validateAddress
    final payload = data.sublist(0, data.length - 6);

    // Convert from 5-bit to 8-bit (skip witness version byte)
    final witnessVersion = payload[0];
    final program =
        _convertBitsStatic(payload.sublist(1), 5, 8, pad: false);

    return _Bech32mDecoded(
      hrp: hrp,
      witnessVersion: witnessVersion,
      program: Uint8List.fromList(program),
    );
  }

  List<int> _convertBits(List<int> data, int fromBits, int toBits,
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

  // ── Push data encoding ──

  Uint8List _pushData(Uint8List data) {
    final buf = BytesBuilder();
    final len = data.length;

    if (len < 76) {
      buf.addByte(len);
    } else if (len <= 0xFF) {
      buf.addByte(0x4c); // OP_PUSHDATA1
      buf.addByte(len);
    } else if (len <= 0xFFFF) {
      buf.addByte(0x4d); // OP_PUSHDATA2
      buf.addByte(len & 0xFF);
      buf.addByte((len >> 8) & 0xFF);
    } else {
      buf.addByte(0x4e); // OP_PUSHDATA4
      buf.add(_uint32LE(len));
    }

    buf.add(data);
    return buf.toBytes();
  }

  // ── Serialization Helpers ──

  Uint8List _uint32LE(int value) {
    final bytes = Uint8List(4);
    bytes[0] = value & 0xFF;
    bytes[1] = (value >> 8) & 0xFF;
    bytes[2] = (value >> 16) & 0xFF;
    bytes[3] = (value >> 24) & 0xFF;
    return bytes;
  }

  Uint8List _int64LE(int value) {
    final bytes = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      bytes[i] = (value >> (i * 8)) & 0xFF;
    }
    return bytes;
  }

  int _readInt64LE(Uint8List data, int offset) {
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value |= data[offset + i] << (i * 8);
    }
    return value;
  }

  Uint8List _varint(int value) {
    if (value < 0xFD) {
      return Uint8List.fromList([value]);
    } else if (value <= 0xFFFF) {
      return Uint8List.fromList([0xFD, value & 0xFF, (value >> 8) & 0xFF]);
    } else if (value <= 0xFFFFFFFF) {
      final bytes = Uint8List(5);
      bytes[0] = 0xFE;
      bytes[1] = value & 0xFF;
      bytes[2] = (value >> 8) & 0xFF;
      bytes[3] = (value >> 16) & 0xFF;
      bytes[4] = (value >> 24) & 0xFF;
      return bytes;
    } else {
      final bytes = Uint8List(9);
      bytes[0] = 0xFF;
      for (var i = 0; i < 8; i++) {
        bytes[i + 1] = (value >> (i * 8)) & 0xFF;
      }
      return bytes;
    }
  }

  (int, int) _readVarint(Uint8List data, int offset) {
    final first = data[offset];
    if (first < 0xFD) return (first, 1);
    if (first == 0xFD) {
      return (data[offset + 1] | (data[offset + 2] << 8), 3);
    }
    if (first == 0xFE) {
      return (
        data[offset + 1] |
            (data[offset + 2] << 8) |
            (data[offset + 3] << 16) |
            (data[offset + 4] << 24),
        5
      );
    }
    // 0xFF — 8-byte int
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value |= data[offset + 1 + i] << (i * 8);
    }
    return (value, 9);
  }

  /// Convert hex txid string to reversed bytes (internal byte order).
  Uint8List _hexToReversed(String hexStr) {
    final bytes = hex.decode(hexStr);
    return Uint8List.fromList(bytes.reversed.toList());
  }
}


/// Internal output representation.
class _RawOutput {
  final int valueSat;
  final Uint8List scriptPubKey;
  final int visibility; // 0x00 = transparent, 0x01 = confidential
  final int assetType;  // 0x00 = SOQ, 0x01 = USDSOQ
  const _RawOutput({
    required this.valueSat,
    required this.scriptPubKey,
    this.visibility = 0x00,
    this.assetType = kAssetTypeSoq,
  });
}

/// Bech32m decode result.
class _Bech32mDecoded {
  final String hrp;
  final int witnessVersion;
  final Uint8List program;
  const _Bech32mDecoded({
    required this.hrp,
    required this.witnessVersion,
    required this.program,
  });
}

/// Thrown when the wallet doesn't have enough UTXOs for a transaction.
class InsufficientFundsException implements Exception {
  final double available;
  final double requested;

  const InsufficientFundsException({
    required this.available,
    required this.requested,
  });

  @override
  String toString() =>
      'Insufficient funds: ${available.toStringAsFixed(4)} SOQ available, '
      '${requested.toStringAsFixed(4)} SOQ requested';
}
