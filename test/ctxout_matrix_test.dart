// Copyright (c) 2026 Soqucoin Labs Inc.
// Distributed under the MIT software license.
//
// ctxout_matrix_test.dart — CTxOut serialization golden matrix (Phase 4 re-pin).
//
// Phase 4 removed the nVisibility/nAssetType extension bytes. CTxOut is now the single
// STANDARD Bitcoin format (value + scriptPubKey) — identical to the foreign/AuxPoW-parent
// encoding, so the dual-format seam is gone. This pins the byte-less format byte-identical
// to the C++ node + the Go/TS reimpls. (The pre-Phase-4 "...0101" form no longer exists.)
//
// Fixture: nValue=12345678, scriptPubKey=OP_TRUE (0x51) → "4e61bc00000000000151".

import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serialize a CTxOut in the post-Phase-4 byte-less format: value(8 LE) + CompactSize(len) + script.
Uint8List serializeCTxOut({required int value, required Uint8List scriptPubKey}) {
  final buf = BytesBuilder();
  buf.add(_int64LE(value));
  buf.add(_compactSize(scriptPubKey.length));
  buf.add(scriptPubKey);
  // Phase 4: no nVisibility/nAssetType — asset/visibility follow the witness version.
  return buf.toBytes();
}

Uint8List _int64LE(int value) {
  final bytes = Uint8List(8);
  for (var i = 0; i < 8; i++) {
    bytes[i] = (value >> (i * 8)) & 0xFF;
  }
  return bytes;
}

Uint8List _compactSize(int value) {
  if (value < 0xFD) {
    return Uint8List.fromList([value]);
  } else if (value <= 0xFFFF) {
    return Uint8List.fromList([0xFD, value & 0xFF, (value >> 8) & 0xFF]);
  } else {
    throw ArgumentError('CompactSize value too large for this test: $value');
  }
}

void main() {
  final fixtureScript = Uint8List.fromList([0x51]); // OP_TRUE
  const fixtureValue = 12345678;

  // Post-Phase-4 byte-less golden (== old SERIALIZE_TXOUT_STANDARD form; matches node + Go + TS).
  const expect_ = '4e61bc00000000000151';

  group('CTxOut Golden Matrix Cross-Pin (Phase 4)', () {
    test('byte-less format matches the cross-impl golden', () {
      final got = hex.encode(serializeCTxOut(value: fixtureValue, scriptPubKey: fixtureScript));
      expect(got, equals(expect_),
          reason: 'CROSS-PIN MISMATCH: Dart=$got want=$expect_ — serialization drift!');
    });

    test('no trailing extension bytes (value+len+script = 10 bytes)', () {
      // Phase-4 regression guard: OP_TRUE output is 10 bytes, not 12 (the old +2 is gone).
      final bytes = serializeCTxOut(value: fixtureValue, scriptPubKey: fixtureScript);
      expect(bytes.length, equals(10));
    });

    test('v7 USDSOQ holding (OP_7<32>) is byte-less too', () {
      final v7 = Uint8List.fromList([0x57, 0x20, ...List.filled(32, 0xaa)]);
      final got = hex.encode(serializeCTxOut(value: fixtureValue, scriptPubKey: v7));
      expect(got,
          equals('4e61bc0000000000225720aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
    });
  });
}
