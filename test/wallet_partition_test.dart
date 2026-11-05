// The cached coin set and the transaction history partition by WALLET.
//
// ⛔ Until this, both were keyed by network alone. The coin set is what the
// transaction builder selects inputs from, so a second wallet reading the
// first wallet's partition is offered outputs it holds no key for — it
// cannot sign them, and the balance it shows is not the balance it can
// spend. The history under the wrong wallet is another wallet's payment
// record, read by whoever opens this one.
//
// The wallet that predates the registry keeps the un-prefixed keys. Nothing
// stored before the registry moves, so there is no migration to half-finish.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soqushield/models/utxo.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/rpc_service.dart';
import 'package:soqushield/services/tx_history_service.dart';
import 'package:soqushield/services/utxo_service.dart';

import 'lite_test_support.dart';

class _OfflineRpc extends RpcService {
  @override
  Future<Map<String, dynamic>?> getTxOut(String txid, int vout,
          {bool includeMempool = true}) async =>
      null;
}

Utxo _coin(String txid, double soq) => Utxo(
      txid: txid * 32,
      vout: 0,
      value: soq,
      valueSat: (soq * 100000000).round(),
      scriptPubKey: '5120${'00' * 32}',
      address: 'sq1test',
      height: 100,
      confirmations: 10,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    TxHistoryService.setWallet(WalletRecord.primaryId);
    TxHistoryService.setNetwork(SoqNetwork.mainnet);
  });

  group('the scoping rule', () {
    test('the primary wallet passes every key through unchanged', () {
      expect(WalletRecord.scopeKey(WalletRecord.primaryId, 'soq_mnemonic_v2'),
          'soq_mnemonic_v2');
      expect(
          WalletRecord.scopeKey(
              WalletRecord.primaryId, 'soq_utxo_set_mainnet'),
          'soq_utxo_set_mainnet',
          reason: 'nothing written before the registry moves');
    });

    test('any other wallet gets its own prefix', () {
      expect(WalletRecord.scopeKey('w2', 'soq_utxo_set_mainnet'),
          'soq_w_w2_soq_utxo_set_mainnet');
    });

    test('two wallets never share a key', () {
      final keys = {
        for (final id in [WalletRecord.primaryId, 'w2', 'w3'])
          WalletRecord.scopeKey(id, 'soq_utxo_set_mainnet')
      };
      expect(keys, hasLength(3));
    });
  });

  group('the cached coin set', () {
    test('a second wallet is not offered the first wallet\'s coins', () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.addUtxo(_coin('aa', 5.0));
      expect(svc.soqBalance, closeTo(5.0, 1e-9));
      expect(secureStore['soq_utxo_set_mainnet'], isNotNull,
          reason: 'the primary wallet writes the un-prefixed key');

      await svc.setWallet('w2');

      expect(svc.utxos, isEmpty,
          reason: 'the second wallet holds no key for those outputs');
      expect(svc.soqBalance, 0);
    });

    test('the first wallet still finds its coins on the way back', () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.addUtxo(_coin('aa', 5.0));
      await svc.setWallet('w2');
      await svc.addUtxo(_coin('bb', 2.0));

      await svc.setWallet(WalletRecord.primaryId);
      expect(svc.soqBalance, closeTo(5.0, 1e-9));
      expect(svc.utxos.single.txid, 'aa' * 32);
    });

    test('the second wallet writes under its own key, not the first\'s',
        () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.setWallet('w2');
      await svc.addUtxo(_coin('bb', 2.0));

      expect(secureStore['soq_w_w2_soq_utxo_set_mainnet'], isNotNull);
      expect(secureStore['soq_utxo_set_mainnet'], isNull,
          reason: "a second wallet must not write into the first's partition");
    });

    test('the partitions are per wallet AND per network', () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.setWallet('w2');
      await svc.addUtxo(_coin('bb', 2.0));
      await svc.setNetwork(SoqNetwork.stagenet);
      expect(svc.utxos, isEmpty);
      await svc.addUtxo(_coin('cc', 9.0));

      expect(secureStore['soq_w_w2_soq_utxo_set_mainnet'], isNotNull);
      expect(secureStore['soq_w_w2_soq_utxo_set_stagenet'], isNotNull);
      expect(secureStore['soq_utxo_set_mainnet'], isNull);
      expect(secureStore['soq_utxo_set_stagenet'], isNull);
    });

    test('a wipe of every network takes only the open wallet\'s coins',
        () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.addUtxo(_coin('aa', 5.0));
      await svc.setWallet('w2');
      await svc.addUtxo(_coin('bb', 2.0));

      await svc.clearAll();

      expect(secureStore['soq_w_w2_soq_utxo_set_mainnet'], isNull);
      expect(secureStore['soq_utxo_set_mainnet'], isNotNull,
          reason: 'the other wallets on the device are not being replaced');
    });

    test('an instance never told otherwise behaves as it always has', () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.addUtxo(_coin('aa', 5.0));
      expect(svc.walletId, WalletRecord.primaryId);
      expect(secureStore.keys, contains('soq_utxo_set_mainnet'));
    });

    test('opening the wallet already open reloads nothing', () async {
      final svc = UtxoService(_OfflineRpc(), network: SoqNetwork.mainnet);
      await svc.addUtxo(_coin('aa', 5.0));
      await svc.setWallet(WalletRecord.primaryId);
      expect(svc.soqBalance, closeTo(5.0, 1e-9),
          reason: 'the in-memory set is not dropped for a no-op switch');
    });
  });

  group('the transaction history', () {
    WalletTransaction tx(String txid, double amount) => WalletTransaction(
          txid: txid * 32,
          type: TxType.received,
          amount: amount,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          confirmations: 3,
        );

    test('a second wallet opens on an empty feed', () async {
      await TxHistoryService.save([tx('aa', 2.0)]);
      expect(await TxHistoryService.load(), hasLength(1));

      TxHistoryService.setWallet('w2');
      expect(await TxHistoryService.load(), isEmpty,
          reason: "the first wallet's payments are not this wallet's record");
    });

    test('each wallet keeps its own rows', () async {
      await TxHistoryService.save([tx('aa', 2.0)]);
      TxHistoryService.setWallet('w2');
      await TxHistoryService.save([tx('bb', 9.0)]);

      TxHistoryService.setWallet(WalletRecord.primaryId);
      expect((await TxHistoryService.load()).single.amount, 2.0);
      TxHistoryService.setWallet('w2');
      expect((await TxHistoryService.load()).single.amount, 9.0);
    });

    test('the primary wallet keeps the key earlier builds wrote', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'soqshield_tx_history_mainnet',
          jsonEncode([
            {
              'txid': 'aa' * 32,
              'type': 1,
              'amount': 2.0,
              'timestamp': 1700000000000,
              'confirmations': 3,
            }
          ]));

      expect((await TxHistoryService.load()).single.amount, 2.0,
          reason: 'an upgrade finds the history exactly where it left it');
    });

    test('a second wallet writes under its own key', () async {
      TxHistoryService.setWallet('w2');
      await TxHistoryService.save([tx('bb', 9.0)]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('soq_w_w2_soqshield_tx_history_mainnet'),
          isNotNull);
      expect(prefs.getString('soqshield_tx_history_mainnet'), isNull);
    });
  });
}
