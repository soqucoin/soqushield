// Coin selection against a fee that grows with the input count.
//
// A Dilithium input is ~3,750 bytes — about 375,000 koinu of fee at the relay
// floor — so the fee is a FUNCTION of how many coins are chosen. Selection
// used to price a guessed two inputs and the builder then re-priced the real
// count without re-selecting, so a send needing three or more inputs could
// come up short against its own fee and be refused while the wallet plainly
// held the money.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soqushield/models/utxo.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/services/rpc_service.dart';
import 'package:soqushield/services/tx_builder.dart';
import 'package:soqushield/services/tx_parser.dart';
import 'package:soqushield/services/utxo_service.dart';

import 'lite_test_support.dart';

const _address =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

/// The relay floor, in koinu/kB — what a fee is never allowed below.
const _floorPerKb = 100000;

/// What [inputCount] inputs and [outputCount] outputs cost at the floor.
int _feeAtFloor(int inputCount, int outputCount) {
  final size = 10 + (inputCount * 3750) + (outputCount * 34);
  return ((_floorPerKb * size) / 1000).ceil();
}

/// A node that quotes the relay floor and accepts whatever it is handed.
/// [broadcast] captures the raw hex the builder actually sent.
RpcService _rpc({void Function(String hex)? broadcast}) => RpcService(
      client: MockClient((req) async {
        final body = json.decode(req.body) as Map<String, dynamic>;
        switch (body['method']) {
          case 'estimatesmartfee':
            return http.Response(
                json.encode({'result': {'feerate': 0.001}, 'error': null}), 200);
          case 'sendrawtransaction':
            broadcast?.call((body['params'] as List).first as String);
            return http.Response(
                json.encode({'result': 'f' * 64, 'error': null}), 200);
          default:
            // decoderawtransaction and friends — the builder treats a failure
            // here as non-fatal bookkeeping.
            return http.Response(
                json.encode({'result': null, 'error': null}), 200);
        }
      }),
      network: SoqNetwork.mainnet,
    );

/// A wallet of [count] confirmed SOQ coins worth [valueSat] each.
Future<UtxoService> _wallet(RpcService rpc, int count, int valueSat) async {
  final utxos = UtxoService(rpc, network: SoqNetwork.mainnet);
  for (var i = 0; i < count; i++) {
    await utxos.addUtxo(Utxo(
      txid: i.toRadixString(16).padLeft(64, '0'),
      vout: 0,
      value: valueSat / 100000000,
      valueSat: valueSat,
      scriptPubKey: '5120${'bb' * 32}',
      address: _address,
      confirmations: 6,
    ));
  }
  return utxos;
}

Future<String> _send(TxBuilder b, double amountSoq) => b.sendTransaction(
      toAddress: _address,
      amountSoq: amountSoq,
      secretKey: Uint8List(WalletKeys.secKeySize),
      publicKey: Uint8List(WalletKeys.pubKeySize),
      myAddress: _address,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  group('a wallet of many small coins can spend', () {
    test('1.0 SOQ across 100 coins of 0.01 sends 0.2 SOQ', () async {
      // The exact shape that was refused: largest-first needs 21 inputs, whose
      // real fee is ~0.079 SOQ. 0.2 + 0.079 = 0.279 SOQ out of 1.0 held.
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 100, 1000000); // 0.01 SOQ each
      expect(utxos.soqBalance, closeTo(1.0, 1e-9));

      final txid = await _send(TxBuilder(rpc, utxos), 0.2);
      expect(txid, 'f' * 64);
    });

    test('3.0 SOQ across 60 coins of 0.05 sends 1.0 SOQ', () async {
      // A second shape the old code refused: it stopped at 21 inputs, priced
      // for 2, and came up short against the 21-input fee. 22 inputs covers it.
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 60, 5000000); // 0.05 SOQ each
      expect(await _send(TxBuilder(rpc, utxos), 1.0), 'f' * 64);
    });

    test('the common case — few large coins — is unchanged', () async {
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 5, 100000000); // 1 SOQ each
      expect(await _send(TxBuilder(rpc, utxos), 3.5), 'f' * 64);
    });
  });

  group('the fee the transaction pays is the fee selection priced for', () {
    test('a multi-input send deducts exactly its own fee', () async {
      String? raw;
      final rpc = _rpc(broadcast: (h) => raw = h);
      final utxos = await _wallet(rpc, 100, 1000000);
      await _send(TxBuilder(rpc, utxos), 0.2);

      // Read the broadcast transaction back with the app's own parser: the
      // fee is what went in minus what came out, and it must equal the fee
      // function evaluated at the REAL input count.
      final tx = TxParser.parse(raw!);
      final inSat = tx.inputs.length * 1000000;
      final outSat =
          tx.outputs.fold<int>(0, (sum, o) => sum + o.valueSat);
      final feePaid = inSat - outSat;

      expect(feePaid, _feeAtFloor(tx.inputs.length, tx.outputs.length),
          reason: 'the deducted fee must match the priced fee exactly');
      // Recipient + change, and the recipient gets exactly what was asked.
      expect(tx.outputs.length, 2);
      expect(tx.outputs.first.valueSat, 20000000);
      expect(outSat, inSat - feePaid);
    });
  });

  group('a refusal is honest about what is there', () {
    test('a genuinely short wallet reports its real balance', () async {
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 3, 100000000); // 3.0 SOQ
      await expectLater(
        _send(TxBuilder(rpc, utxos), 10.0),
        throwsA(isA<InsufficientFundsException>()
            .having((e) => e.available, 'available', closeTo(3.0, 1e-9))
            .having((e) => e.requested, 'requested', 10.0)),
      );
    });

    test('the figure is the wallet balance, not a partial selection total',
        () async {
      // The old message reported the running total of the coins it had picked
      // up before giving up — "0.21 SOQ available" on a 1.0 SOQ wallet — which
      // sent people hunting for funds that were never missing.
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 100, 1000000); // 1.0 SOQ
      try {
        await _send(TxBuilder(rpc, utxos), 5.0);
        fail('expected a refusal');
      } on InsufficientFundsException catch (e) {
        expect(e.available, closeTo(1.0, 1e-9));
      }
    });

    test('coins worth less than their own input fee refuse, and terminate',
        () async {
      // Each 0.001 SOQ coin costs ~0.00375 SOQ of fee to spend, so adding
      // coins makes the shortfall WIDEN. Selection must stop, not spin.
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 200, 100000); // 0.001 SOQ each = 0.2 SOQ
      await expectLater(
        _send(TxBuilder(rpc, utxos), 0.1),
        throwsA(isA<InsufficientFundsException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('UtxoService.selectUtxosForVariableFee', () {
    test('stops at the first count that covers amount + its own fee', () async {
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 10, 100000000); // 1 SOQ each

      final sel = utxos.selectUtxosForVariableFee(
          250000000, (n) => _feeAtFloor(n, 2)); // 2.5 SOQ
      expect(sel, isNotNull);
      final total = Utxo.totalValueSat(sel!);
      expect(total, greaterThanOrEqualTo(250000000 + _feeAtFloor(sel.length, 2)));
      // One coin fewer would not have covered it.
      expect(total - 100000000,
          lessThan(250000000 + _feeAtFloor(sel.length - 1, 2)));
    });

    test('a reserved coin is not offered to a second selection', () async {
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 4, 100000000);
      final first = utxos.selectUtxosForVariableFee(
          100000000, (n) => _feeAtFloor(n, 2))!;
      utxos.reserveUtxos(first);

      final second = utxos.selectUtxosForVariableFee(
          100000000, (n) => _feeAtFloor(n, 2));
      for (final u in second ?? const <Utxo>[]) {
        expect(first.map((f) => f.outpoint), isNot(contains(u.outpoint)));
      }
    });

    test('the fixed-fee overload still behaves as before', () async {
      final rpc = _rpc();
      final utxos = await _wallet(rpc, 5, 100000000);
      final sel = utxos.selectUtxos(250000000, 50000000);
      expect(Utxo.totalValueSat(sel!), greaterThanOrEqualTo(300000000));
    });
  });
}
