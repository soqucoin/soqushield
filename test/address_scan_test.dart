// What a scanned code may hand the send screen: one address, and nothing
// else. The bare address the Receive screen encodes, its uppercase spelling,
// and the address behind the soqucoin: scheme are read; an amount, a label
// and a message after it are dropped unread; the other network's address is
// named as such; and anything not shaped like an address gets one fixed line,
// never its own words on the screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/services/address_scan.dart';

const _mainnet =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenet =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

void main() {
  group('AddressScan.parse', () {
    test('reads the bare address, as the Receive screen encodes it', () {
      final scan = AddressScan.parse(_mainnet, SoqNetwork.mainnet);
      expect(scan.accepted, isTrue);
      expect(scan.address, _mainnet);
      expect(scan.error, isNull);
      expect(AddressScan.parse(_stagenet, SoqNetwork.stagenet).address,
          _stagenet);
    });

    test('reads an all-uppercase spelling back as the lowercase address', () {
      final scan =
          AddressScan.parse(_mainnet.toUpperCase(), SoqNetwork.mainnet);
      expect(scan.address, _mainnet);
    });

    test('trims the whitespace a code may carry around the address', () {
      expect(AddressScan.parse('  $_mainnet\n', SoqNetwork.mainnet).address,
          _mainnet);
    });

    test('reads the address behind the soqucoin: scheme, in any case, with '
        'or without the slashes', () {
      for (final raw in [
        'soqucoin:$_mainnet',
        'SOQUCOIN:$_mainnet',
        'soqucoin://$_mainnet',
        'soqucoin:${_mainnet.toUpperCase()}',
      ]) {
        expect(AddressScan.parse(raw, SoqNetwork.mainnet).address, _mainnet,
            reason: raw);
      }
    });

    test('drops an amount, a label and a message unread', () {
      final scan = AddressScan.parse(
          'soqucoin:$_mainnet?amount=25&label=Soqucoin%20Labs'
          '&message=refund%20desk',
          SoqNetwork.mainnet);
      expect(scan.address, _mainnet);
      expect(scan.error, isNull);
    });

    test('names the network for the other network\'s address', () {
      final onMainnet = AddressScan.parse(_stagenet, SoqNetwork.mainnet);
      expect(onMainnet.accepted, isFalse);
      expect(onMainnet.error, contains('stagenet'));
      final onStagenet = AddressScan.parse(_mainnet, SoqNetwork.stagenet);
      expect(onStagenet.accepted, isFalse);
      expect(onStagenet.error, contains('mainnet'));
    });

    test('gives one fixed line for anything not shaped like an address, '
        'so a code never puts its own words on the screen', () {
      for (final raw in [
        '',
        '   ',
        'soqucoin:',
        'soqucoin:?amount=5',
        'https://example.org/pay?to=$_mainnet',
        'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        'CALL SUPPORT NOW 0800 000 000',
        'sq2$_mainnet',
      ]) {
        final scan = AddressScan.parse(raw, SoqNetwork.mainnet);
        expect(scan.accepted, isFalse, reason: raw);
        expect(scan.error, AddressScan.notAnAddress, reason: raw);
      }
    });

    test('refuses a mixed-case spelling and a wrong checksum with the '
        'validator\'s own reason', () {
      final mixed = AddressScan.parse(
          _mainnet.replaceRange(3, 6, 'P3J'), SoqNetwork.mainnet);
      expect(mixed.accepted, isFalse);
      expect(mixed.error, contains('Mixed case'));
      final wrong = AddressScan.parse(
          '${_mainnet.substring(0, _mainnet.length - 1)}m', SoqNetwork.mainnet);
      expect(wrong.accepted, isFalse);
      expect(wrong.error, contains('checksum'));
    });
  });
}
