// Renaming a wallet.
//
// The name is the only part of a wallet the owner writes, and the only part
// they pick a wallet by. It is the label beside a balance and in a send
// confirmation, so what it renders as decides which wallet's coins move.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/models/wallet_record.dart';
import 'package:soqushield/services/secure_storage_service.dart';

import 'lite_test_support.dart';

const _addrA =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService store;
  setUp(() {
    installSecureStorageMock();
    store = SecureStorageService();
    secureStore['soq_mnemonic_v2'] = 'legal winner thank year wave sausage';
    secureStore['soq_address_v2'] = _addrA;
    secureStore['soq_network_v2'] = 'mainnet';
    secureStore['soq_key_created_v2'] = '2026-10-13T00:00:00.000';
  });

  Future<void> adopt() => store.adoptExistingWallet();

  group('a rename changes the name and nothing else', () {
    test('the new name is stored', () async {
      await adopt();
      final r = await store.renameWallet(WalletRecord.primaryId, 'Spending');
      expect(r.name, 'Spending');
      expect((await store.listWallets()).single.name, 'Spending');
    });

    test('the address, network and date are carried over untouched', () async {
      await adopt();
      final before = (await store.listWallets()).single;
      await store.renameWallet(WalletRecord.primaryId, 'Spending');
      final after = (await store.listWallets()).single;

      expect(after.address, before.address,
          reason: 'a rename must never be what repoints a wallet');
      expect(after.network, before.network);
      expect(after.createdAt, before.createdAt);
      expect(after.id, before.id);
    });

    test('no key is touched', () async {
      await adopt();
      await store.renameWallet(WalletRecord.primaryId, 'Spending');
      expect(secureStore['soq_mnemonic_v2'],
          'legal winner thank year wave sausage');
    });

    test('the wallet that is open stays open', () async {
      await adopt();
      await store.renameWallet(WalletRecord.primaryId, 'Spending');
      expect(await store.activeWalletId(), WalletRecord.primaryId);
    });

    test('renaming one wallet leaves the others alone', () async {
      await adopt();
      final b = await store.addWallet(
        name: 'Second',
        mnemonic: 'abandon abandon abandon abandon abandon art',
        keys: WalletKeys(
          publicKey: Uint8List.fromList(const [1]),
          address: 'sq1pzzzz',
          derivationPath: "m/44'/21329'/0'/0/0",
          accountIndex: 0,
          createdAt: DateTime(2026, 11, 5),
        ),
        network: SoqNetwork.mainnet,
      );

      await store.renameWallet(b.id, 'Savings');
      final wallets = await store.listWallets();
      expect(wallets.firstWhere((w) => w.isPrimary).name, 'Main wallet');
      expect(wallets.firstWhere((w) => w.id == b.id).name, 'Savings');
    });
  });

  group('what a name may be', () {
    test('surrounding and repeated whitespace is tidied', () async {
      await adopt();
      final r =
          await store.renameWallet(WalletRecord.primaryId, '  day   to  day  ');
      expect(r.name, 'day to day');
    });

    test('a name that is only whitespace is refused', () async {
      await adopt();
      await expectLater(
          store.renameWallet(WalletRecord.primaryId, '   \t  '),
          throwsArgumentError);
      expect((await store.listWallets()).single.name, 'Main wallet',
          reason: 'the old name stands');
    });

    test('a bidirectional override is removed', () async {
      await adopt();
      // Built from its code point, never written as a literal: the character
      // reorders the source itself, so a reviewer cannot read a line that
      // contains one and see what it really says.
      final rlo = String.fromCharCode(0x202E);
      // U+202E reorders what follows it, so a crafted name can draw as a
      // different one in the row the owner picks a wallet from.
      final r = await store.renameWallet(
          WalletRecord.primaryId, 'sgnivas${rlo}dnepsac');
      expect(r.name, isNot(contains(rlo)));
      expect(r.name, 'sgnivasdnepsac');
    });

    test('control characters are removed', () async {
      await adopt();
      final r = await store.renameWallet(
          WalletRecord.primaryId, 'day\u0000to\u001Fday');
      expect(r.name, 'daytoday');
    });

    test('a newline cannot push a row open', () async {
      await adopt();
      final r =
          await store.renameWallet(WalletRecord.primaryId, 'day\nto\nday');
      expect(r.name, 'day to day');
    });

    test('a very long name is cut to the limit', () async {
      await adopt();
      final r = await store.renameWallet(WalletRecord.primaryId, 'x' * 200);
      expect(r.name.length, WalletRecord.maxNameLength);
    });

    test('a cut never splits a surrogate pair', () async {
      await adopt();
      // Each of these is one code point made of two code units.
      final r = await store.renameWallet(
          WalletRecord.primaryId, '\u{1F310}' * 60);
      expect(r.name.runes.length, WalletRecord.maxNameLength);
      expect(r.name.contains('�'), isFalse,
          reason: 'half a surrogate pair renders as a replacement box');
    });
  });

  group('names that draw nothing', () {
    final zwsp = String.fromCharCode(0x200B);
    final wj = String.fromCharCode(0x2060);

    test('a name of zero-width spaces is refused', () async {
      await adopt();
      await expectLater(
          store.renameWallet(WalletRecord.primaryId, zwsp * 5),
          throwsArgumentError);
      await expectLater(
          store.renameWallet(WalletRecord.primaryId, '$wj $zwsp$wj'),
          throwsArgumentError);
      expect((await store.listWallets()).single.name, 'Main wallet');
    });

    test('a cut cannot leave only invisible characters', () async {
      await adopt();
      final r = await store.renameWallet(
          WalletRecord.primaryId, '${zwsp * 40}Savings');
      expect(r.name, 'Savings',
          reason: 'the padding goes, and the word the owner typed stays');
    });

    test('a joiner inside an emoji sequence is kept', () async {
      // Woman, ZWJ, laptop: one emoji, which splits in two without its ZWJ.
      const family = '\u{1F469}‍\u{1F4BB}';
      expect(WalletRecord.cleanName('Work $family'), 'Work $family');
    });

    test('a registry row whose name draws nothing reads as Wallet', () {
      final row = WalletRecord.fromJson({
        'id': 'w2',
        'address': _addrA,
        'name': zwsp * 3,
      });
      expect(row!.name, 'Wallet');
    });
  });

  group('the registry under concurrent and failing renames', () {
    Future<String> addSecond() async {
      await adopt();
      final b = await store.addWallet(
          name: 'Second',
          mnemonic: 'abandon abandon abandon abandon abandon art',
          keys: WalletKeys(
            publicKey: Uint8List.fromList(const [1, 2, 3]),
            address: 'sq1pbbbb',
            derivationPath: "m/44'/21329'/0'/0/0",
            accountIndex: 0,
            createdAt: DateTime(2026, 11, 5),
          ),
          network: SoqNetwork.mainnet);
      return b.id;
    }

    test('two renames started together both stand', () async {
      final b = await addSecond();

      final first = store.renameWallet(WalletRecord.primaryId, 'Spending');
      final second = SecureStorageService().renameWallet(b, 'Savings');
      await Future.wait([first, second]);

      final names = {for (final w in await store.listWallets()) w.id: w.name};
      expect(names[WalletRecord.primaryId], 'Spending');
      expect(names[b], 'Savings',
          reason: "neither rename may write the other's old name back");
    });

    test('a registry read that fails leaves every wallet in it', () async {
      final b = await addSecond();
      final before = secureStore['soq_wallets_v1'];

      secureStorageReadFailures.add('soq_wallets_v1');
      await expectLater(
          store.renameWallet(WalletRecord.primaryId, 'Spending'),
          throwsA(anything));

      expect(secureStore['soq_wallets_v1'], before);
      expect((await store.listWallets()).map((w) => w.id),
          [WalletRecord.primaryId, b]);
    });

    test('a failure on any later registry read loses no wallet either',
        () async {
      final b = await addSecond();

      // The lookup's read succeeds; any read after it, within the rename,
      // fails. Reading that failure as an empty registry would write the
      // renamed row alone over the list.
      secureStorageReadFailuresAfter['soq_wallets_v1'] = 1;
      try {
        await store.renameWallet(WalletRecord.primaryId, 'Spending');
      } catch (_) {}
      secureStorageReadFailuresAfter.clear();

      expect((await store.listWallets()).map((w) => w.id),
          [WalletRecord.primaryId, b],
          reason: 'the rename may fail, but never by hiding a wallet');
    });
  });

  group('refusals', () {
    test('a wallet that is not here is refused, not silently ignored',
        () async {
      await adopt();
      await expectLater(
          store.renameWallet('no-such-wallet', 'Spending'),
          throwsArgumentError);
    });

    test('an empty registry refuses rather than inventing a row', () async {
      await expectLater(
          store.renameWallet(WalletRecord.primaryId, 'Spending'),
          throwsArgumentError);
      expect(await store.listWallets(), isEmpty);
    });
  });

  test('a name read back from a damaged registry is cleaned too', () async {
    final rlo = String.fromCharCode(0x202E);
    secureStore['soq_wallets_v1'] =
        '[{"id":"primary","address":"$_addrA","network":"mainnet",'
        '"name":"bad${rlo}name","createdAt":"2026-10-13T00:00:00.000"}]';
    final row = (await store.listWallets()).single;
    expect(row.name, isNot(contains(rlo)),
        reason: 'a registry edited outside the app must not put an '
            'unrenderable name on screen');
  });
}
