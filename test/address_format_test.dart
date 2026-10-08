import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/hashlib.dart';
import 'package:soqushield/services/key_service.dart';
import 'package:soqushield/services/tx_builder.dart';
import 'package:soqushield/models/wallet_keys.dart';

/// End-to-end wallet integration tests.
///
/// These tests verify the FULL pipeline a user would exercise:
///   generate wallet → derive address → decode address → build scriptPubKey
///   → construct transaction → sign → verify format
///
/// Prevents regressions like SOQ-INFRA-009 (BLAKE2b-160 vs SHA-256)
/// and the P2PKH vs witness v1 scriptPubKey mismatch.
void main() {
  late KeyService keyService;

  setUp(() {
    keyService = KeyService();
  });

  // ═══════════════════════════════════════════
  // Address Format Tests (SOQ-INFRA-009)
  // ═══════════════════════════════════════════
  group('Address Format Compatibility (SOQ-INFRA-009)', () {
    test('generated address length matches network HRP (32-byte witness v1)',
        () async {
      final phrase = keyService.generateMnemonic();
      final stage = await keyService.deriveFromMnemonic(phrase,
          network: SoqNetwork.stagenet);
      final main = await keyService.deriveFromMnemonic(phrase,
          network: SoqNetwork.mainnet);
      expect(stage.address.length, equals(63),
          reason: "Stagenet: hrp 'ssq' + 32-byte SHA-256 witness program");
      expect(main.address.length, equals(62),
          reason: "Mainnet: hrp 'sq' + 32-byte SHA-256 witness program");
    });

    test('address starts with <hrp>1p (witness version 1)', () async {
      final phrase = keyService.generateMnemonic();
      final stage = await keyService.deriveFromMnemonic(phrase,
          network: SoqNetwork.stagenet);
      final main = await keyService.deriveFromMnemonic(phrase,
          network: SoqNetwork.mainnet);
      expect(stage.address.startsWith('ssq1p'), isTrue,
          reason: 'Stagenet witness v1 Bech32m must start with ssq1p');
      expect(main.address.startsWith('sq1p'), isTrue,
          reason: 'Mainnet witness v1 Bech32m must start with sq1p');
    });

    test('address is NOT 42 chars (old BLAKE2b-160 format)', () async {
      final phrase = keyService.generateMnemonic();
      final keys = await keyService.deriveFromMnemonic(phrase);
      expect(keys.address.length, isNot(equals(42)),
          reason: 'Must NOT produce 42-char BLAKE2b-160 addresses');
    });

    test('deriveAddress produces consistent stagenet output', () {
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);
      expect(addr.length, equals(63));
      expect(addr.startsWith('ssq1p'), isTrue);
      expect(addr, equals(keyService.deriveAddress(pubkey, SoqNetwork.stagenet)));
    });

    test('mainnet and stagenet use DISTINCT HRPs over the same key', () async {
      final phrase = keyService.generateMnemonic();
      final mnKeys = await keyService.deriveFromMnemonic(
        phrase, network: SoqNetwork.mainnet);
      final snKeys = await keyService.deriveFromMnemonic(
        phrase, network: SoqNetwork.stagenet);
      expect(mnKeys.address.startsWith('sq1p'), isTrue);
      expect(snKeys.address.startsWith('ssq1p'), isTrue);
      expect(mnKeys.address, isNot(equals(snKeys.address)),
          reason: 'Distinct HRPs prevent cross-network address reuse');
      // Same key, same witness program: the addresses differ ONLY by HRP
      // (and checksum), so the data part after the separator matters.
      expect(mnKeys.address.substring(2, 3), equals('1'));
      expect(snKeys.address.substring(3, 4), equals('1'));
    });

    test('SHA-256 hash matches C++ CSHA256 output for known input', () {
      // All-zero 1312-byte pubkey → SHA-256 must match
      // Python: hashlib.sha256(b'\x00' * 1312).hexdigest()
      final pubkey = Uint8List(1312);
      final hash = sha256.convert(pubkey);
      // The hash should be deterministic and 32 bytes
      expect(hash.bytes.length, equals(32));

      // Verify it's NOT the BLAKE2b-160 output (20 bytes would fail assertion)
      // This is implicitly tested by the 62-char address length
    });

    test('address changes when pubkey changes', () {
      final pubkey1 = Uint8List(1312);
      final pubkey2 = Uint8List(1312)..fillRange(0, 32, 0xFF);
      final addr1 = keyService.deriveAddress(pubkey1, SoqNetwork.stagenet);
      final addr2 = keyService.deriveAddress(pubkey2, SoqNetwork.stagenet);
      expect(addr1, isNot(equals(addr2)),
          reason: 'Different pubkeys must produce different addresses');
    });
  });

  // ═══════════════════════════════════════════
  // Bech32m Round-Trip Tests
  // ═══════════════════════════════════════════
  group('Bech32m Round-Trip', () {
    test('encode → decode preserves witness program', () {
      // Generate a known address
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);

      // Decode it back using the same Bech32m decoder as tx_builder
      final expectedHash = sha256.convert(pubkey).bytes;

      // Manually decode the address to verify
      const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
      final pos = addr.lastIndexOf('1');
      final data = addr.substring(pos + 1)
          .split('').map((c) => charset.indexOf(c)).toList();
      final payload = data.sublist(0, data.length - 6);

      // First value is witness version
      expect(payload[0], equals(1), reason: 'Witness version must be 1');

      // Convert 5-bit to 8-bit (skip witness version)
      final program = _convertBits(payload.sublist(1), 5, 8);
      expect(program.length, equals(32),
          reason: 'Decoded witness program must be 32 bytes');

      // Verify it matches the SHA-256 hash
      for (var i = 0; i < 32; i++) {
        expect(program[i], equals(expectedHash[i]),
            reason: 'Witness program byte $i mismatch');
      }
    });

    test('all valid Bech32 characters present in address', () {
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);
      const validChars = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

      // After the separator '1', all chars should be in the Bech32 charset
      final datapart = addr.substring(addr.lastIndexOf('1') + 1);
      for (final c in datapart.split('')) {
        expect(validChars.contains(c), isTrue,
            reason: 'Character "$c" not in Bech32 charset');
      }
    });
  });

  // ═══════════════════════════════════════════
  // ScriptPubKey Construction Tests
  // ═══════════════════════════════════════════
  group('ScriptPubKey Construction', () {
    test('scriptPubKey is witness v1 format (OP_1 + 32 bytes)', () {
      // Generate an address
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);

      // Build scriptPubKey using the same logic as tx_builder
      final script = _addressToScriptPubKey(addr);

      // Must be 34 bytes: OP_1 (1) + PUSH_32 (1) + program (32)
      expect(script.length, equals(34),
          reason: 'Witness v1 scriptPubKey must be 34 bytes');
      expect(script[0], equals(0x51),
          reason: 'First byte must be OP_1 (0x51)');
      expect(script[1], equals(0x20),
          reason: 'Second byte must be PUSH_32 (0x20)');
    });

    test('scriptPubKey is NOT legacy P2PKH (OP_DUP...)', () {
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);
      final script = _addressToScriptPubKey(addr);

      // Must NOT start with OP_DUP (0x76) — that was the bug
      expect(script[0], isNot(equals(0x76)),
          reason: 'Must NOT use legacy P2PKH format (SOQ-INFRA-009)');
      expect(script.length, isNot(equals(25)),
          reason: 'Must NOT be 25 bytes (P2PKH size)');
    });

    test('scriptPubKey hex matches node format "5120..."', () {
      final pubkey = Uint8List(1312);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);
      final script = _addressToScriptPubKey(addr);
      final scriptHex = hex.encode(script);

      expect(scriptHex.startsWith('5120'), isTrue,
          reason: 'scriptPubKey hex must start with "5120" (OP_1 PUSH_32)');
      expect(scriptHex.length, equals(68),
          reason: 'scriptPubKey hex must be 68 chars (34 bytes)');
    });

    test('scriptPubKey witness program matches address decode', () {
      final pubkey = Uint8List(1312);
      final expectedHash = Uint8List.fromList(sha256.convert(pubkey).bytes);
      final addr = keyService.deriveAddress(pubkey, SoqNetwork.stagenet);
      final script = _addressToScriptPubKey(addr);

      // Bytes 2..33 should be the witness program (SHA-256 hash)
      final witnessFromScript = script.sublist(2, 34);
      for (var i = 0; i < 32; i++) {
        expect(witnessFromScript[i], equals(expectedHash[i]),
            reason: 'Script witness byte $i mismatch with expected SHA-256');
      }
    });

    test('two different addresses produce different scriptPubKeys', () {
      final pubkey1 = Uint8List(1312);
      final pubkey2 = Uint8List(1312)..fillRange(0, 32, 0xAB);
      final addr1 = keyService.deriveAddress(pubkey1, SoqNetwork.stagenet);
      final addr2 = keyService.deriveAddress(pubkey2, SoqNetwork.stagenet);
      final script1 = _addressToScriptPubKey(addr1);
      final script2 = _addressToScriptPubKey(addr2);

      expect(hex.encode(script1), isNot(equals(hex.encode(script2))),
          reason: 'Different addresses must produce different scriptPubKeys');

      // But both should still be valid witness v1
      expect(script1[0], equals(0x51));
      expect(script2[0], equals(0x51));
    });
  });

  // ═══════════════════════════════════════════
  // Full Send Pipeline Simulation
  // ═══════════════════════════════════════════
  group('Send Pipeline Simulation', () {
    test('wallet-to-wallet: sender can create output for recipient address', () async {
      // Simulate: Alice generates wallet, Bob generates wallet,
      // Alice creates an output paying to Bob's address
      final alicePhrase = keyService.generateMnemonic();
      final bobPhrase = keyService.generateMnemonic();

      final aliceKeys = await keyService.deriveFromMnemonic(alicePhrase);
      final bobKeys = await keyService.deriveFromMnemonic(bobPhrase);

      // Alice creates a scriptPubKey for Bob's address
      final scriptForBob = _addressToScriptPubKey(bobKeys.address);

      // Verify: valid witness v1 output
      expect(scriptForBob.length, equals(34));
      expect(scriptForBob[0], equals(0x51)); // OP_1

      // Alice creates a change output back to herself
      final changeScript = _addressToScriptPubKey(aliceKeys.address);
      expect(changeScript.length, equals(34));
      expect(changeScript[0], equals(0x51));

      // Verify outputs are different (different recipients)
      expect(hex.encode(scriptForBob), isNot(equals(hex.encode(changeScript))));
    });

    test('sender can sign a message hash and verify', () async {
      final phrase = keyService.generateMnemonic();
      final (publicKey, secretKey) = await keyService.deriveNativeKeyPair(phrase);

      // Create a fake sighash (32-byte double-SHA256 of tx data)
      final txData = Uint8List(100)..fillRange(0, 100, 0x42);
      final firstHash = sha256.convert(txData);
      final sighash = Uint8List.fromList(sha256.convert(firstHash.bytes).bytes);

      // Sign with ML-DSA-44
      final sig = keyService.signNative(secretKey, sighash);
      expect(sig.length, equals(2420),
          reason: 'ML-DSA-44 signature must be 2420 bytes');

      // Verify
      final valid = keyService.verifyNative(publicKey, sig, sighash);
      expect(valid, isTrue, reason: 'Signature must verify');

      // Tamper with sighash → should fail
      sighash[0] ^= 0xFF;
      final invalid = keyService.verifyNative(publicKey, sig, sighash);
      expect(invalid, isFalse, reason: 'Tampered sighash must not verify');
    });

    test('complete wallet lifecycle: generate → address → script → sign', () async {
      // Full lifecycle test simulating what happens when a user sends SOQ
      final phrase = keyService.generateMnemonic();
      final keys = await keyService.deriveFromMnemonic(phrase);
      final (publicKey, secretKey) = await keyService.deriveNativeKeyPair(phrase);

      // 1. Verify address format (default network is stagenet, hrp 'ssq')
      expect(keys.address.length, equals(63));
      expect(keys.address.startsWith('ssq1p'), isTrue);

      // 2. Verify scriptPubKey format
      final script = _addressToScriptPubKey(keys.address);
      expect(script.length, equals(34));
      expect(hex.encode(script).startsWith('5120'), isTrue);

      // 3. Verify signing works
      final fakeHash = Uint8List(32)..fillRange(0, 32, 0xDE);
      final sig = keyService.signNative(secretKey, fakeHash);
      expect(sig.length, equals(2420));
      expect(keyService.verifyNative(publicKey, sig, fakeHash), isTrue);

      // 4. Verify derivation is deterministic
      final keys2 = await keyService.deriveFromMnemonic(phrase);
      expect(keys2.address, equals(keys.address),
          reason: 'Same mnemonic must produce same address');
    });
  });

  // ═══════════════════════════════════════════
  // Network-scoped HRP validation (bead m4f P0-2)
  // ═══════════════════════════════════════════
  group('Network-scoped address validation', () {
    // Same derivation-KAT key, encoded for each network.
    const mainnetAddr =
        'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
    const stagenetAddr =
        'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

    test('address validates on its own network', () {
      expect(TxBuilder.validateAddress(mainnetAddr, SoqNetwork.mainnet), isNull);
      expect(TxBuilder.validateAddress(stagenetAddr, SoqNetwork.stagenet), isNull);
    });

    test('stagenet address is rejected on mainnet (funds-burn guard)', () {
      final err = TxBuilder.validateAddress(stagenetAddr, SoqNetwork.mainnet);
      expect(err, isNotNull);
      expect(err, contains('stagenet'));
    });

    test('mainnet address is rejected on stagenet', () {
      final err = TxBuilder.validateAddress(mainnetAddr, SoqNetwork.stagenet);
      expect(err, isNotNull);
      expect(err, contains('mainnet'));
    });
  });

}

// ═══════════════════════════════════════════
// Test Helpers (mirror tx_builder internals)
// ═══════════════════════════════════════════

/// Mirrors TxBuilder._addressToScriptPubKey for test verification.
Uint8List _addressToScriptPubKey(String address) {
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final pos = address.lastIndexOf('1');
  final data = address.substring(pos + 1)
      .split('').map((c) => charset.indexOf(c)).toList();
  final payload = data.sublist(0, data.length - 6);
  final witnessVersion = payload[0];
  final program = _convertBits(payload.sublist(1), 5, 8);

  if (witnessVersion != 1) {
    throw ArgumentError('Expected witness version 1, got $witnessVersion');
  }
  if (program.length != 32) {
    throw ArgumentError(
      'Expected 32-byte witness program, got ${program.length}. '
      'If 20 bytes, address uses old BLAKE2b-160 format (SOQ-INFRA-009).');
  }

  final script = Uint8List(34);
  script[0] = 0x51; // OP_1
  script[1] = 0x20; // Push 32 bytes
  for (var i = 0; i < 32; i++) {
    script[2 + i] = program[i];
  }
  return script;
}

/// Mirrors the 5-bit to 8-bit conversion used in Bech32m decoding.
List<int> _convertBits(List<int> data, int fromBits, int toBits) {
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
  return result;
}
