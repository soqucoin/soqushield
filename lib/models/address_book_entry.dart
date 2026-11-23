/// One saved address: what the owner calls it, the address itself, and the
/// network the address belongs to, read off its prefix.
///
/// ⛔ CARRIES NO SECRET AND NO AMOUNT. The book is a list of places coins
/// can be sent; it never says how many. It lives on this device only, in the
/// shared secure storage, and is not part of the recovery phrase or the
/// encrypted backup.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';

import 'wallet_keys.dart';
import 'wallet_record.dart' show WalletRecord;

@immutable
class AddressBookEntry {
  /// Stable identifier, so a rename or a removal names a row and never an
  /// address typed again.
  final String id;

  /// What the owner calls it. Cleaned by [cleanName]: the name is how the
  /// owner picks who gets paid, so it may not render as something else.
  final String name;

  /// The address, in the lowercase form the rest of the app uses.
  final String address;

  final DateTime createdAt;

  const AddressBookEntry({
    required this.id,
    required this.name,
    required this.address,
    required this.createdAt,
  });

  /// The network this address belongs to. An entry is only ever built from
  /// an address whose prefix names one ([fromJson] drops any other), so the
  /// fallback is never reached.
  SoqNetwork get network => SoqNetwork.ofAddress(address) ?? SoqNetwork.mainnet;

  /// The longest a name may be, and the cleaning it gets: the wallet list's
  /// rule, for the same reason (see [WalletRecord.cleanName]).
  static const int maxNameLength = WalletRecord.maxNameLength;
  static String? cleanName(String raw) => WalletRecord.cleanName(raw);

  /// The name a stored row gets when its own cleans away to nothing.
  static const fallbackName = 'Saved address';

  AddressBookEntry copyWith({String? name}) => AddressBookEntry(
        id: id,
        name: name ?? this.name,
        address: address,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Null when the row is unusable.
  ///
  /// ⛔ NEVER THROWS. One row that cannot be read is dropped; a throw would
  /// escape into the caller's catch and empty the whole book.
  static AddressBookEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final address = raw['address'];
    if (id is! String || id.isEmpty) return null;
    if (address is! String || SoqNetwork.ofAddress(address) == null) return null;
    return AddressBookEntry(
      id: id,
      name: (raw['name'] is String ? cleanName(raw['name'] as String) : null) ??
          fallbackName,
      address: address.toLowerCase(),
      createdAt: raw['createdAt'] is String
          ? DateTime.tryParse(raw['createdAt'] as String) ?? DateTime(2026)
          : DateTime(2026),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AddressBookEntry &&
      other.id == id &&
      other.name == name &&
      other.address == address;

  @override
  int get hashCode => Object.hash(id, name, address);
}
