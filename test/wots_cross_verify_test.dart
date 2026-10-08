// ignore_for_file: avoid_print
/// Cross-verification: print same test vectors as JS cross-verify-wots.js
///
/// Run: dart test test/wots_cross_verify_test.dart
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/crypto/wots_signer.dart';
import 'package:soqushield/crypto/xmss_tree.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('Cross-verification against JS xmss-client.js test vectors', () {
    final testSeed = Uint8List.fromList(List.generate(32, (i) => i));

    // Test 1: keccakTruncated
    final t1 = keccakTruncated(Uint8List.fromList([1, 2, 3, 4]));
    print('keccakTruncated([1,2,3,4]) = ${_hex(t1)}');
    expect(_hex(t1), equals('a6885b3731702da62e8e4a8f584ac46a7f6822f4'));

    // Test 2: keccakFull
    final t2 = keccakFull(Uint8List.fromList([1, 2, 3, 4]));
    print('keccakFull([1,2,3,4]) = ${_hex(t2)}');
    expect(_hex(t2), equals(
        'a6885b3731702da62e8e4a8f584ac46a7f6822f4e2ba50fba902f67b1588d23b'));

    // Test 3: hashChain
    final t3Input = keccakTruncated(Uint8List.fromList([1, 2, 3]));
    final t3 = hashChain(t3Input, 3);
    print('hashChain(keccak_t([1,2,3]), 3) = ${_hex(t3)}');
    expect(_hex(t3), equals('2c20cfbe5aa3e638cc2700046de9d966609fce77'));

    // Test 4: WOTS+ keypair
    final keypair = generateWotsKeypair(testSeed);
    print('sk[0]  = ${_hex(keypair.privateKey[0])}');
    print('pk[0]  = ${_hex(keypair.publicKey[0])}');
    print('pkHash = ${_hex(keypair.publicKeyHash)}');
    expect(_hex(keypair.privateKey[0]),
        equals('f33831ec8a7f96379ef0db745d66a8a8cb5633c5'));
    expect(_hex(keypair.publicKey[0]),
        equals('f2ecccd774f1093a11399221f9c5a105c2d6f2fe'));
    expect(_hex(keypair.publicKeyHash), equals(
        '345b31d99edb647ba26e78123eb9b5d45cf11df009fdf6f61088bf85a3aa0522'));

    // Test 5: Sign + verify
    final message = keccakTruncated(
        Uint8List.fromList('test message'.codeUnits));
    print('message = ${_hex(message)}');
    expect(_hex(message), equals('ea83cdcdd06bf61e414054115a551e23133711d0'));

    final sig = wotsSign(message, keypair.privateKey);
    print('sig[0]  = ${_hex(sig[0])}');
    expect(_hex(sig[0]), equals('89ff9614b1fdb3127bf2a0b2f99b72a15f3076e6'));

    final verified = wotsVerify(message, sig, keypair.publicKeyHash);
    expect(verified, isTrue);

    // Test 6: XMSS tree
    final tree = generateXmssTree(2, testSeed);
    print('merkleRoot = ${_hex(tree.merkleRoot)}');
    expect(_hex(tree.merkleRoot), equals(
        '2d137ac3b5b9116803efc4377a068c917cd802a136e0b6ada67f0e63554ecc60'));
    expect(_hex(tree.leaves[0]), equals(
        'e1383feb27c10b0bbdf5ec879d609afbf5c8f9b958a98371251d581861e62e9d'));
    expect(_hex(tree.leaves[1]), equals(
        'c2d726b42bbaa350d8763d157a42f0ec27d9176229bdcbeb792aeafbb0fd1ef2'));

    // Test 7: Withdrawal message
    final recipient = Uint8List(32);
    recipient[0] = 0xFF;
    final wMsg = constructWithdrawalMessage(1000000000, recipient, 0);
    print('withdrawal message = ${_hex(wMsg)}');
    expect(_hex(wMsg), equals('0b9d7bac0be843a1fbc51c0b8c006882030e1139'));

    print('\n✅ ALL CROSS-VERIFICATION VECTORS MATCH JS IMPLEMENTATION');
  });
}
