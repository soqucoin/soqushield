// Copyright (c) 2026 Soqucoin Labs Inc.
// Distributed under the MIT software license.
//
// v7_holding_test.dart — Tests for v7 USDSOQ holding support in the Dart wallet.
// Covers re-keying (OP_1 → OP_7), version-aware SPK construction, passthrough
// for existing v7 addresses, rejection of invalid versions, and defense-in-depth
// asset classification from scriptPubKey.

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert/convert.dart';
import 'package:soqushield/models/utxo.dart';
import 'package:soqushield/services/tx_builder.dart';
import 'package:soqushield/services/rpc_service.dart';
import 'package:soqushield/services/utxo_service.dart';

void main() {
  // Helper: build a 32-byte program filled with a repeated byte.
  Uint8List prog(int fill) => Uint8List.fromList(List.filled(32, fill));

  group('assetTypeFromScript', () {
    test('v7 scriptPubKey (5720...) is classified as USDSOQ', () {
      // OP_7 (0x57) + PUSH_32 (0x20) + 32 bytes = 68 hex chars
      final spkHex = '5720${hex.encode(prog(0xaa))}';
      expect(assetTypeFromScript(spkHex), AssetType.usdsoq);
    });

    test('v1 scriptPubKey (5120...) is classified as SOQ', () {
      final spkHex = '5120${hex.encode(prog(0xbb))}';
      expect(assetTypeFromScript(spkHex), AssetType.soq);
    });

    test('v5 authority marker (5520...) is classified as SOQ', () {
      // Authority markers are NOT USDSOQ holdings — they are value-0 markers.
      final spkHex = '5520${hex.encode(prog(0xcc))}';
      expect(assetTypeFromScript(spkHex), AssetType.soq);
    });

    test('empty scriptPubKey is classified as SOQ', () {
      expect(assetTypeFromScript(''), AssetType.soq);
    });

    test('short scriptPubKey is classified as SOQ', () {
      expect(assetTypeFromScript('5720aa'), AssetType.soq);
    });
  });

  group('_classifyAsset (combined classifier)', () {
    test('byte=1 wins even if script is v1', () {
      final spkHex = '5120${hex.encode(prog(0x11))}';
      // _classifyAsset is private, but we test it through Utxo.fromTxOut
      final utxo = Utxo.fromTxOut('a' * 64, 0, {
        'value': 1.0,
        'confirmations': 6,
        'assetType': 1,
        'scriptPubKey': {'hex': spkHex, 'addresses': ['test']},
      });
      expect(utxo.assetType, AssetType.usdsoq);
    });

    test('byte=0 but v7 script → USDSOQ (defense-in-depth)', () {
      final spkHex = '5720${hex.encode(prog(0x22))}';
      final utxo = Utxo.fromTxOut('b' * 64, 0, {
        'value': 2.0,
        'confirmations': 6,
        'assetType': 0, // Node reports SOQ, but script says v7
        'scriptPubKey': {'hex': spkHex, 'addresses': ['test']},
      });
      expect(utxo.assetType, AssetType.usdsoq);
    });

    test('byte=null but v7 script → USDSOQ', () {
      final spkHex = '5720${hex.encode(prog(0x33))}';
      final utxo = Utxo.fromTxOut('c' * 64, 0, {
        'value': 3.0,
        'confirmations': 6,
        // assetType omitted entirely
        'scriptPubKey': {'hex': spkHex, 'addresses': ['test']},
      });
      expect(utxo.assetType, AssetType.usdsoq);
    });

    test('byte=0 and v1 script → SOQ', () {
      final spkHex = '5120${hex.encode(prog(0x44))}';
      final utxo = Utxo.fromTxOut('d' * 64, 0, {
        'value': 4.0,
        'confirmations': 6,
        'assetType': 0,
        'scriptPubKey': {'hex': spkHex, 'addresses': ['test']},
      });
      expect(utxo.assetType, AssetType.soq);
    });
  });

  group('witness version constants', () {
    test('kOpWitnessV1 is 0x51', () {
      expect(kOpWitnessV1, 0x51);
    });

    test('kOpWitnessV7 is 0x57', () {
      expect(kOpWitnessV7, 0x57);
    });
  });

  // Behaviour tests for the actual send-path re-keying on TxBuilder (not a copy).
  // Exercised via @visibleForTesting hooks; the helpers are pure (no RPC/UTXO use).
  group('TxBuilder send-path re-keying (behaviour)', () {
    final rpc = RpcService();
    final tb = TxBuilder(rpc, UtxoService(rpc));

    Uint8List v1Spk(int fill) {
      final s = Uint8List(34);
      s[0] = 0x51; // OP_1
      s[1] = 0x20; // PUSH_32
      s.fillRange(2, 34, fill);
      return s;
    }

    test('OP_1 holding re-keys to OP_7, same 32-byte program', () {
      final v1 = v1Spk(0xab);
      final v7 = tb.debugRekeyToV7Holding(v1);
      expect(v7.length, 34);
      expect(v7[0], 0x57); // OP_7
      expect(v7[1], 0x20);
      expect(v7.sublist(2), equals(v1.sublist(2))); // program unchanged
    });

    test('existing OP_7 holding passes through unchanged', () {
      final v7in = Uint8List.fromList(v1Spk(0xcd))..[0] = 0x57;
      final out = tb.debugRekeyToV7Holding(v7in);
      expect(out, equals(v7in));
    });

    test('rejects a non-v1/v7 version (e.g. OP_5 authority)', () {
      final v5 = Uint8List.fromList(v1Spk(0x11))..[0] = 0x55;
      expect(() => tb.debugRekeyToV7Holding(v5), throwsArgumentError);
    });

    test('rejects wrong length and wrong push opcode', () {
      expect(() => tb.debugRekeyToV7Holding(Uint8List.fromList([0x51, 0x20])),
          throwsArgumentError);
      final badPush = v1Spk(0x22)..[1] = 0x21; // not PUSH_32
      expect(() => tb.debugRekeyToV7Holding(badPush), throwsArgumentError);
    });

    // REGRESSION (live bug daf9fd85): the BIP143 scriptCode for a USDSOQ input MUST be
    // OP_7<program> — the node verifies a v7 holding against its real v7 scriptPubKey, so
    // signing against the stored v1 form (OP_1) yields the wrong sighash → NULLFAIL →
    // the tx relays but can NEVER be mined. The tracker often stores the v1 SPK for a
    // USDSOQ coin (assetType is refreshed from chain, the stored SPK is not re-keyed), so
    // the scriptCode must be derived from assetType, not the stored prefix.
    Utxo utxo(String spkHex, AssetType asset) => Utxo(
          txid: '00' * 32,
          vout: 0,
          value: 10.0,
          valueSat: 1000000000,
          scriptPubKey: spkHex,
          address: 'ssq1ptest',
          assetType: asset,
        );

    test('USDSOQ input stored as v1 (OP_1) is SIGNED against v7 (OP_7) scriptCode', () {
      final v1Hex = '5120${hex.encode(prog(0xab))}';
      final sc = tb.debugScriptCodeForInput(utxo(v1Hex, AssetType.usdsoq));
      expect(sc[0], 0x57, reason: 'v7 USDSOQ input must sign against OP_7 scriptCode');
      expect(sc[1], 0x20);
      expect(sc.sublist(2), equals(prog(0xab))); // same program
    });

    test('USDSOQ input already stored as v7 signs against v7 (idempotent)', () {
      final v7Hex = '5720${hex.encode(prog(0xac))}';
      final sc = tb.debugScriptCodeForInput(utxo(v7Hex, AssetType.usdsoq));
      expect(sc[0], 0x57);
      expect(sc.sublist(2), equals(prog(0xac)));
    });

    test('SOQ input signs against its stored v1 (OP_1) scriptCode unchanged', () {
      final v1Hex = '5120${hex.encode(prog(0xbd))}';
      final sc = tb.debugScriptCodeForInput(utxo(v1Hex, AssetType.soq));
      expect(sc[0], 0x51, reason: 'a SOQ input must NOT be re-keyed to v7');
      expect(sc.sublist(2), equals(prog(0xbd)));
    });

    // NOTE: the v1-address → OP_1 leg of the send chain (debugAddressToScriptPubKey)
    // needs native Dilithium key derivation to mint a real address, which isn't loaded
    // under plain `flutter test`. It's covered by address_format_test (run where the FFI
    // is available); for v1 the version-aware refactor is identity (0x50+1 == 0x51).
  });
}
