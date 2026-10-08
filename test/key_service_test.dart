import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/services/key_service.dart';
import 'package:soqushield/models/wallet_keys.dart';

void main() {
  late KeyService keyService;

  setUp(() {
    keyService = KeyService();
  });

  group('ML-DSA-44 Core Crypto', () {
    test('generates valid 24-word mnemonic', () {
      final seed = keyService.generateMnemonic();
      expect(seed.words.length, 24);
      expect(keyService.validateMnemonic(seed.mnemonic), isTrue);
    });

    test('derives keypair with correct sizes', () async {
      final seed = keyService.generateMnemonic();
      final keys = await keyService.deriveFromMnemonic(seed);

      // Verify ML-DSA-44 constant sizes (must match C++ node)
      expect(keys.publicKey.length, WalletKeys.pubKeySize,
          reason: 'Public key must be 1312 bytes (ML-DSA-44)');
      expect(keys.derivationPath, "m/44'/21329'/0'/0/0");
      expect(keys.accountIndex, 0);
    });

    test('generates Bech32m address with correct HRP', () async {
      final seed = keyService.generateMnemonic();

      // Stagenet
      final testKeys = await keyService.deriveFromMnemonic(
        seed,
        network: SoqNetwork.stagenet,
      );
      expect(testKeys.address.startsWith('ssq1'), isTrue,
          reason: 'Stagenet address must start with ssq1');
    });

    test('deterministic derivation — same seed = same address', () async {
      final seed = keyService.generateMnemonic();
      final keys1 = await keyService.deriveFromMnemonic(seed);
      final keys2 = await keyService.deriveFromMnemonic(seed);

      expect(keys1.address, keys2.address,
          reason: 'Same seed must produce same address');
      expect(keys1.publicKey, keys2.publicKey,
          reason: 'Same seed must produce same public key');
    });

    test('different account indices = different keys', () async {
      final seed = keyService.generateMnemonic();
      final keys0 = await keyService.deriveFromMnemonic(seed, accountIndex: 0);
      final keys1 = await keyService.deriveFromMnemonic(seed, accountIndex: 1);

      expect(keys0.address, isNot(keys1.address),
          reason: 'Different indices must produce different addresses');
      expect(keys0.derivationPath, "m/44'/21329'/0'/0/0");
      expect(keys1.derivationPath, "m/44'/21329'/0'/0/1");
    });

    test('sign and verify roundtrip', () async {
      final seed = keyService.generateMnemonic();

      // Derive key pair via the same native FIPS 204 pipeline as production
      final (publicKey, secretKey) = await keyService.deriveNativeKeyPair(seed);

      // Simulate a 32-byte sighash (SHA256d of a transaction)
      final sighash = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        sighash[i] = i;
      }

      final signature = keyService.signNative(secretKey, sighash);

      // Verify sizes
      expect(signature.length, WalletKeys.signatureSize,
          reason: 'Signature must be 2420 bytes (ML-DSA-44)');

      // Verify signature
      final isValid = keyService.verifyNative(publicKey, signature, sighash);
      expect(isValid, isTrue, reason: 'Signature must verify');

      // Verify with wrong message fails
      final wrongHash = Uint8List(32);
      wrongHash[0] = 0xFF;
      final isFalse2 = keyService.verifyNative(publicKey, signature, wrongHash);
      expect(isFalse2, isFalse, reason: 'Wrong message must fail verification');
    });

    test('mnemonic validation rejects garbage', () {
      expect(keyService.validateMnemonic('hello world'), isFalse);
      expect(keyService.validateMnemonic(''), isFalse);
      expect(
        keyService.validateMnemonic(
          'abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon about',
        ),
        isTrue,
        reason: 'The BIP-39 test vector mnemonic must validate',
      );
    });
  });
}
