// The address book's model, storage and notifier: what a row is, what the
// book accepts and refuses, that a failed read is never written back as an
// empty book, that a row whose address no longer validates is dropped, and
// that a wipe removes the book's key.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/models/address_book_entry.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/address_book_provider.dart';
import 'package:soqushield/services/address_book_service.dart';
import 'package:soqushield/services/secure_storage_service.dart';

import 'lite_test_support.dart';

const _mainnet =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenet =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';
const _key = AddressBookService.storageKey;

List<dynamic> _stored() =>
    json.decode(secureStore[_key] ?? '[]') as List<dynamic>;

Map<String, dynamic> _row(String id, String name, String address) => {
      'id': id,
      'name': name,
      'address': address,
      'createdAt': '2026-10-14T00:00:00Z',
    };

/// Lets the notifier's microtasks and storage calls land.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installSecureStorageMock);

  group('SoqNetwork.ofAddress', () {
    test('reads the network off the prefix, in either case', () {
      expect(SoqNetwork.ofAddress(_mainnet), SoqNetwork.mainnet);
      expect(SoqNetwork.ofAddress(_stagenet), SoqNetwork.stagenet);
      expect(SoqNetwork.ofAddress(_mainnet.toUpperCase()), SoqNetwork.mainnet);
      expect(SoqNetwork.ofAddress(' $_stagenet '), SoqNetwork.stagenet);
      expect(SoqNetwork.ofAddress('bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
          isNull);
      expect(SoqNetwork.ofAddress(''), isNull);
      expect(SoqNetwork.ofAddress('sq2abc'), isNull);
      // A prefix in front of other words: the part before the last
      // separator is what the validator reads as the network.
      expect(SoqNetwork.ofAddress('sq1call support now1qqqqqqq'), isNull);
      expect(SoqNetwork.ofAddress('sq1$_mainnet'), isNull);
    });
  });

  group('AddressBookEntry', () {
    test('round-trips through JSON, and its network is the address\'s own',
        () {
      final entry = AddressBookEntry(
          id: 'ab',
          name: 'Alice',
          address: _stagenet,
          createdAt: DateTime.utc(2026, 10, 14));
      final back = AddressBookEntry.fromJson(json.decode(json.encode(entry.toJson())));
      expect(back, entry);
      expect(back!.network, SoqNetwork.stagenet);
      expect(back.createdAt, DateTime.utc(2026, 10, 14));
    });

    test('cleans the name on the way in and lowercases the address', () {
      final e = AddressBookEntry.fromJson(
          _row('ab', '\u202Eecila  ', _mainnet.toUpperCase()));
      expect(e!.name, 'ecila');
      expect(e.address, _mainnet);
    });

    test('a mixed-case stored address is dropped, not repaired; an uppercase '
        'one is read back lowercase', () {
      final flipped = _mainnet.replaceRange(3, 4, 'P');
      expect(AddressBookEntry.fromJson(_row('ab', 'Alice', flipped)), isNull);
      expect(
          AddressBookEntry.fromJson(_row('ab', 'Alice', _mainnet.toUpperCase()))!
              .address,
          _mainnet);
    });

    test('a blank name gets the fallback', () {
      expect(AddressBookEntry.fromJson(_row('ab', '\u200B', _mainnet))!.name,
          AddressBookEntry.fallbackName);
      expect(AddressBookEntry.fromJson({'id': 'ab', 'address': _mainnet})!.name,
          AddressBookEntry.fallbackName);
    });

    test('never throws, and drops a row it cannot read', () {
      expect(AddressBookEntry.fromJson(null), isNull);
      expect(AddressBookEntry.fromJson('x'), isNull);
      expect(AddressBookEntry.fromJson({'name': 'Alice', 'address': _mainnet}),
          isNull, reason: 'no id');
      expect(AddressBookEntry.fromJson({'id': 'ab', 'name': 'Alice'}), isNull,
          reason: 'no address');
      expect(AddressBookEntry.fromJson(_row('ab', 'Alice', 'bc1qxyz')), isNull,
          reason: 'not shaped like an address of either network');
      final odd = AddressBookEntry.fromJson(
          {'id': 'ab', 'name': 7, 'address': _mainnet, 'createdAt': 5});
      expect(odd!.name, AddressBookEntry.fallbackName);
      expect(odd.createdAt, DateTime(2026));
    });
  });

  group('AddressBookService', () {
    late AddressBookService book;
    setUp(() => book = AddressBookService());

    test('saves an address under a name and lists it, oldest first',
        () async {
      final a = await book.add(name: ' Alice ', address: _mainnet);
      final b = await book.add(name: 'Bob', address: _stagenet);
      expect(a.name, 'Alice');
      expect(a.network, SoqNetwork.mainnet);
      expect(b.network, SoqNetwork.stagenet);
      expect(a.id, isNot(b.id));
      expect(a.id, hasLength(16));
      final list = await book.list();
      expect(list, [a, b]);
      expect(_stored(), hasLength(2));
    });

    test('stores the lowercase form of an uppercase spelling', () async {
      final e = await book.add(name: 'Alice', address: _mainnet.toUpperCase());
      expect(e.address, _mainnet);
    });

    test('refuses a blank name, a bad address, a duplicate and a full book',
        () async {
      await book.add(name: 'Alice', address: _mainnet);
      Future<String> refusal(Future<void> Function() act) async {
        try {
          await act();
        } on AddressBookRefusal catch (e) {
          return e.message;
        }
        fail('not refused');
      }

      expect(await refusal(() => book.add(name: '  ', address: _stagenet)),
          'Give the address a name');
      expect(
          await refusal(() => book.add(name: 'Bob', address: 'hello there')),
          'That is not a Soqucoin address');
      expect(
          await refusal(() => book.add(
              name: 'Bob',
              address: '${_mainnet.substring(0, _mainnet.length - 1)}m')),
          contains('checksum'));
      expect(
          await refusal(() => book.add(
              name: 'Bob', address: _mainnet.replaceRange(3, 6, 'P3J'))),
          contains('Mixed case'));
      expect(await refusal(() => book.add(name: 'Bob', address: _mainnet)),
          'That address is already saved as Alice');
      expect(await refusal(() => book.add(name: 'Bob', address: ' $_mainnet ')),
          'That address is already saved as Alice',
          reason: 'the duplicate check reads the address as stored');
      expect(await book.list(), hasLength(1), reason: 'nothing was written');

      // A full book: rows past the cap, then one more.
      secureStore[_key] = json.encode([
        for (var i = 0; i < AddressBookService.maxEntries; i++)
          _row('id$i', 'Row $i', _mainnet),
      ]);
      expect(await refusal(() => book.add(name: 'Bob', address: _stagenet)),
          'The address book is full');
    });

    test('renames and removes by id; a rename changes nothing else',
        () async {
      final a = await book.add(name: 'Alice', address: _mainnet);
      final renamed = await book.rename(a.id, '  Alice at work ');
      expect(renamed.name, 'Alice at work');
      expect(renamed.address, a.address);
      expect(renamed.id, a.id);
      expect(renamed.createdAt, a.createdAt);
      expect(await book.list(), [renamed]);

      await expectLater(book.rename('nope', 'x'), throwsA(isA<AddressBookRefusal>()));
      await expectLater(book.rename(a.id, '\u200B'), throwsA(isA<AddressBookRefusal>()));

      await book.remove(a.id);
      expect(await book.list(), isEmpty);
      await book.remove(a.id); // already gone: not an error
    });

    test('an unreadable book lists as empty, and a failed read is never '
        'written back as an empty book', () async {
      await book.add(name: 'Alice', address: _mainnet);
      final before = secureStore[_key];

      secureStorageReadFailures.add(_key);
      expect(await book.list(), isEmpty);

      secureStorageReadFailures.add(_key);
      await expectLater(
          book.add(name: 'Bob', address: _stagenet), throwsA(anything));
      expect(secureStore[_key], before, reason: 'the book is untouched');
      expect(await book.list(), hasLength(1));
    });

    test('undecodable content reads as empty and is repaired by the next write',
        () async {
      secureStore[_key] = '{not json';
      expect(await book.list(), isEmpty);
      await book.add(name: 'Alice', address: _mainnet);
      expect(_stored(), hasLength(1));
    });

    test('a row whose address does not validate is dropped on read, and a '
        'row that cannot be read does not take the others with it',
        () async {
      secureStore[_key] = json.encode([
        _row('a', 'Alice', _mainnet),
        _row('b', 'Bad', '${_mainnet.substring(0, _mainnet.length - 1)}m'),
        'junk',
        _row('m', 'Mixed', _mainnet.replaceRange(3, 4, 'P')),
        _row('c', 'Carol', _stagenet),
      ]);
      final list = await book.list();
      expect(list.map((e) => e.name), ['Alice', 'Carol']);
    });

    test('clear takes its turn behind a write in flight', () async {
      await book.add(name: 'Alice', address: _mainnet);
      final hold = Completer<void>();
      secureStorageWriteHolds[_key] = hold;
      final adding = book.add(name: 'Bob', address: _stagenet);
      await Future<void>.delayed(Duration.zero);
      final clearing = book.clear();
      await Future<void>.delayed(Duration.zero);
      expect(secureStore.containsKey(_key), isTrue,
          reason: 'the clear waits for the write');
      hold.complete();
      await adding;
      await clearing;
      expect(secureStore.containsKey(_key), isFalse,
          reason: 'the write landed, then the clear deleted it');
      expect(await book.list(), isEmpty);
    });

    test('the wipe deletes the book\'s key by name', () async {
      expect(SecureStorageService.addressBookKeys,
          containsAll(AddressBookService.storedKeys));
      await book.add(name: 'Alice', address: _mainnet);
      await SecureStorageService().wipeWallet();
      expect(secureStorageCalls, contains('delete $_key'));
      expect(secureStore.containsKey(_key), isFalse);
    });
  });

  group('addressBookProvider', () {
    test('loads the stored book, and every change reaches storage and the '
        'state', () async {
      secureStore[_key] = json.encode([_row('s', 'Stage', _stagenet)]);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(addressBookProvider).loaded, isFalse);
      await _settle();
      var book = container.read(addressBookProvider);
      expect(book.loaded, isTrue);
      expect(book.entries.map((e) => e.name), ['Stage']);
      expect(book.on(SoqNetwork.mainnet), isEmpty);
      expect(book.on(SoqNetwork.stagenet), hasLength(1));

      final notifier = container.read(addressBookProvider.notifier);
      final alice = await notifier.add(name: 'Alice', address: _mainnet);
      book = container.read(addressBookProvider);
      expect(book.on(SoqNetwork.mainnet), [alice]);
      expect(book.byAddress(_mainnet.toUpperCase()), alice);
      expect(book.byAddress(_stagenet)!.name, 'Stage');
      expect(book.byAddress('sq1nothing'), isNull);

      await notifier.rename(alice.id, 'Alice B');
      expect(container.read(addressBookProvider).byAddress(_mainnet)!.name,
          'Alice B');

      await expectLater(notifier.add(name: '', address: _mainnet),
          throwsA(isA<AddressBookRefusal>()));

      await notifier.remove(alice.id);
      expect(container.read(addressBookProvider).entries.map((e) => e.name),
          ['Stage']);
      expect(_stored(), hasLength(1));

      await notifier.resetToDefaults();
      expect(container.read(addressBookProvider).entries, isEmpty);
      expect(container.read(addressBookProvider).loaded, isTrue);
      expect(secureStore.containsKey(_key), isFalse,
          reason: 'the reset deletes the stored book');
    });

    test('a reset during a held write: the write lands, the clear follows, '
        'and the state stays empty', () async {
      secureStore[_key] = json.encode([_row('a', 'Alice', _mainnet)]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(addressBookProvider);
      await _settle();
      final notifier = container.read(addressBookProvider.notifier);

      final hold = Completer<void>();
      secureStorageWriteHolds[_key] = hold;
      final adding = notifier.add(name: 'Bob', address: _stagenet);
      await _settle();
      final resetting = notifier.resetToDefaults();
      await _settle();
      expect(container.read(addressBookProvider).entries, isEmpty,
          reason: 'the state empties at once');
      expect(secureStore.containsKey(_key), isTrue,
          reason: 'the clear waits its turn behind the write');

      hold.complete();
      await adding;
      await resetting;
      await _settle();
      expect(secureStore.containsKey(_key), isFalse,
          reason: 'the clear ran after the write');
      expect(container.read(addressBookProvider).entries, isEmpty,
          reason: 'the add does not read the book back after the reset');
    });

    test('a reload in flight when the reset lands cannot put entries back',
        () async {
      secureStore[_key] = json.encode([_row('a', 'Alice', _mainnet)]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(addressBookProvider);
      await _settle();
      expect(container.read(addressBookProvider).entries, hasLength(1));
      final notifier = container.read(addressBookProvider.notifier);

      final hold = Completer<void>();
      secureStorageReadHolds[_key] = hold;
      final reloading = notifier.reload();
      await _settle();
      await notifier.resetToDefaults();
      expect(container.read(addressBookProvider).entries, isEmpty);

      hold.complete();
      await reloading;
      await _settle();
      expect(container.read(addressBookProvider).entries, isEmpty,
          reason: 'the read that began before the reset is dropped');
      expect(secureStore.containsKey(_key), isFalse);
    });

    test('an older read that lands after a newer one cannot put back a row '
        'the newer read no longer holds', () async {
      final service = _HeldReads();
      final container = ProviderContainer(overrides: [
        addressBookServiceProvider.overrideWithValue(service),
      ]);
      addTearDown(container.dispose);
      container.read(addressBookProvider);
      await _settle();
      service.answer(0, [_entry('a', 'Alice', _mainnet)]);
      await _settle();
      final notifier = container.read(addressBookProvider.notifier);

      // Two reads in flight: the first saw Alice, the second saw her removed.
      final first = notifier.reload();
      await _settle();
      final second = notifier.reload();
      await _settle();
      expect(service.pending, 2);
      service.answer(2, const []);
      await second;
      expect(container.read(addressBookProvider).entries, isEmpty);

      service.answer(1, [_entry('a', 'Alice', _mainnet)]);
      await first;
      await _settle();
      expect(container.read(addressBookProvider).entries, isEmpty,
          reason: 'the superseded read is dropped when it lands');
    });
  });
}

AddressBookEntry _entry(String id, String name, String address) =>
    AddressBookEntry.fromJson(_row(id, name, address))!;

/// A service whose reads wait until the test answers them, in any order.
class _HeldReads extends AddressBookService {
  final List<Completer<List<AddressBookEntry>>> _reads = [];

  int get pending => _reads.where((c) => !c.isCompleted).length;

  void answer(int index, List<AddressBookEntry> entries) =>
      _reads[index].complete(entries);

  @override
  Future<List<AddressBookEntry>> list() {
    final read = Completer<List<AddressBookEntry>>();
    _reads.add(read);
    return read.future;
  }
}
