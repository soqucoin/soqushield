/// The address book as the screens read it: every saved address, and whether
/// the stored list has been read yet.
///
/// The notifier changes the book through [AddressBookService] and reads the
/// stored list back after every change, so the state is always what storage
/// holds and never a guess at it. A refusal from the service passes through
/// as an [AddressBookRefusal], for the screen to show as it is.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/address_book_entry.dart';
import '../models/wallet_keys.dart';
import '../services/address_book_service.dart';

export '../services/address_book_service.dart' show AddressBookRefusal;

@immutable
class AddressBook {
  /// Every saved address, on either network, oldest first.
  final List<AddressBookEntry> entries;

  /// False until the stored list has been read.
  final bool loaded;

  const AddressBook({this.entries = const [], this.loaded = false});

  /// The entries on [network], which is what the send screen offers.
  List<AddressBookEntry> on(SoqNetwork network) =>
      entries.where((e) => e.network == network).toList();

  /// The entry that holds [address], in either case, or null.
  AddressBookEntry? byAddress(String address) {
    final lower = address.trim().toLowerCase();
    for (final e in entries) {
      if (e.address == lower) return e;
    }
    return null;
  }
}

/// The service the notifier writes through, replaceable by a test.
final addressBookServiceProvider =
    Provider<AddressBookService>((_) => AddressBookService());

class AddressBookNotifier extends Notifier<AddressBook> {
  AddressBookService get _service => ref.read(addressBookServiceProvider);

  /// The stored list, read once. Every change waits on it, so a read that
  /// finishes late can never overwrite a change made while it was pending.
  late Future<void> _ready;

  @override
  AddressBook build() {
    _ready = Future.microtask(_load);
    return const AddressBook();
  }

  Future<void> _load() async {
    final entries = await _service.list();
    if (!ref.mounted) return;
    state = AddressBook(entries: entries, loaded: true);
  }

  /// Read the stored list again.
  Future<void> reload() async {
    await _ready;
    if (!ref.mounted) return;
    await _load();
  }

  /// Save [address] under [name]. Throws [AddressBookRefusal] when the
  /// service refuses.
  Future<AddressBookEntry> add({
    required String name,
    required String address,
  }) async {
    await _ready;
    final entry = await _service.add(name: name, address: address);
    await _load();
    return entry;
  }

  Future<AddressBookEntry> rename(String id, String name) async {
    await _ready;
    final entry = await _service.rename(id, name);
    await _load();
    return entry;
  }

  Future<void> remove(String id) async {
    await _ready;
    await _service.remove(id);
    await _load();
  }

  /// Empty, for a wipe. The stored key goes with
  /// SecureStorageService.wipeWallet; this is the state in memory.
  Future<void> resetToDefaults() async {
    await _ready;
    if (!ref.mounted) return;
    state = const AddressBook(loaded: true);
  }
}

final addressBookProvider =
    NotifierProvider<AddressBookNotifier, AddressBook>(AddressBookNotifier.new);
