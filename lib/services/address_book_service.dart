/// The address book's storage: a JSON list under one key in the shared
/// secure storage, read whole and written whole.
///
/// ⛔ What goes in is checked here, not at the screen. A name is cleaned and
/// may not be blank; an address is validated against the network its own
/// prefix names, so the book holds mainnet and stagenet addresses side by
/// side and the send screen picks by network; a duplicate address is refused
/// and the existing name given back. A row read back whose address no longer
/// validates is dropped, so a book edited outside the app cannot put a bad
/// address in front of the send screen.
///
/// Every change is one read-modify-write in a queue, as the wallet registry's
/// are: two writers that each read the list and write it back would otherwise
/// both succeed while the second erased the first's change. A writer's read
/// that fails throws rather than reads as empty, so a failed read is never
/// written back as an empty book.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/address_book_entry.dart';
import '../models/wallet_keys.dart';
import 'secure_storage_service.dart' show kDeviceOnlySecureStorage;
import 'tx_builder.dart';

/// The book refused a change, for a reason the owner can read as it is.
class AddressBookRefusal implements Exception {
  final String message;
  const AddressBookRefusal(this.message);
  @override
  String toString() => message;
}

class AddressBookService {
  static const storageKey = 'soq_address_book_v1';

  /// Every key this service stores. A wipe deletes them by name
  /// ([SecureStorageService.addressBookKeys] names the same list, pinned by
  /// a test): on iOS the wallet instance's deleteAll does not reach them.
  static const storedKeys = [storageKey];

  /// More rows than anyone scrolls, and a bound on the one stored value.
  static const maxEntries = 500;

  final FlutterSecureStorage _storage;

  /// The instance the book is kept in, for a test to check its options.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  AddressBookService({FlutterSecureStorage? storage})
      : _storage = storage ?? kDeviceOnlySecureStorage;

  /// Every saved address, oldest first. An unreadable book reads as empty
  /// rather than throwing: the screens still open, and nothing is written.
  Future<List<AddressBookEntry>> list() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return const [];
      return _rows(json.decode(raw));
    } catch (e) {
      debugPrint('AddressBook: unreadable, treating as empty: $e');
      return const [];
    }
  }

  /// The rows of [decoded] that can be read and whose address still
  /// validates on its own network.
  static List<AddressBookEntry> _rows(Object? decoded) {
    if (decoded is! List) return const [];
    final out = <AddressBookEntry>[];
    for (final row in decoded) {
      try {
        final entry = AddressBookEntry.fromJson(row);
        if (entry == null) continue;
        if (TxBuilder.validateAddress(entry.address, entry.network) != null) {
          debugPrint('AddressBook: dropping a row whose address does not validate');
          continue;
        }
        out.add(entry);
      } catch (e) {
        debugPrint('AddressBook: dropping an unreadable row: $e');
      }
    }
    return out;
  }

  /// The book as a WRITER must see it: a storage read that fails throws.
  /// Content that is there but cannot be decoded holds no row anyone can
  /// read, so it reads as empty and the write repairs it.
  Future<List<AddressBookEntry>> _readForWrite() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return [];
    final Object? decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException catch (e) {
      debugPrint('AddressBook: undecodable, rewriting it: $e');
      return [];
    }
    return _rows(decoded).toList();
  }

  // The write queue, shared by every instance (see the library comment).
  static bool _busy = false;
  static final List<Completer<void>> _waiters = [];

  static Future<T> _mutate<T>(Future<T> Function() body) async {
    if (_busy) {
      final turn = Completer<void>();
      _waiters.add(turn);
      await turn.future;
    } else {
      _busy = true;
    }
    try {
      return await body();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _write(List<AddressBookEntry> entries) => _storage.write(
        key: storageKey,
        value: json.encode(entries.map((e) => e.toJson()).toList()),
      );

  static String _cleanedName(String name) {
    final cleaned = AddressBookEntry.cleanName(name);
    if (cleaned == null) throw const AddressBookRefusal('Give the address a name');
    return cleaned;
  }

  /// [raw] as the address the book stores: of one of the networks, valid on
  /// it, lowercase. An all-uppercase spelling is the same address.
  static String _checkedAddress(String raw) {
    final text = raw.trim();
    final network = SoqNetwork.ofAddress(text);
    if (network == null) {
      throw const AddressBookRefusal('That is not a Soqucoin address');
    }
    final candidate = text == text.toUpperCase() ? text.toLowerCase() : text;
    final refusal = TxBuilder.validateAddress(candidate, network);
    if (refusal != null) throw AddressBookRefusal(refusal);
    return candidate;
  }

  /// Save [address] under [name]. Throws [AddressBookRefusal] with the
  /// reason when it cannot.
  Future<AddressBookEntry> add({
    required String name,
    required String address,
  }) async {
    final cleaned = _cleanedName(name);
    final checked = _checkedAddress(address);
    return _mutate(() async {
      final entries = await _readForWrite();
      for (final e in entries) {
        if (e.address == checked) {
          throw AddressBookRefusal('That address is already saved as ${e.name}');
        }
      }
      if (entries.length >= maxEntries) {
        throw const AddressBookRefusal('The address book is full');
      }
      final entry = AddressBookEntry(
        id: _freshId(entries.map((e) => e.id).toSet()),
        name: cleaned,
        address: checked,
        createdAt: DateTime.now(),
      );
      await _write([...entries, entry]);
      return entry;
    });
  }

  /// Give [id] a new name. ⛔ Only the name changes: the address and the
  /// date are carried over, so a rename can never repoint a name at
  /// another address.
  Future<AddressBookEntry> rename(String id, String name) async {
    final cleaned = _cleanedName(name);
    return _mutate(() async {
      final entries = await _readForWrite();
      final i = entries.indexWhere((e) => e.id == id);
      if (i < 0) throw const AddressBookRefusal('That address is no longer saved');
      final renamed = entries[i].copyWith(name: cleaned);
      entries[i] = renamed;
      await _write(entries);
      return renamed;
    });
  }

  /// Remove [id]. A row already gone is not an error.
  Future<void> remove(String id) => _mutate(() async {
        final entries = await _readForWrite();
        final kept = entries.where((e) => e.id != id).toList();
        if (kept.length == entries.length) return;
        await _write(kept);
      });

  /// Delete the book, for a wipe. It takes its turn in the write queue, so
  /// a change that read the book before the wipe lands first and is then
  /// deleted with the rest, never written back after it.
  Future<void> clear() => _mutate(() => _storage.delete(key: storageKey));

  /// An id no row carries: hex from a secure generator, as the wallet ids
  /// are, so it is never a counter and never a slice of the address.
  static String _freshId(Set<String> taken) {
    final rng = Random.secure();
    const hex = '0123456789abcdef';
    for (var attempt = 0; attempt < 64; attempt++) {
      final id = List.generate(16, (_) => hex[rng.nextInt(16)]).join();
      if (!taken.contains(id)) return id;
    }
    throw StateError('could not find an unused address id');
  }
}
