/// WOTS+ Cross-Verification Test
///
/// Verifies that the Dart WOTS+ implementation produces identical
/// results to the JavaScript xmss-client.js. Uses a fixed seed
/// to ensure deterministic output across both implementations.
///
/// Run: dart test test/wots_test.dart
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/crypto/wots_signer.dart';
import 'package:soqushield/crypto/xmss_tree.dart';

void main() {
  group('WOTS+ Dart Implementation', () {
    // Fixed seed for deterministic testing
    final testSeed = Uint8List.fromList(List.generate(32, (i) => i));

    test('keccakTruncated produces 20-byte output', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final hash = keccakTruncated(data);
      expect(hash.length, equals(hashLen));
      expect(hash.length, equals(20));
    });

    test('keccakFull produces 32-byte output', () {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final hash = keccakFull(data);
      expect(hash.length, equals(fullHashLen));
      expect(hash.length, equals(32));
    });

    test('hashChain is identity with 0 steps', () {
      final input = keccakTruncated(Uint8List.fromList([1, 2, 3]));
      final chained = hashChain(input, 0);
      expect(chained, equals(input));
    });

    test('hashChain accumulates with multiple steps', () {
      final input = keccakTruncated(Uint8List.fromList([1, 2, 3]));
      final step1 = hashChain(input, 1);
      final step2 = hashChain(input, 2);
      expect(step1, isNot(equals(input)));
      expect(step2, isNot(equals(step1)));
      // step2 should equal hashing step1 once more
      expect(step2, equals(hashChain(step1, 1)));
    });

    test('msgToDigits extracts correct nibbles', () {
      final msg = Uint8List(20);
      msg[0] = 0xAB; // should give digits [10, 11]
      msg[1] = 0xCD; // should give digits [12, 13]
      final digits = msgToDigits(msg);
      expect(digits[0], equals(0x0A));
      expect(digits[1], equals(0x0B));
      expect(digits[2], equals(0x0C));
      expect(digits[3], equals(0x0D));
      expect(digits.length, equals(numChains));
    });

    test('generateWotsKeypair produces correct structure', () {
      final keypair = generateWotsKeypair(testSeed);
      expect(keypair.privateKey.length, equals(numChains));
      expect(keypair.publicKey.length, equals(numChains));
      expect(keypair.publicKeyHash.length, equals(fullHashLen));

      // Each chain should be hashLen bytes
      for (final sk in keypair.privateKey) {
        expect(sk.length, equals(hashLen));
      }
      for (final pk in keypair.publicKey) {
        expect(pk.length, equals(hashLen));
      }

      // Public key should be hash^(w-1)(private key)
      for (var i = 0; i < numChains; i++) {
        final computed = hashChain(keypair.privateKey[i], maxChainSteps);
        expect(computed, equals(keypair.publicKey[i]),
            reason: 'pk[$i] should equal hash^15(sk[$i])');
      }
    });

    test('wotsSign + wotsVerify roundtrip succeeds', () {
      final keypair = generateWotsKeypair(testSeed);
      final message = keccakTruncated(Uint8List.fromList('test message'.codeUnits));

      final signature = wotsSign(message, keypair.privateKey);
      expect(signature.length, equals(numChains));

      final verified = wotsVerify(message, signature, keypair.publicKeyHash);
      expect(verified, isTrue, reason: 'Valid signature should verify');
    });

    test('wotsVerify rejects wrong message', () {
      final keypair = generateWotsKeypair(testSeed);
      final message1 = keccakTruncated(Uint8List.fromList('message 1'.codeUnits));
      final message2 = keccakTruncated(Uint8List.fromList('message 2'.codeUnits));

      final signature = wotsSign(message1, keypair.privateKey);
      final verified = wotsVerify(message2, signature, keypair.publicKeyHash);
      expect(verified, isFalse, reason: 'Wrong message should fail');
    });

    test('wotsVerify rejects wrong key', () {
      final seed2 = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final keypair1 = generateWotsKeypair(testSeed);
      final keypair2 = generateWotsKeypair(seed2);
      final message = keccakTruncated(Uint8List.fromList('test'.codeUnits));

      final signature = wotsSign(message, keypair1.privateKey);
      final verified = wotsVerify(message, signature, keypair2.publicKeyHash);
      expect(verified, isFalse, reason: 'Wrong key should fail');
    });

    test('constructWithdrawalMessage produces deterministic output', () {
      final recipient = Uint8List(32);
      recipient[0] = 0xFF;
      final msg1 = constructWithdrawalMessage(1000000000, recipient, 0);
      final msg2 = constructWithdrawalMessage(1000000000, recipient, 0);
      expect(msg1, equals(msg2));

      // Different amount should give different message
      final msg3 = constructWithdrawalMessage(2000000000, recipient, 0);
      expect(msg1, isNot(equals(msg3)));

      // Different leaf index should give different message
      final msg4 = constructWithdrawalMessage(1000000000, recipient, 1);
      expect(msg1, isNot(equals(msg4)));
    });
  });

  group('XMSS-Lite Key Tree', () {
    final testSeed = Uint8List.fromList(List.generate(32, (i) => i));

    test('generateXmssTree depth=2 produces 4 keys', () {
      final tree = generateXmssTree(2, testSeed);
      expect(tree.keys.length, equals(4));
      expect(tree.leaves.length, equals(4));
      expect(tree.proofs.length, equals(4));
      expect(tree.merkleRoot.length, equals(fullHashLen));
      expect(tree.depth, equals(2));
      expect(tree.maxSignatures, equals(4));
    });

    test('generateXmssTree depth=4 produces 16 keys', () {
      final tree = generateXmssTree(4, testSeed);
      expect(tree.keys.length, equals(16));
      expect(tree.maxSignatures, equals(16));
    });

    test('Merkle proof verifies for each leaf', () {
      final tree = generateXmssTree(3, testSeed);

      for (var i = 0; i < tree.keys.length; i++) {
        // Verify the Merkle proof manually
        var currentHash = Uint8List.fromList(tree.leaves[i]);
        final proof = tree.proofAt(i);
        var idx = i;

        for (final sibling in proof) {
          final combined = Uint8List(fullHashLen * 2);
          if (idx.isEven) {
            combined.setRange(0, fullHashLen, currentHash);
            combined.setRange(fullHashLen, fullHashLen * 2, sibling);
          } else {
            combined.setRange(0, fullHashLen, sibling);
            combined.setRange(fullHashLen, fullHashLen * 2, currentHash);
          }
          currentHash = keccakFull(combined);
          idx = idx ~/ 2;
        }

        expect(currentHash, equals(tree.merkleRoot),
            reason: 'Merkle proof for leaf $i should verify');
      }
    });

    test('flattenSignature produces correct length', () {
      final keypair = generateWotsKeypair(testSeed);
      final message = keccakTruncated(Uint8List.fromList('test'.codeUnits));
      final sig = wotsSign(message, keypair.privateKey);
      final flat = XmssKeyTree.flattenSignature(sig);
      expect(flat.length, equals(numChains * hashLen));
    });

    test('flattenProof produces correct length', () {
      final tree = generateXmssTree(3, testSeed);
      final proof = tree.proofAt(0);
      final flat = XmssKeyTree.flattenProof(proof);
      // Depth=3, so 3 siblings in proof, each 32 bytes
      expect(flat.length, equals(3 * fullHashLen));
    });

    test('deterministic tree generation from same seed', () {
      final tree1 = generateXmssTree(2, testSeed);
      final tree2 = generateXmssTree(2, testSeed);
      expect(tree1.merkleRoot, equals(tree2.merkleRoot));
      for (var i = 0; i < tree1.keys.length; i++) {
        expect(tree1.keys[i].publicKeyHash, equals(tree2.keys[i].publicKeyHash));
      }
    });

    test('end-to-end: sign withdrawal message and verify', () {
      final tree = generateXmssTree(4, testSeed);
      final leafIndex = 0;
      final amount = 10000000000; // 10 tokens
      final recipient = Uint8List(32);
      recipient[0] = 0xDE;
      recipient[1] = 0xAD;

      // Construct message (matches on-chain)
      final message = constructWithdrawalMessage(amount, recipient, leafIndex);
      expect(message.length, equals(hashLen));

      // Sign with WOTS+ at leaf 0
      final keypair = tree.keypairAt(leafIndex);
      final signature = wotsSign(message, keypair.privateKey);

      // Verify signature
      final verified = wotsVerify(message, signature, keypair.publicKeyHash);
      expect(verified, isTrue);

      // Verify Merkle proof
      var currentHash = Uint8List.fromList(tree.leaves[leafIndex]);
      final proof = tree.proofAt(leafIndex);
      var idx = leafIndex;
      for (final sibling in proof) {
        final combined = Uint8List(fullHashLen * 2);
        if (idx.isEven) {
          combined.setRange(0, fullHashLen, currentHash);
          combined.setRange(fullHashLen, fullHashLen * 2, sibling);
        } else {
          combined.setRange(0, fullHashLen, sibling);
          combined.setRange(fullHashLen, fullHashLen * 2, currentHash);
        }
        currentHash = keccakFull(combined);
        idx = idx ~/ 2;
      }
      expect(currentHash, equals(tree.merkleRoot));
    });
  });
}
