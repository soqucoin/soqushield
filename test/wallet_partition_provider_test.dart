// The wallet partitions seen from the provider: which wallet boot opens the
// coins and the history of, and what a device-wide wipe removes.
//
//   1. boot keeps the coins and the history on the primary wallet, whose seed
//      is the one secure storage reads, whatever the registry pointer says;
//   2. a wipe deletes every registered wallet's coin partitions by name,
//      through the instance that wrote them;
//   3. a wipe removes every wallet's history, on every network.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/tx_history_service.dart';

import 'lite_test_support.dart';

class _RefusingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      throw const SocketException('no network in tests');
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RefusingOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RefusingHttpClient();
}

Future<WalletState> _boot(ProviderContainer c) async {
  c.read(walletProvider);
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (!c.read(walletProvider).isLoading) break;
  }
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return c.read(walletProvider);
}

Map<String, dynamic> _cachedUtxo(String address, double value) => {
      'txid': 'ab' * 32,
      'vout': 0,
      'value': value,
      'valueSat': (value * 100000000).round(),
      'scriptPubKey': '5120${'00' * 32}',
      'address': address,
      'height': 100,
      'confirmations': 10,
      'locked': false,
      'assetType': 0,
      'visibility': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kat = jsonDecode(File('test/derivation.kat.json').readAsStringSync())
      as Map<String, dynamic>;
  final mnemonic = kat['mnemonic'] as String;
  final mainnetAddress = (kat['vectors'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((v) => v['network'] == 'mainnet' && v['accountIndex'] == 0)[
          'address'] as String;

  late ProviderContainer container;

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _RefusingOverrides();
    TxHistoryService.setWallet(WalletRecord.primaryId);
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
    HttpOverrides.global = null;
    TxHistoryService.setWallet(WalletRecord.primaryId);
  });

  /// The primary wallet's secrets, a second wallet in the registry, and the
  /// pointer on [active].
  void storeTwoWallets({required String active}) {
    secureStore['soq_mnemonic_v2'] = mnemonic;
    secureStore['soq_address_v2'] = mainnetAddress;
    secureStore['soq_deriv_path_v2'] = "m/44'/21329'/0'/0/0";
    secureStore['soq_account_index_v2'] = '0';
    secureStore['soq_backup_confirmed_v2'] = 'true';
    secureStore['soq_network_v2'] = 'mainnet';
    secureStore['soq_mainnet_switch_v1'] = 'kept';
    secureStore['soq_wallets_v1'] = jsonEncode([
      WalletRecord(
        id: WalletRecord.primaryId,
        name: 'Main wallet',
        address: mainnetAddress,
        network: SoqNetwork.mainnet,
        createdAt: DateTime(2026),
      ).toJson(),
      WalletRecord(
        id: 'w2',
        name: 'Second',
        address: 'sq1second',
        network: SoqNetwork.mainnet,
        createdAt: DateTime(2026),
      ).toJson(),
    ]);
    secureStore['soq_active_wallet_v1'] = active;
  }

  test('1. boot keeps the partitions on the wallet whose seed it read',
      () async {
    storeTwoWallets(active: 'w2');
    secureStore['soq_w_w2_soq_utxo_set_mainnet'] =
        jsonEncode([_cachedUtxo('sq1second', 5.0)]);

    final s = await _boot(container);

    expect(s.hasWallet, isTrue);
    expect(s.address, mainnetAddress);
    expect(s.balance, 0,
        reason: "the primary seed must not be paired with w2's cached coins");
    expect(TxHistoryService.walletId, WalletRecord.primaryId,
        reason: "nor with w2's payment history");
  });

  test("2. a wipe deletes every registered wallet's coins by name", () async {
    storeTwoWallets(active: WalletRecord.primaryId);
    secureStore['soq_w_w2_soq_utxo_set_mainnet'] =
        jsonEncode([_cachedUtxo('sq1second', 5.0)]);
    await _boot(container);

    await container.read(walletProvider.notifier).wipeWallet();

    for (final n in SoqNetwork.values) {
      expect(secureStorageCalls, contains('delete soq_w_w2_soq_utxo_set_${n.name}'),
          reason: "on iOS the wallet's deleteAll does not reach the coin "
              'cache; each partition is deleted by name');
    }
  });

  test("3. a wipe removes every wallet's history on every network", () async {
    storeTwoWallets(active: WalletRecord.primaryId);
    SharedPreferences.setMockInitialValues({
      'soqshield_tx_history_mainnet': '[]',
      'soq_w_w2_soqshield_tx_history_mainnet': '[]',
      'soq_w_w2_soqshield_tx_history_stagenet': '[]',
      'soq_w_0123abcd_soqshield_tx_history_stagenet': '[]',
    });
    await _boot(container);

    await container.read(walletProvider.notifier).wipeWallet();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.contains('soqshield_tx_history_')),
        isEmpty,
        reason: 'a resold device carries no wallet\'s payment record');
  });
}
