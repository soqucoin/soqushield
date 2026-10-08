import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/utxo.dart';
import 'package:soqushield/models/transaction.dart';

void main() {
  group('UTXO Model', () {
    test('creates from JSON round-trip', () {
      final utxo = Utxo(
        txid: 'a' * 64,
        vout: 0,
        value: 100.0,
        valueSat: 10000000000,
        scriptPubKey: '76a914${'bb' * 20}88ac',
        address: 'sq1test123',
        height: 1000,
        confirmations: 6,
      );

      final json = utxo.toJson();
      final restored = Utxo.fromJson(json);

      expect(restored.txid, utxo.txid);
      expect(restored.vout, utxo.vout);
      expect(restored.value, utxo.value);
      expect(restored.valueSat, utxo.valueSat);
      expect(restored.scriptPubKey, utxo.scriptPubKey);
      expect(restored.address, utxo.address);
      expect(restored.height, utxo.height);
      expect(restored.confirmations, utxo.confirmations);
      expect(restored.locked, false);
    });

    test('outpoint format is correct', () {
      final utxo = Utxo(
        txid: 'ab' * 32,
        vout: 3,
        value: 50.0,
        valueSat: 5000000000,
        scriptPubKey: '',
        address: '',
      );

      expect(utxo.outpoint, '${'ab' * 32}:3');
    });

    test('totalValue sums correctly', () {
      final utxos = [
        Utxo(txid: 'a' * 64, vout: 0, value: 100.0, valueSat: 10000000000,
            scriptPubKey: '', address: ''),
        Utxo(txid: 'b' * 64, vout: 1, value: 50.5, valueSat: 5050000000,
            scriptPubKey: '', address: ''),
        Utxo(txid: 'c' * 64, vout: 0, value: 0.001, valueSat: 100000,
            scriptPubKey: '', address: ''),
      ];

      expect(Utxo.totalValue(utxos), closeTo(150.501, 0.0001));
      expect(Utxo.totalValueSat(utxos), 15050100000);
    });

    test('equality by outpoint', () {
      final u1 = Utxo(txid: 'a' * 64, vout: 0, value: 100.0,
          valueSat: 10000000000, scriptPubKey: '', address: '');
      final u2 = Utxo(txid: 'a' * 64, vout: 0, value: 50.0,
          valueSat: 5000000000, scriptPubKey: '', address: '');
      final u3 = Utxo(txid: 'a' * 64, vout: 1, value: 100.0,
          valueSat: 10000000000, scriptPubKey: '', address: '');

      expect(u1 == u2, true);  // Same outpoint
      expect(u1 == u3, false); // Different vout
    });

    test('copyWith preserves fields', () {
      final utxo = Utxo(
        txid: 'a' * 64,
        vout: 0,
        value: 100.0,
        valueSat: 10000000000,
        scriptPubKey: 'aabbcc',
        address: 'sq1addr',
        confirmations: 3,
        locked: false,
      );

      final locked = utxo.copyWith(locked: true);
      expect(locked.locked, true);
      expect(locked.confirmations, 3);
      expect(locked.value, 100.0);

      final confirmed = utxo.copyWith(confirmations: 10);
      expect(confirmed.confirmations, 10);
      expect(confirmed.locked, false);
    });
  });

  group('Transaction Model', () {
    test('parses RPC response', () {
      final rpcData = {
        'txid': 'ff' * 32,
        'version': 1,
        'locktime': 0,
        'vin': [
          {
            'txid': 'aa' * 32,
            'vout': 0,
            'scriptSig': {'hex': 'deadbeef'},
            'sequence': 4294967295,
          },
        ],
        'vout': [
          {
            'value': 50.0,
            'n': 0,
            'scriptPubKey': {
              'hex': '76a914${'bb' * 20}88ac',
              'type': 'pubkeyhash',
              'addresses': ['sq1recipient'],
            },
          },
          {
            'value': 49.999,
            'n': 1,
            'scriptPubKey': {
              'hex': '76a914${'cc' * 20}88ac',
              'type': 'pubkeyhash',
              'addresses': ['sq1change'],
            },
          },
        ],
        'confirmations': 12,
        'blockhash': 'dd' * 32,
      };

      final tx = SoqTransaction.fromRpc(rpcData);

      expect(tx.txid, 'ff' * 32);
      expect(tx.version, 1);
      expect(tx.inputs.length, 1);
      expect(tx.outputs.length, 2);
      expect(tx.confirmations, 12);

      expect(tx.inputs[0].txid, 'aa' * 32);
      expect(tx.inputs[0].scriptSig, 'deadbeef');

      expect(tx.outputs[0].value, 50.0);
      expect(tx.outputs[0].addresses, ['sq1recipient']);
      expect(tx.outputs[1].value, 49.999);
      expect(tx.outputs[1].addresses, ['sq1change']);
    });

    test('parses coinbase transaction', () {
      final rpcData = {
        'txid': 'ee' * 32,
        'version': 1,
        'locktime': 0,
        'vin': [
          {
            'coinbase': '0123456789',
            'sequence': 4294967295,
          },
        ],
        'vout': [
          {
            'value': 500000.0,
            'n': 0,
            'scriptPubKey': {
              'hex': '76a914${'dd' * 20}88ac',
              'type': 'pubkeyhash',
              'addresses': ['sq1miner'],
            },
          },
        ],
      };

      final tx = SoqTransaction.fromRpc(rpcData);
      expect(tx.inputs[0].isCoinbase, true);
      expect(tx.outputs[0].valueSat, 50000000000000);
    });

    test('totalOutput sums correctly', () {
      final tx = SoqTransaction(
        txid: 'ab' * 32,
        version: 1,
        lockTime: 0,
        inputs: [],
        outputs: [
          TxOutput(value: 100.0, valueSat: 10000000000, n: 0,
              scriptPubKey: '', addresses: ['addr1']),
          TxOutput(value: 50.5, valueSat: 5050000000, n: 1,
              scriptPubKey: '', addresses: ['addr2']),
        ],
      );

      expect(tx.totalOutput, closeTo(150.5, 0.001));
      expect(tx.totalOutputSat, 15050000000);
    });
  });

  group('Fee Estimate', () {
    test('display format', () {
      const fee = FeeEstimate(feePerKb: 0.01, estimatedFeeSat: 75000, confTarget: 6);
      expect(fee.displayFee, '0.0008 SOQ');
    });
  });
}
