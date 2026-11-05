/// One wallet in the registry: what the owner needs to tell them apart, and
/// where this wallet's secrets live.
///
/// ⛔ CARRIES NO SECRET. The mnemonic stays in secure storage under the keys
/// [SecureStorageService] derives from [id]; this record is the index, and it
/// holds only what a wallet list has to render.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';

import 'wallet_keys.dart';

@immutable
class WalletRecord {
  /// Stable identifier, and the namespace this wallet's secrets live under.
  ///
  /// ⛔ [primaryId] is reserved for the wallet that existed before there was
  /// a registry. Its secrets stay at the original un-namespaced keys, so
  /// adopting it into the registry MOVES NOTHING: a migration that has to
  /// relocate a mnemonic can half-finish, and a half-finished one is a lost
  /// wallet.
  final String id;

  /// What the owner calls it.
  final String name;

  /// The receive address, kept here so a wallet list renders without
  /// re-deriving every wallet's keys — which would need every mnemonic.
  final String address;

  /// The network this wallet was last on.
  final SoqNetwork network;

  final DateTime createdAt;

  /// The id of the wallet that predates the registry.
  static const String primaryId = 'primary';

  const WalletRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.network,
    required this.createdAt,
  });

  bool get isPrimary => id == primaryId;

  WalletRecord copyWith({String? name, String? address, SoqNetwork? network}) =>
      WalletRecord(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        network: network ?? this.network,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'network': network.name,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Null when the entry is unusable — a registry that has been corrupted
  /// must not take the wallet list down with it, and a row that cannot be
  /// read is better dropped than guessed at.
  static WalletRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final address = raw['address'];
    if (id is! String || id.isEmpty) return null;
    if (address is! String || address.isEmpty) return null;
    return WalletRecord(
      id: id,
      name: raw['name'] is String && (raw['name'] as String).trim().isNotEmpty
          ? raw['name'] as String
          : 'Wallet',
      address: address,
      network: SoqNetwork.values.firstWhere(
        (n) => n.name == raw['network'],
        orElse: () => SoqNetwork.mainnet,
      ),
      createdAt:
          DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? DateTime(2026),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WalletRecord &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.network == network;

  @override
  int get hashCode => Object.hash(id, name, address, network);
}
