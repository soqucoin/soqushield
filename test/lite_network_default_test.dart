// Lite mainnet build: the network a wallet is born on, and the hosts it talks
// to, through the real WalletNotifier against an in-memory secure storage.
//
// Every outbound request is recorded and refused, so the tests also pin that
// a mainnet wallet never talks to a stagenet host at boot, create or restore.
// The canonical 24 words are the derivation known-answer vectors the console
// and the node share (test/derivation.kat.json).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/wallet_provider.dart';

import 'lite_test_support.dart';

/// One confirmed 5 SOQ output in the on-disk UTXO format (Utxo.toJson).
String _cachedUtxoJson(String address) => jsonEncode([
      {
        'txid': 'ab' * 32,
        'vout': 0,
        'value': 5.0,
        'valueSat': 500000000,
        'scriptPubKey': '5120${'00' * 32}',
        'address': address,
        'height': 100,
        'confirmations': 10,
        'locked': false,
        'assetType': 0,
        'visibility': 0,
      }
    ]);

/// One received row in the on-disk history format (TxHistoryService.save).
String _historyJson() => jsonEncode([
      {'txid': 'cd' * 32, 'type': 1, 'amount': 2.0, 'timestamp': 1700000000000, 'confirmations': 3}
    ]);


const _stagenetHosts = {
  'staging-rpc.soqu.org',
  'soqushield-api.research-c26.workers.dev',
};
const _mainnetHosts = {
  'mainnet-rpc.soqu.org',
  'mainnet-api.soqu.org',
};

/// Records every host the app opens a request to and refuses the request.
class _RecordingHttpClient implements HttpClient {
  final List<Uri> urls;
  _RecordingHttpClient(this.urls);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    urls.add(url);
    throw const SocketException('no network in tests');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingOverrides extends HttpOverrides {
  final List<Uri> urls = [];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(urls);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final kat = jsonDecode(File('test/derivation.kat.json').readAsStringSync())
      as Map<String, dynamic>;
  final mnemonic = kat['mnemonic'] as String;
  String address(String network) => (kat['vectors'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((v) => v['network'] == network && v['accountIndex'] == 0)['address'] as String;
  final mainnetAddress = address('mainnet');
  final stagenetAddress = address('stagenet');

  late _RecordingOverrides overrides;
  late ProviderContainer container;

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    overrides = _RecordingOverrides();
    HttpOverrides.global = overrides;
    container = ProviderContainer();
  });

  tearDown(() async {
    // Stops the refresh timers and clears the store.
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

  Set<String> hosts() => overrides.urls.map((u) => u.host).toSet();

  test('a new install is born on mainnet', () async {
    final s = await _boot(container);
    expect(s.hasWallet, isFalse);
    expect(s.network, SoqNetwork.mainnet);
  });

  test('restoring the canonical words on a new install gives the mainnet address '
      'and talks only to mainnet hosts', () async {
    await _boot(container);
    await container.read(walletProvider.notifier).restoreFromMnemonic(mnemonic);
    await _settle();
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress);
    expect(secureStore['soq_network_v2'], 'mainnet');
    expect(hosts(), isNotEmpty, reason: 'the restore refreshes the balance');
    expect(hosts().intersection(_stagenetHosts), isEmpty,
        reason: 'a mainnet wallet must not query a stagenet host');
    expect(hosts().difference(_mainnetHosts), isEmpty,
        reason: 'only the two mainnet hosts may be contacted');
  });

  test('an existing stagenet install keeps stagenet and its address', () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    final s = await _boot(container);
    expect(s.network, SoqNetwork.stagenet);
    expect(s.address, stagenetAddress);
    expect(hosts().intersection(_mainnetHosts), isEmpty);
    expect(hosts().difference(_stagenetHosts), isEmpty);
  });

  test('an existing mainnet install boots on mainnet and talks only to mainnet hosts',
      () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    final s = await _boot(container);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress);
    expect(hosts(), isNotEmpty, reason: 'boot refreshes the balance');
    expect(hosts().intersection(_stagenetHosts), isEmpty,
        reason: 'a mainnet wallet must not query a stagenet host at boot');
    expect(hosts().difference(_mainnetHosts), isEmpty);
  });

  test('creating a wallet on a new install stores mainnet and an sq1 address', () async {
    await _boot(container);
    await container.read(walletProvider.notifier).createWallet('Test');
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address.startsWith('sq1'), isTrue);
    expect(s.seedPhrase, isNotNull, reason: 'the backup screen reads the phrase');
    expect(secureStore['soq_network_v2'], 'mainnet');
    expect(secureStore['soq_address_v2'], s.address);
    await _settle();
    expect(hosts(), isNotEmpty, reason: 'a created wallet starts its balance poll');
    expect(hosts().difference(_mainnetHosts), isEmpty);
  });

  test('a stagenet install reads its own UTXO and history partitions', () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStore['soq_utxo_set_stagenet'] = _cachedUtxoJson(stagenetAddress);
    SharedPreferences.setMockInitialValues({'soqshield_tx_history_stagenet': _historyJson()});
    final s = await _boot(container);
    expect(s.balance, 5.0, reason: 'the cached stagenet output is read at boot');
    expect(s.recentTransactions.length, 1);
  });

  test('a mainnet install never reads the stagenet partitions', () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    secureStore['soq_utxo_set_stagenet'] = _cachedUtxoJson(stagenetAddress);
    SharedPreferences.setMockInitialValues({'soqshield_tx_history_stagenet': _historyJson()});
    final s = await _boot(container);
    expect(s.balance, 0);
    expect(s.recentTransactions, isEmpty);
  });

  test('a wipe clears the history of both networks', () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    SharedPreferences.setMockInitialValues({
      'soqshield_tx_history_mainnet': _historyJson(),
      'soqshield_tx_history_stagenet': _historyJson(),
    });
    await _boot(container);
    await container.read(walletProvider.notifier).wipeWallet();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('soqshield_tx_history_')), isEmpty);
    expect(secureStore, isEmpty);
    expect(container.read(walletProvider).hasWallet, isFalse);
    // On iOS the UTXO partitions sit under another keychain accessibility than
    // the wallet's deleteAll reaches, so the wipe must delete each by name.
    for (final n in SoqNetwork.values) {
      expect(secureStorageCalls, contains('delete soq_utxo_set_${n.name}'));
    }
  });

  test('switching an existing install to stagenet re-points every host and carries no rows', () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    SharedPreferences.setMockInitialValues({'soqshield_tx_history_mainnet': _historyJson()});
    final booted = await _boot(container);
    expect(booted.recentTransactions.length, 1);
    overrides.urls.clear();
    await container.read(walletProvider.notifier).setNetwork(SoqNetwork.stagenet);
    await _settle();
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.stagenet);
    expect(s.address, stagenetAddress);
    expect(secureStore['soq_network_v2'], 'stagenet');
    expect(s.recentTransactions, isEmpty, reason: 'the mainnet rows stay in the mainnet partition');
    expect(s.pendingBalance, 0);
    expect(hosts().intersection(_mainnetHosts), isEmpty);
    expect(hosts().difference(_stagenetHosts), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('soqshield_tx_history_stagenet'), isNull,
        reason: 'nothing of the old network is written into the new partition');
  });

  test('a refresh in flight across a switch writes nothing into the new network', () async {
    // The mainnet balance answer is held until after the switch to stagenet
    // has completed against immediate stagenet answers; releasing it must not
    // land 42 SOQ in the stagenet state.
    final hold = Completer<void>();
    String body(Map<String, dynamic> m) => jsonEncode(m);
    final client = MockClient((req) async {
      final p = req.url.path;
      if (req.method != 'GET') return http.Response('rpc refused', 400);
      if (p == '/api/v2/multi-balance/$mainnetAddress') {
        await hold.future;
        return http.Response(body({'soq': {'confirmed': 4200000000, 'unconfirmed': 0, 'confirmed_soq': 42.0, 'unconfirmed_soq': 0.0}}), 200);
      }
      if (p == '/api/v2/multi-balance/$stagenetAddress') {
        return http.Response(body({'soq': {'confirmed': 0, 'unconfirmed': 0, 'confirmed_soq': 0.0, 'unconfirmed_soq': 0.0}}), 200);
      }
      if (p == '/api/v2/tip') return http.Response(body({'height': 777}), 200);
      if (p.startsWith('/api/v2/utxos/')) return http.Response(body({'utxos': []}), 200);
      if (p.startsWith('/api/v2/history/')) return http.Response(body({'transactions': []}), 200);
      return http.Response('not found', 404);
    });
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    // The services create their HTTP clients when the provider is built, so
    // the build happens inside the mock client's zone.
    container.dispose();
    container = await http.runWithClient(() async {
      final c = ProviderContainer();
      c.read(walletProvider);
      return c;
    }, () => client);
    await _boot(container);
    await container.read(walletProvider.notifier).setNetwork(SoqNetwork.stagenet);
    await _settle();
    expect(container.read(walletProvider).blockHeight, 777);
    hold.complete();
    await _settle();
    final s = container.read(walletProvider);
    expect(s.network, SoqNetwork.stagenet);
    expect(s.balance, 0, reason: 'the held mainnet answer must not reach the stagenet state');
    expect(s.blockHeight, 777);
  });
}
