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

  /// The longest a wallet name may be. Long enough to be descriptive, short
  /// enough that a list row renders it whole rather than cutting it off
  /// mid-word — a name the owner cannot read in full is a name they cannot
  /// pick a wallet by.
  static const int maxNameLength = 40;

  /// What a wallet may actually be called.
  ///
  /// ⛔ THE NAME IS HOW THE OWNER PICKS WHICH WALLET SIGNS. It is the label
  /// beside a balance and in a send confirmation, so a name that renders as
  /// something other than what it is can send the wrong wallet's coins.
  /// Three things are therefore taken out of it:
  ///
  ///  - bidirectional overrides (U+202A..U+202E, U+2066..U+2069), which
  ///    reorder the characters AFTER them and can make one name draw as
  ///    another entirely;
  ///  - every other control character, which can blank or truncate a row;
  ///  - runs of whitespace, collapsed to one space, so two names cannot
  ///    differ only by padding that nothing renders.
  ///
  /// Tab, newline and carriage return are left to the whitespace pass on
  /// purpose. Stripping them as control characters would JOIN the words
  /// either side — "day\nto\nday" becoming "daytoday" — and a name that
  /// runs two words together is harder to read than one with a space.
  ///
  /// Returns null when nothing usable is left, so the caller refuses rather
  /// than storing a blank.
  static String? cleanName(String raw) {
    final stripped = raw.replaceAll(
        RegExp(r'[\u0000-\u0008\u000E-\u001F\u007F-\u009F'
                r'\u202A-\u202E\u2066-\u2069]'),
        '');
    final collapsed = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    // Cut on code points, never on code units: half of a surrogate pair is
    // not a character, and storing one would render as a replacement box.
    final runes = collapsed.runes.toList();
    if (runes.length <= maxNameLength) return collapsed;
    final cut = String.fromCharCodes(runes.take(maxNameLength)).trim();
    return cut.isEmpty ? null : cut;
  }

  /// The one rule for turning a per-wallet storage key into a real one.
  ///
  /// ⛔ [primaryId] passes [flatKey] through UNCHANGED. Every partition that
  /// existed before the registry — the mnemonic, the cached coin set, the
  /// transaction history — stays exactly where it was written, so bringing
  /// the registry in moves no stored byte. Any wallet added afterwards gets
  /// its own prefix and can never read or overwrite another wallet's.
  ///
  /// Every service that partitions by wallet calls THIS, so the rule cannot
  /// drift apart between them: two services disagreeing about where a
  /// wallet's data lives is how one wallet comes to spend another's coins.
  static String scopeKey(String walletId, String flatKey) =>
      walletId == primaryId ? flatKey : 'soq_w_${walletId}_$flatKey';

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
  ///
  /// ⛔ NEVER THROWS. It returns null for anything it cannot read, field by
  /// field. A throw from here escapes into the caller's catch and empties
  /// the whole list, which turns one unreadable row into every wallet
  /// vanishing from the registry.
  static WalletRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final address = raw['address'];
    if (id is! String || id.isEmpty) return null;
    if (address is! String || address.isEmpty) return null;
    return WalletRecord(
      id: id,
      // Cleaned on the way in too: a registry written by an older build, or
      // edited outside the app, must not put an unrenderable name on screen.
      name: (raw['name'] is String ? cleanName(raw['name'] as String) : null) ??
          'Wallet',
      address: address,
      network: SoqNetwork.values.firstWhere(
        (n) => n.name == raw['network'],
        orElse: () => SoqNetwork.mainnet,
      ),
      // Type-checked, not cast: a row whose createdAt is a number would
      // throw here, and the caller catches around the WHOLE registry — so
      // one bad row would hide every healthy wallet and the next write
      // would overwrite them.
      createdAt: raw['createdAt'] is String
          ? DateTime.tryParse(raw['createdAt'] as String) ?? DateTime(2026)
          : DateTime(2026),
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
