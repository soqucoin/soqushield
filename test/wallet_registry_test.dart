// The wallet registry: the index multiwallet is built on.
//
// The rule that matters most here is that adopting the wallet which existed
// before the registry MOVES NOTHING. A migration that relocates a mnemonic
// can half-finish, and a half-finished one is a lost wallet. The primary
// wallet keeps the original keys and the registry simply learns to name them.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/services/secure_storage_service.dart';

import 'lite_test_support.dart';

const _address =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _other =
    'sq1pzzzznd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qzzzzzz';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService store;
  setUp(() {
    installSecureStorageMock();
    store = SecureStorageService();
  });

  /// The shape a pre-registry install has on disk.
  void seedLegacyWallet() {
    secureStore['soq_mnemonic_v2'] = 'legal winner thank year wave sausage';
    secureStore['soq_address_v2'] = _address;
    secureStore['soq_network_v2'] = 'mainnet';
    secureStore['soq_key_created_v2'] = '2026-10-13T00:00:00.000';
  }

  group('adopting the wallet that predates the registry', () {
    test('moves no secret: the mnemonic stays exactly where it was', () async {
      seedLegacyWallet();
      final before = secureStore['soq_mnemonic_v2'];

      await store.adoptExistingWallet();

      expect(secureStore['soq_mnemonic_v2'], before,
          reason: 'the whole point of the primary namespace is that the '
              'riskiest part of a migration never happens');
      expect(store.mnemonicKeyFor(WalletRecord.primaryId), 'soq_mnemonic_v2');
    });

    test('records what a wallet list needs, and opens it', () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();

      final wallets = await store.listWallets();
      expect(wallets, hasLength(1));
      expect(wallets.single.id, WalletRecord.primaryId);
      expect(wallets.single.address, _address);
      expect(wallets.single.network, SoqNetwork.mainnet);
      expect(wallets.single.createdAt, DateTime(2026, 10, 13));
      expect(await store.activeWalletId(), WalletRecord.primaryId);
    });

    test('is a no-op on a device with no wallet', () async {
      await store.adoptExistingWallet();
      expect(await store.listWallets(), isEmpty);
      expect(await store.activeWalletId(), isNull);
    });

    test('runs again safely, and does not overwrite a renamed entry',
        () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();
      await store.putWallet((await store.listWallets()).single
          .copyWith(name: 'Rent money'));

      await store.adoptExistingWallet(); // e.g. the next boot

      final wallets = await store.listWallets();
      expect(wallets, hasLength(1));
      expect(wallets.single.name, 'Rent money');
    });
  });

  group('a second wallet gets its own namespace', () {
    test('its keys never collide with the primary wallet', () {
      expect(store.mnemonicKeyFor('w2'), 'soq_w_w2_soq_mnemonic_v2');
      expect(store.mnemonicKeyFor('w2'),
          isNot(store.mnemonicKeyFor(WalletRecord.primaryId)));
      expect(store.addressKeyFor('w2'),
          isNot(store.addressKeyFor(WalletRecord.primaryId)));
    });

    test('the registry keeps both, in the order they were added', () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();
      await store.putWallet(WalletRecord(
        id: 'w2',
        name: 'Savings',
        address: _other,
        network: SoqNetwork.mainnet,
        createdAt: DateTime(2026, 11, 4),
      ));

      final wallets = await store.listWallets();
      expect(wallets.map((w) => w.id), [WalletRecord.primaryId, 'w2']);
      expect(wallets.last.name, 'Savings');
    });

    test('putWallet replaces an entry rather than duplicating it', () async {
      final rec = WalletRecord(
        id: 'w2',
        name: 'Savings',
        address: _other,
        network: SoqNetwork.mainnet,
        createdAt: DateTime(2026, 11, 4),
      );
      await store.putWallet(rec);
      await store.putWallet(rec.copyWith(name: 'Holiday'));

      final wallets = await store.listWallets();
      expect(wallets, hasLength(1));
      expect(wallets.single.name, 'Holiday');
    });
  });

  group('the active pointer cannot dangle', () {
    test('an id the registry does not carry is refused', () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();
      expect(() => store.setActiveWallet('ghost'), throwsArgumentError,
          reason: 'opening a wallet whose secrets are gone reads nothing');
    });

    test('a pointer left behind by a removed wallet reads as none', () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();
      // The registry is emptied underneath the pointer.
      secureStore['soq_wallets_v1'] = '[]';
      expect(await store.activeWalletId(), isNull);
    });
  });

  group('a damaged registry does not take the app down', () {
    test('unparsable JSON reads as an empty list', () async {
      secureStore['soq_wallets_v1'] = 'not json {{{';
      expect(await store.listWallets(), isEmpty);
    });

    test('JSON of the wrong shape reads as an empty list', () async {
      secureStore['soq_wallets_v1'] = jsonEncode({'id': 'w2'});
      expect(await store.listWallets(), isEmpty);
    });

    test('a single unreadable row is dropped, the rest survive', () async {
      secureStore['soq_wallets_v1'] = jsonEncode([
        {'id': 'w2', 'address': _other, 'network': 'mainnet'},
        {'name': 'no id, no address'},
        'not even a map',
      ]);
      final wallets = await store.listWallets();
      expect(wallets.map((w) => w.id), ['w2']);
      expect(wallets.single.name, 'Wallet', reason: 'a default, not a crash');
    });

    test('an adoption rebuilds an entry after the registry is lost', () async {
      seedLegacyWallet();
      await store.adoptExistingWallet();
      secureStore.remove('soq_wallets_v1');

      await store.adoptExistingWallet();
      expect((await store.listWallets()).single.id, WalletRecord.primaryId);
    });
  });

  test('a wipe takes the registry with it', () async {
    seedLegacyWallet();
    await store.adoptExistingWallet();
    await store.wipeWallet();
    expect(await store.listWallets(), isEmpty);
    expect(await store.activeWalletId(), isNull);
  });
}
