// The six wallet-provider findings of the lite build's automated review, one
// case each, red before its fix:
//   1. a cold start sums only SOQ outputs into the balance (a cached USDSOQ
//      output from a 2.1 upgrade is not SOQ);
//   2. a wipe retires the refresh in flight, so its late reply writes nothing;
//   3. a wipe deletes, by name, the keys earlier builds wrote through a default
//      storage instance (social sign-in, the pending swap);
//   4. the UTXO write loop stops at a switch, so an old network's output never
//      lands in the new partition;
//   5. overlapping switch requests resolve to the last selection;
//   6. a history save lands under the partition selected when it was called.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/services/tx_history_service.dart';

import 'lite_test_support.dart';

const _mainnetHosts = {'mainnet-rpc.soqu.org', 'mainnet-api.soqu.org'};

/// One confirmed output in the on-disk UTXO format (Utxo.toJson). A USDSOQ
/// output carries the v7 witness program, which the loader treats as the
/// definitive asset tag.
Map<String, dynamic> _cachedUtxo(String address,
        {required double value, bool usdsoq = false, String txid = 'ab'}) =>
    {
      'txid': txid * 32,
      'vout': 0,
      'value': value,
      'valueSat': (value * 100000000).round(),
      'scriptPubKey': '${usdsoq ? '5720' : '5120'}${'00' * 32}',
      'address': address,
      'height': 100,
      'confirmations': 10,
      'locked': false,
      'assetType': usdsoq ? 1 : 0,
      'visibility': 0,
    };

/// One output in the REST bridge's shape (BalanceService.getUtxos).
Map<String, dynamic> _remoteUtxo(String txid, int vout, double soq) => {
      'txid': txid * 32,
      'vout': vout,
      'value_soq': soq,
      'value': (soq * 100000000).round(),
      'height': 100,
    };

/// Refuses every request the app opens outside a mock client.
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

Future<void> _settle([int turns = 40]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<WalletState> _boot(ProviderContainer c) async {
  c.read(walletProvider);
  for (var i = 0; i < 400; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (!c.read(walletProvider).isLoading) break;
  }
  await _settle();
  return c.read(walletProvider);
}

/// Waits until the mocked storage has seen [call], or fails.
Future<void> _untilCall(String call) async {
  for (var i = 0; i < 400; i++) {
    if (secureStorageCalls.contains(call)) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('the storage never saw "$call"');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kat = jsonDecode(File('test/derivation.kat.json').readAsStringSync())
      as Map<String, dynamic>;
  final mnemonic = kat['mnemonic'] as String;
  String address(String network) => (kat['vectors'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((v) =>
          v['network'] == network && v['accountIndex'] == 0)['address'] as String;
  final mainnetAddress = address('mainnet');
  final stagenetAddress = address('stagenet');

  late ProviderContainer container;

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    HttpOverrides.global = _RefusingOverrides();
    container = ProviderContainer();
  });

  tearDown(() async {
    for (final hold in secureStorageWriteHolds.values) {
      if (!hold.isCompleted) hold.complete();
    }
    await container.read(walletProvider.notifier).wipeWallet();
    container.dispose();
    HttpOverrides.global = null;
  });

  void storeWallet(SoqNetwork network, String addr) {
    secureStore['soq_mnemonic_v2'] = mnemonic;
    secureStore['soq_address_v2'] = addr;
    secureStore['soq_deriv_path_v2'] = "m/44'/21329'/0'/0/0";
    secureStore['soq_account_index_v2'] = '0';
    secureStore['soq_backup_confirmed_v2'] = 'true';
    secureStore['soq_network_v2'] = network.name;
  }

  /// The REST bridge for both networks: 42 SOQ confirmed on mainnet, 0 on
  /// stagenet, tip 777, [mainnetUtxos] for the mainnet address, nothing else.
  /// The mainnet balance reply waits on [holdMainnetBalance] when given.
  MockClient client({
    Completer<void>? holdMainnetBalance,
    List<Map<String, dynamic>> mainnetUtxos = const [],
    List<Uri>? requests,
  }) {
    http.Response ok(Map<String, dynamic> m) => http.Response(jsonEncode(m), 200);
    Map<String, dynamic> soq(double v) => {
          'soq': {
            'confirmed': (v * 100000000).round(),
            'unconfirmed': 0,
            'confirmed_soq': v,
            'unconfirmed_soq': 0.0,
          }
        };
    return MockClient((req) async {
      requests?.add(req.url);
      final p = req.url.path;
      if (req.method != 'GET') return http.Response('rpc refused', 400);
      if (p == '/api/v2/multi-balance/$mainnetAddress') {
        if (holdMainnetBalance != null) await holdMainnetBalance.future;
        return ok(soq(42.0));
      }
      if (p == '/api/v2/multi-balance/$stagenetAddress') return ok(soq(0.0));
      if (p == '/api/v2/tip') return ok({'height': 777});
      if (p == '/api/v2/utxos/$mainnetAddress') return ok({'utxos': mainnetUtxos});
      if (p.startsWith('/api/v2/utxos/')) return ok({'utxos': []});
      if (p.startsWith('/api/v2/history/')) return ok({'transactions': []});
      return http.Response('not found', 404);
    });
  }

  /// The services create their HTTP clients when the provider is built, so
  /// the build happens inside the mock client's zone.
  Future<void> bootWith(MockClient c) async {
    container.dispose();
    container = await http.runWithClient(() async {
      final pc = ProviderContainer();
      pc.read(walletProvider);
      return pc;
    }, () => c);
    await _boot(container);
  }

  test('1. a cold start counts only the SOQ outputs of the cached set', () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStore['soq_utxo_set_stagenet'] = jsonEncode([
      _cachedUtxo(stagenetAddress, value: 5.0),
      _cachedUtxo(stagenetAddress, value: 7.0, usdsoq: true, txid: 'cd'),
    ]);
    final s = await _boot(container);
    expect(s.balance, 5.0,
        reason: 'a cached USDSOQ output from the 2.1 build is not SOQ');
  });

  test('2. a wipe retires the refresh in flight; its late reply writes nothing',
      () async {
    final hold = Completer<void>();
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    await bootWith(client(holdMainnetBalance: hold));
    await container.read(walletProvider.notifier).wipeWallet();
    expect(container.read(walletProvider).hasWallet, isFalse);
    hold.complete();
    await _settle();
    final s = container.read(walletProvider);
    expect(s.balance, 0, reason: 'the held balance must not land after the wipe');
    expect(s.blockHeight, 0, reason: 'nor the chain tip');
    expect(s.recentTransactions, isEmpty);
    expect(secureStore, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('soqshield_tx_history_')),
        isEmpty);
  });

  test('3. a wipe deletes the default-instance keys of earlier builds by name',
      () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    await _boot(container);
    await container.read(walletProvider.notifier).wipeWallet();
    for (final key in const [
      'soq_social_provider',
      'soq_social_user_id',
      'soq_social_email',
      'soq_social_display_name',
      'soq_pending_swap_v1',
    ]) {
      expect(secureStorageCalls, contains('delete $key'),
          reason: 'on iOS the wallet\'s deleteAll does not reach an item '
              'written with the default accessibility; it is deleted by name');
    }
  });

  test('4. the UTXO write loop stops at a switch; no old output reaches the '
      'new partition', () async {
    final hold = Completer<void>();
    secureStorageWriteHolds['soq_utxo_set_mainnet'] = hold;
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    await bootWith(client(mainnetUtxos: [
      _remoteUtxo('aa', 0, 1.0),
      _remoteUtxo('bb', 1, 2.0),
    ]));
    // The first output's write is in flight when the switch lands.
    await _untilCall('write soq_utxo_set_mainnet');
    await container.read(walletProvider.notifier).setNetwork(SoqNetwork.stagenet);
    await _settle();
    hold.complete();
    await _settle();
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.stagenet);
    expect(secureStore['soq_utxo_set_stagenet'], isNull,
        reason: 'the second mainnet output must not be written into the '
            'stagenet partition');
    final mainnetSet = jsonDecode(secureStore['soq_utxo_set_mainnet']!) as List;
    expect(mainnetSet.length, 1, reason: 'the held write lands where it began');
    expect(s.balance, 0);
  });

  test('5. overlapping switch requests resolve to the last selection', () async {
    final requests = <Uri>[];
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    await bootWith(client(requests: requests));
    final n = container.read(walletProvider.notifier);
    final toStagenet = n.setNetwork(SoqNetwork.stagenet);
    final backToMainnet = n.setNetwork(SoqNetwork.mainnet);
    await Future.wait([toStagenet, backToMainnet]);
    await _settle();
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.mainnet, reason: 'the last selection wins');
    expect(s.address, mainnetAddress);
    expect(secureStore['soq_network_v2'], 'mainnet');
    requests.clear();
    await n.refreshBalance();
    expect(requests, isNotEmpty);
    expect(requests.map((u) => u.host).toSet().difference(_mainnetHosts), isEmpty,
        reason: 'every service follows the selection that won');
  });

  test('6. a history save lands under the partition selected when it was called',
      () async {
    TxHistoryService.setNetwork(SoqNetwork.mainnet);
    final row = WalletTransaction(
      txid: 'cd' * 32,
      type: TxType.received,
      amount: 2.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      confirmations: 3,
    );
    final save = TxHistoryService.save([row]);
    // The switch lands while the save awaits its preferences handle.
    TxHistoryService.setNetwork(SoqNetwork.stagenet);
    await save;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('soqshield_tx_history_mainnet'), isNotNull,
        reason: 'the row belongs to the network it was fetched on');
    expect(prefs.getString('soqshield_tx_history_stagenet'), isNull);
  });

  test('7. a switch that fails leaves nothing half-applied: every service '
      'stays on the state\'s network and a later request recovers', () async {
    final requests = <Uri>[];
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    await bootWith(client(requests: requests));
    final n = container.read(walletProvider.notifier);
    // storeWallet's first write, mid-switch, is refused once.
    secureStorageWriteFailures.add('soq_mnemonic_v2');
    await expectLater(
        n.setNetwork(SoqNetwork.stagenet), throwsA(isA<PlatformException>()));
    await _settle();
    var s = container.read(walletProvider);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress);
    requests.clear();
    await n.refreshBalance();
    expect(requests, isNotEmpty);
    expect(requests.map((u) => u.host).toSet().difference(_mainnetHosts), isEmpty,
        reason: 'the services returned to mainnet with the state');
    expect(s.blockHeight == 0 || container.read(walletProvider).blockHeight == 777,
        isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('soqshield_tx_history_stagenet'), isNull,
        reason: 'nothing of mainnet reached the stagenet partition');
    await n.setNetwork(SoqNetwork.stagenet);
    await _settle();
    s = container.read(walletProvider);
    expect(s.network, SoqNetwork.stagenet, reason: 'the next request recovers');
    expect(s.address, stagenetAddress);
  });

  test('8. the node fallback\'s verification in flight writes nothing after a '
      'wipe', () async {
    final hold = Completer<void>();
    final methods = <String>[];
    final c = MockClient((req) async {
      if (req.method == 'GET') return http.Response('down', 503);
      final method = (jsonDecode(req.body) as Map)['method'] as String;
      methods.add(method);
      Object? result;
      switch (method) {
        case 'getblockcount':
          result = 777;
        case 'gettxout':
          // A spent output: the verification's prune is the save that must
          // not land after the wipe (a live answer updates nothing once the
          // wipe has emptied the set, so it would never reach the save).
          await hold.future;
          result = null;
        default:
          return http.Response(
              jsonEncode({'result': null, 'error': {'code': -32601, 'message': 'no'}, 'id': 1}),
              200);
      }
      return http.Response(jsonEncode({'result': result, 'error': null, 'id': 1}), 200);
    });
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    secureStore['soq_utxo_set_mainnet'] =
        jsonEncode([_cachedUtxo(mainnetAddress, value: 5.0)]);
    await bootWith(c);
    for (var i = 0; i < 400 && !methods.contains('gettxout'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(methods, contains('gettxout'), reason: 'the verification is in flight');
    await container.read(walletProvider.notifier).wipeWallet();
    final writes = secureStorageCalls.where((k) => k == 'write soq_utxo_set_mainnet').length;
    hold.complete();
    await _settle();
    expect(secureStorageCalls.where((k) => k == 'write soq_utxo_set_mainnet').length,
        writes,
        reason: 'the verification saves nothing after the wipe');
    expect(secureStore, isEmpty);
  });
}
