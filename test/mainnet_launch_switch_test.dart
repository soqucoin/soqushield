// The one-time move to Mainnet after block 1 (13 October 2026), build 27.
//
// An install that stored Stagenet (the stagenet-era app) opens on Mainnet on
// its first boot after the update, derives the sq1 address of the same seed,
// rewrites the stored network and address, remembers that it moved, and shows
// the notice until the member dismisses it. An install already on Mainnet is
// marked 'kept' and shows nothing. Once marked, the stored network is honoured
// as it is, so a member's later switch back to Stagenet stays.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/wallet_provider.dart';

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
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return c.read(walletProvider);
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

  test('1. an install that stored Stagenet moves to Mainnet once and shows the notice',
      () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    final s = await _boot(container);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress, reason: 'the same seed, the sq1 address');
    expect(s.mainnetSwitchNotice, isTrue);
    expect(secureStore['soq_network_v2'], 'mainnet');
    expect(secureStore['soq_address_v2'], mainnetAddress);
    expect(secureStore['soq_mainnet_switch_v1'], 'moved');
  });

  test('2. an install with no stored network (reads as Stagenet) moves too', () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStore.remove('soq_network_v2');
    final s = await _boot(container);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.mainnetSwitchNotice, isTrue);
    expect(secureStore['soq_mainnet_switch_v1'], 'moved');
  });

  test('3. an install already on Mainnet is marked kept and shows no notice', () async {
    storeWallet(SoqNetwork.mainnet, mainnetAddress);
    final s = await _boot(container);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.mainnetSwitchNotice, isFalse);
    expect(secureStore['soq_mainnet_switch_v1'], 'kept');
  });

  test('4. once decided, the stored network is honoured: a switch back to Stagenet stays',
      () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStore['soq_mainnet_switch_v1'] = 'moved';
    secureStore['soq_mainnet_switch_notice_dismissed_v1'] = 'true';
    final s = await _boot(container);
    expect(s.network, SoqNetwork.stagenet);
    expect(s.address, stagenetAddress);
    expect(s.mainnetSwitchNotice, isFalse, reason: 'dismissed earlier');
    expect(secureStore['soq_network_v2'], 'stagenet');
  });

  test('5. the notice shows again after a restart until it is dismissed, then stays dismissed',
      () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    final first = await _boot(container);
    expect(first.mainnetSwitchNotice, isTrue);

    // A restart before the dismissal: the move is remembered, the notice is due.
    container.dispose();
    container = ProviderContainer();
    final second = await _boot(container);
    expect(second.network, SoqNetwork.mainnet);
    expect(second.mainnetSwitchNotice, isTrue);

    await container.read(walletProvider.notifier).dismissMainnetSwitchNotice();
    expect(container.read(walletProvider).mainnetSwitchNotice, isFalse);
    expect(secureStore['soq_mainnet_switch_notice_dismissed_v1'], 'true');

    container.dispose();
    container = ProviderContainer();
    final third = await _boot(container);
    expect(third.mainnetSwitchNotice, isFalse);
    expect(third.network, SoqNetwork.mainnet);
  });

  test('6. a wallet created on this build and switched to Stagenet by hand stays there after a restart',
      () async {
    await _boot(container); // nothing stored: onboarding
    final n = container.read(walletProvider.notifier);
    await n.createWallet('member');
    expect(container.read(walletProvider).network, SoqNetwork.mainnet);
    expect(secureStore['soq_mainnet_switch_v1'], 'kept',
        reason: 'a wallet created on this build is a decided install');
    expect(container.read(walletProvider).mainnetSwitchNotice, isFalse);

    await n.setNetwork(SoqNetwork.stagenet);
    expect(secureStore['soq_network_v2'], 'stagenet');

    container.dispose();
    container = ProviderContainer();
    final s = await _boot(container);
    expect(s.network, SoqNetwork.stagenet, reason: 'the deliberate choice is honoured');
    expect(s.mainnetSwitchNotice, isFalse);
    expect(secureStore['soq_mainnet_switch_v1'], 'kept');
  });

  test('7. a wallet restored on this build is a decided install too, across a restart', () async {
    await _boot(container);
    final n = container.read(walletProvider.notifier);
    await n.restoreFromMnemonic(mnemonic);
    expect(container.read(walletProvider).network, SoqNetwork.mainnet);
    expect(secureStore['soq_mainnet_switch_v1'], 'kept');
    expect(container.read(walletProvider).mainnetSwitchNotice, isFalse);

    await n.setNetwork(SoqNetwork.stagenet);
    container.dispose();
    container = ProviderContainer();
    final s = await _boot(container);
    expect(s.network, SoqNetwork.stagenet, reason: 'the deliberate choice is honoured');
    expect(s.address, stagenetAddress);
    expect(s.mainnetSwitchNotice, isFalse);
  });

  // A storage write that fails mid-move fails that boot; the next boot must
  // still finish on Mainnet with the notice, and never read the interrupted
  // move as an install that was on Mainnet already ('kept', no notice).
  Future<void> expectCompletedMove() async {
    container.dispose();
    container = ProviderContainer();
    final s = await _boot(container);
    expect(s.error, isNull);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress);
    expect(s.mainnetSwitchNotice, isTrue,
        reason: 'the member was moved and must be told');
    expect(secureStore['soq_network_v2'], 'mainnet');
    expect(secureStore['soq_mainnet_switch_v1'], 'moved');
  }

  test('8. a refused write of the move marker changes nothing; the next boot moves and shows the notice',
      () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStorageWriteFailures.add('soq_mainnet_switch_v1');
    final first = await _boot(container);
    expect(first.error, isNotNull);
    expect(secureStore['soq_network_v2'], 'stagenet',
        reason: 'the network is not rewritten before the marker lands');
    expect(secureStore.containsKey('soq_mainnet_switch_v1'), isFalse);
    await expectCompletedMove();
  });

  test('9. a refused network write leaves the move marked in progress; the next boot completes it',
      () async {
    storeWallet(SoqNetwork.stagenet, stagenetAddress);
    secureStorageWriteFailures.add('soq_network_v2');
    final first = await _boot(container);
    expect(first.error, isNotNull);
    expect(secureStore['soq_network_v2'], 'stagenet');
    expect(secureStore['soq_mainnet_switch_v1'], 'moving');
    await expectCompletedMove();
  });

  test('10. a move whose final marker write failed (network Mainnet, marker moving) is completed with the notice',
      () async {
    storeWallet(SoqNetwork.mainnet, stagenetAddress);
    secureStore['soq_mainnet_switch_v1'] = 'moving';
    final s = await _boot(container);
    expect(s.error, isNull);
    expect(s.network, SoqNetwork.mainnet);
    expect(s.address, mainnetAddress);
    expect(s.mainnetSwitchNotice, isTrue);
    expect(secureStore['soq_mainnet_switch_v1'], 'moved');
  });
}
