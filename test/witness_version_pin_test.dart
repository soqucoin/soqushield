import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/services/tx_builder.dart';
import 'package:soqushield/models/wallet_keys.dart';

/// Witness-version pin — bead wallet-sdk-witness-version-pin-u38l.
///
/// Every Soqucoin witness version shares the same HRP (`sq` / `ssq`), so the
/// HRP + 32-byte-program check this wallet performed accepted an address at ANY
/// witness version 0-16. A version with no active consensus rule is
/// anyone-can-spend under BIP-141, so paying such an address is a loss-of-funds
/// path: the payment confirms and any observer can then sweep it.
///
/// The mining pool already pins this (soqupool-server/bitcoin/soqucoin.go,
/// bead gp9); the fix never propagated to this wallet or to the SDK.
///
/// The v2 case is the one that motivated it: PAT commits to signatures rather
/// than verifying them, so a witness-v2 output authorizes nothing at all
/// (bead pat-v2-anyone-can-spend-ae6u — proven against the real VerifyScript).
///
/// These tests craft GENUINE checksum-valid addresses at each witness version,
/// which is exactly what an attacker or a buggy tool would hand the wallet.

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const int _bech32mConst = 0x2bc830a3;

int _polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  int chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (int i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= gen[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) {
  final ret = <int>[];
  for (final c in hrp.codeUnits) {
    ret.add(c >> 5);
  }
  ret.add(0);
  for (final c in hrp.codeUnits) {
    ret.add(c & 31);
  }
  return ret;
}

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  int acc = 0, bits = 0;
  final ret = <int>[];
  final maxv = (1 << to) - 1;
  for (final v in data) {
    acc = (acc << from) | v;
    bits += from;
    while (bits >= to) {
      bits -= to;
      ret.add((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) ret.add((acc << (to - bits)) & maxv);
  return ret;
}

/// Builds a real, checksum-valid bech32m address at an arbitrary witness
/// version — the honest way to produce the input under test.
String craftAddress(String hrp, int witnessVersion) {
  final program = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final data = <int>[witnessVersion] + _convertBits(program, 8, 5, true);
  final values = _hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0];
  final mod = _polymod(values) ^ _bech32mConst;
  final checksum = <int>[for (int i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  final sb = StringBuffer(hrp)..write('1');
  for (final d in data + checksum) {
    sb.write(_charset[d]);
  }
  return sb.toString();
}

void main() {
  group('Witness-version pin (loss-of-funds guard)', () {
    test('a crafted address is otherwise well-formed (control)', () {
      // v1 must pass, proving the crafting helper produces valid addresses and
      // that any rejection below is about the VERSION, not a malformed input.
      final v1 = craftAddress('sq', 1);
      expect(TxBuilder.validateAddress(v1, SoqNetwork.mainnet), isNull,
          reason: 'crafted v1 address should validate — helper is sound');
    });

    test('REJECTS witness v2 (PAT attestation — authorizes nothing)', () {
      final v2 = craftAddress('sq', 2);
      final err = TxBuilder.validateAddress(v2, SoqNetwork.mainnet);

      expect(err, isNotNull,
          reason: 'a v2 address was accepted — paying it would lose the funds '
              '(bead pat-v2-anyone-can-spend-ae6u)');
      expect(err, contains('v2'),
          reason: 'the error must name the offending version');
      expect(err!.toLowerCase(), contains('lose'),
          reason: 'the user must be told this loses funds, not just that it is invalid');
    });

    test('rejects every unsupported version, accepts exactly v1/v5/v7', () {
      for (int v = 0; v <= 16; v++) {
        final addr = craftAddress('sq', v);
        final err = TxBuilder.validateAddress(addr, SoqNetwork.mainnet);

        if (isSupportedWitnessVersion(v)) {
          expect(err, isNull, reason: 'v$v is supported but was rejected: $err');
        } else {
          expect(err, isNotNull,
              reason: 'v$v is NOT supported but was accepted — loss-of-funds path');
        }
      }
    });

    test('the supported set is exactly {1, 5, 7} (drift detector)', () {
      // Widening this set without a consensus rule that makes the version's
      // outputs require real authorization is how the v2 hazard was created.
      expect(kSupportedWitnessVersions, equals({1, 5, 7}));
      for (int v = 0; v <= 16; v++) {
        expect(isSupportedWitnessVersion(v), equals(const {1, 5, 7}.contains(v)),
            reason: 'v$v support flag drifted from the ratified set');
      }
    });

    test('stagenet is pinned too — a test network is a live trap as well', () {
      final v2 = craftAddress('ssq', 2);
      expect(TxBuilder.validateAddress(v2, SoqNetwork.stagenet), isNotNull,
          reason: 'v2 must be refused on stagenet as well as mainnet');
    });
  });
}
