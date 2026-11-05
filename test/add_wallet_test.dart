// Adding a wallet alongside the ones already here.
//
// ⛔ The property this file exists for: adding a wallet CANNOT reach the
// seed of a wallet already on the device. Before the registry every wallet
// wrote `soq_mnemonic_v2`, so a second one would have written straight over
// the first — the owner's coins still on chain, the words to reach them
// gone, and nothing on screen to say it had happened.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/services/secure_storage_service.dart';

import 'lite_test_support.dart';

const _addrA =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _addrB =
    'sq1pzzzznd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qzzzzzz';
const _mnemonicA = 'legal winner thank year wave sausage';
const _mnemonicB = 'abandon abandon abandon abandon abandon art';

WalletKeys _keys(String address) => WalletKeys(
      publicKey: Uint8List.fromList(const [1, 2, 3]),
      address: address,
      derivationPath: "m/44'/21329'/0'/0/0",
      accountIndex: 0,
      createdAt: DateTime(2026, 11, 5),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService store;
  setUp(() {
    installSecureStorageMock();
    store = SecureStorageService();
  });

  /// The shape a device with one pre-registry wallet has.
  void seedFirstWallet() {
    secureStore['soq_mnemonic_v2'] = _mnemonicA;
    secureStore['soq_address_v2'] = _addrA;
    secureStore['soq_network_v2'] = 'mainnet';
    secureStore['soq_key_created_v2'] = '2026-10-13T00:00:00.000';
  }

  group('a second wallet never reaches the first one\'s seed', () {
    test('the first wallet\'s mnemonic is byte-for-byte untouched', () async {
      seedFirstWallet();

      await store.addWallet(
        name: 'Second',
        mnemonic: _mnemonicB,
        keys: _keys(_addrB),
        network: SoqNetwork.mainnet,
      );

      expect(secureStore['soq_mnemonic_v2'], _mnemonicA,
          reason: 'the words that reach the first wallet\'s coins');
      expect(secureStore['soq_address_v2'], _addrA);
    });

    test('the second wallet is written under its own namespace', () async {
      seedFirstWallet();
      final record = await store.addWallet(
        name: 'Second',
        mnemonic: _mnemonicB,
        keys: _keys(_addrB),
        network: SoqNetwork.mainnet,
      );

      expect(record.id, isNot(WalletRecord.primaryId));
      expect(secureStore['soq_w_${record.id}_soq_mnemonic_v2'], _mnemonicB);
      expect(secureStore['soq_w_${record.id}_soq_address_v2'], _addrB);
    });

    test('each wallet reads back its own secrets', () async {
      seedFirstWallet();
      final record = await store.addWallet(
        name: 'Second',
        mnemonic: _mnemonicB,
        keys: _keys(_addrB),
        network: SoqNetwork.mainnet,
      );

      store.setWallet(WalletRecord.primaryId);
      expect(await store.readMnemonic(), _mnemonicA);
      expect(await store.readAddress(), _addrA);

      store.setWallet(record.id);
      expect(await store.readMnemonic(), _mnemonicB);
      expect(await store.readAddress(), _addrB);
    });

    test('a third wallet collides with neither', () async {
      seedFirstWallet();
      final b = await store.addWallet(
          name: 'B',
          mnemonic: _mnemonicB,
          keys: _keys(_addrB),
          network: SoqNetwork.mainnet);
      final c = await store.addWallet(
          name: 'C',
          mnemonic: 'zoo zoo zoo zoo zoo wrong',
          keys: _keys('sq1pcccc'),
          network: SoqNetwork.mainnet);

      expect({WalletRecord.primaryId, b.id, c.id}, hasLength(3));
      expect(secureStore['soq_mnemonic_v2'], _mnemonicA);
      expect(secureStore['soq_w_${b.id}_soq_mnemonic_v2'], _mnemonicB);
      expect(secureStore['soq_w_${c.id}_soq_mnemonic_v2'], 'zoo zoo zoo zoo zoo wrong');
    });
  });

  group('the registry keeps up', () {
    test('the pre-registry wallet is adopted before the new one joins',
        () async {
      seedFirstWallet();
      expect(await store.listWallets(), isEmpty, reason: 'no registry yet');

      await store.addWallet(
          name: 'Second',
          mnemonic: _mnemonicB,
          keys: _keys(_addrB),
          network: SoqNetwork.mainnet);

      final wallets = await store.listWallets();
      expect(wallets, hasLength(2));
      expect(wallets.first.id, WalletRecord.primaryId,
          reason: 'the wallet that was here first is in the list, not lost');
      expect(wallets.first.address, _addrA);
    });

    test('adding one does NOT open it', () async {
      seedFirstWallet();
      await store.addWallet(
          name: 'Second',
          mnemonic: _mnemonicB,
          keys: _keys(_addrB),
          network: SoqNetwork.mainnet);

      expect(await store.activeWalletId(), WalletRecord.primaryId,
          reason: 'opening a wallet is a separate act, behind the credential');
    });

    test('the first wallet on a blank device needs no adoption', () async {
      final record = await store.addWallet(
          name: 'Only',
          mnemonic: _mnemonicB,
          keys: _keys(_addrB),
          network: SoqNetwork.mainnet);

      final wallets = await store.listWallets();
      expect(wallets.map((w) => w.id), [record.id]);
    });
  });

  group('refusals', () {
    test('an empty phrase is refused before anything is written', () async {
      seedFirstWallet();
      await expectLater(
        store.addWallet(
            name: 'Second',
            mnemonic: '   ',
            keys: _keys(_addrB),
            network: SoqNetwork.mainnet),
        throwsArgumentError,
      );
      expect(await store.listWallets(), isEmpty,
          reason: 'nothing was adopted or written on the way to the refusal');
    });

    test('knownAddresses names every wallet here, for refusing a duplicate',
        () async {
      seedFirstWallet();
      await store.addWallet(
          name: 'Second',
          mnemonic: _mnemonicB,
          keys: _keys(_addrB),
          network: SoqNetwork.mainnet);

      expect(await store.knownAddresses(), {_addrA, _addrB});
    });
  });

  test('a device wipe takes every wallet with it', () async {
    seedFirstWallet();
    final b = await store.addWallet(
        name: 'Second',
        mnemonic: _mnemonicB,
        keys: _keys(_addrB),
        network: SoqNetwork.mainnet);

    await store.wipeWallet();

    expect(secureStore['soq_mnemonic_v2'], isNull);
    expect(secureStore['soq_w_${b.id}_soq_mnemonic_v2'], isNull,
        reason: 'a wipe that left a namespaced seed behind would hand the '
            'next owner of the device a funded wallet');
    expect(await store.listWallets(), isEmpty);
  });

  test('the registry is not scoped: every wallet sees the same list',
      () async {
    seedFirstWallet();
    final b = await store.addWallet(
        name: 'Second',
        mnemonic: _mnemonicB,
        keys: _keys(_addrB),
        network: SoqNetwork.mainnet);

    store.setWallet(b.id);
    expect((await store.listWallets()).map((w) => w.id),
        [WalletRecord.primaryId, b.id],
        reason: 'a scoped registry would give each wallet its own private '
            'list of wallets');
    expect(jsonDecode(secureStore['soq_wallets_v1']!), hasLength(2));
  });
}
