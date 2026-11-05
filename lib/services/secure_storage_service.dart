import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/wallet_keys.dart';
import '../models/wallet_record.dart';

/// The storage every service other than [SecureStorageService] uses.
///
/// On Android the plugin re-initialises on every call from that call's
/// options: a call with `encryptedSharedPreferences: true` opens the
/// encrypted file and moves every key out of the legacy file into it, while
/// a call without it reads the legacy file. Two option sets in one app
/// therefore shuttle keys between the files, and an instance without the
/// option reads null for anything the wallet's instance has touched since
/// (the auto-lock timeout, the lock-on-background flag, the failed-attempt
/// backoff and the cached UTXO set all reset on a restart). One option set
/// for every instance keeps every key in the one file.
///
/// iOS keeps the plugin's default accessibility here; the wallet's own
/// instance is configured in [SecureStorageService].
const kSharedSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Secure persistent storage for wallet secrets.
///
/// Uses platform-native secure storage:
/// - iOS: Keychain (kSecClassGenericPassword)
/// - Android: EncryptedSharedPreferences (AES-256)
/// - Web: Encrypted localStorage (less secure — shows warning)
///
/// Stores: encrypted mnemonic, public key hex, address, derivation metadata.
/// Private keys are NEVER stored directly — they're re-derived from the
/// mnemonic on each app session.
class SecureStorageService {
  static const _keyMnemonic = 'soq_mnemonic_v2';
  static const _keyPublicKeyHex = 'soq_pubkey_hex_v2';
  static const _keyAddress = 'soq_address_v2';
  static const _keyDerivationPath = 'soq_deriv_path_v2';
  static const _keyAccountIndex = 'soq_account_index_v2';
  static const _keyBackupConfirmed = 'soq_backup_confirmed_v2';
  static const _keyNetwork = 'soq_network_v2';
  static const _keyCreatedAt = 'soq_key_created_v2';
  // The one-time move to Mainnet after block 1 (13 October 2026): 'moved' when
  // the stored network was changed, 'kept' when it was Mainnet already; and
  // whether the member dismissed the notice that explains the move.
  static const _keyMainnetSwitch = 'soq_mainnet_switch_v1';
  static const _keyMainnetSwitchNoticeDismissed =
      'soq_mainnet_switch_notice_dismissed_v1';

  /// The wallet list, and which of them is open.
  static const _keyRegistry = 'soq_wallets_v1';
  static const _keyActiveWallet = 'soq_active_wallet_v1';

  /// Where a wallet's secrets live.
  ///
  /// The rule itself lives in [WalletRecord.scopeKey], because the cached
  /// coin set and the transaction history have to partition by exactly the
  /// same rule and must not be able to drift away from it.
  static String _scoped(String id, String flatKey) =>
      WalletRecord.scopeKey(id, flatKey);

  String mnemonicKeyFor(String id) => _scoped(id, _keyMnemonic);
  String addressKeyFor(String id) => _scoped(id, _keyAddress);

  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                // SECURITY NOTE (FINDING-07): This provides at-rest
                // encryption but NOT biometric-bound access control.
                // The mnemonic is readable after first unlock without
                // requiring biometric re-authentication. True biometric
                // binding requires kSecAccessControlBiometryCurrentSet
                // which flutter_secure_storage does not expose.
                // TODO(v2.0): Implement custom platform channel for
                // biometric-bound Keychain access.
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  // ── Wallet Lifecycle ──

  /// Check if a wallet exists on this device.
  Future<bool> hasWallet() async {
    final mnemonic = await _storage.read(key: _keyMnemonic);
    return mnemonic != null && mnemonic.isNotEmpty;
  }

  /// Store the wallet mnemonic and derived metadata.
  /// The mnemonic is the ONLY secret — everything else is re-derivable.
  Future<void> storeWallet({
    required String mnemonic,
    required WalletKeys keys,
    required SoqNetwork network,
  }) async {
    await _storage.write(key: _keyMnemonic, value: mnemonic);
    await _storage.write(
      key: _keyPublicKeyHex,
      value: keys.publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    await _storage.write(key: _keyAddress, value: keys.address);
    await _storage.write(key: _keyDerivationPath, value: keys.derivationPath);
    await _storage.write(key: _keyAccountIndex, value: keys.accountIndex.toString());
    await _storage.write(key: _keyNetwork, value: network.name);
    await _storage.write(key: _keyCreatedAt, value: DateTime.now().toIso8601String());
  }

  /// Read the stored mnemonic (needed for key re-derivation and signing).
  /// Returns null if no wallet exists.
  Future<String?> readMnemonic() async {
    return _storage.read(key: _keyMnemonic);
  }

  /// Read the stored address (fast path — no re-derivation needed).
  Future<String?> readAddress() async {
    return _storage.read(key: _keyAddress);
  }

  /// Read the stored network.
  Future<SoqNetwork> readNetwork() async {
    final name = await _storage.read(key: _keyNetwork);
    return SoqNetwork.values.firstWhere(
      (n) => n.name == name,
      orElse: () => SoqNetwork.stagenet,
    );
  }

  /// Store the network alone, for the one-time move to Mainnet at boot.
  Future<void> writeNetwork(SoqNetwork network) async {
    await _storage.write(key: _keyNetwork, value: network.name);
  }

  /// The one-time move to Mainnet: null when it has not been decided on this
  /// install, 'moving' while the move is being written (the stored network
  /// may or may not be Mainnet yet; the next boot completes the move),
  /// 'moved' when the stored network was changed to Mainnet, 'kept' when it
  /// was Mainnet already.
  Future<String?> readMainnetSwitch() async {
    return _storage.read(key: _keyMainnetSwitch);
  }

  /// Recorded before the stored network is rewritten, so a move interrupted
  /// by a failed write is completed at the next boot and still shows the
  /// notice, instead of reading as an install that was on Mainnet already.
  Future<void> markMainnetSwitchMoving() async {
    await _storage.write(key: _keyMainnetSwitch, value: 'moving');
  }

  Future<void> markMainnetSwitch({required bool moved}) async {
    await _storage.write(key: _keyMainnetSwitch, value: moved ? 'moved' : 'kept');
  }

  Future<bool> isMainnetSwitchNoticeDismissed() async {
    return await _storage.read(key: _keyMainnetSwitchNoticeDismissed) == 'true';
  }

  Future<void> dismissMainnetSwitchNotice() async {
    await _storage.write(key: _keyMainnetSwitchNoticeDismissed, value: 'true');
  }

  /// Read the stored account index.
  Future<int> readAccountIndex() async {
    final idx = await _storage.read(key: _keyAccountIndex);
    return int.tryParse(idx ?? '0') ?? 0;
  }

  // ── The wallet registry ──

  /// Every wallet on this device, in the order they were added.
  ///
  /// An unreadable registry yields an empty list rather than throwing: the
  /// app must still open, and [adoptExistingWallet] will rebuild an entry for
  /// the wallet whose secrets are actually present.
  Future<List<WalletRecord>> listWallets() async {
    try {
      final raw = await _storage.read(key: _keyRegistry);
      if (raw == null || raw.isEmpty) return [];
      final decoded = json.decode(raw);
      if (decoded is! List) return [];
      // Row by row: a single entry that cannot be read is dropped, and the
      // wallets either side of it still reach the caller.
      final wallets = <WalletRecord>[];
      for (final row in decoded) {
        try {
          final record = WalletRecord.fromJson(row);
          if (record != null) wallets.add(record);
        } catch (e) {
          debugPrint('SecureStorage: dropping an unreadable registry row: $e');
        }
      }
      return wallets;
    } catch (e) {
      debugPrint('SecureStorage: registry unreadable, treating as empty: $e');
      return const [];
    }
  }

  Future<void> _writeRegistry(List<WalletRecord> wallets) async {
    await _storage.write(
      key: _keyRegistry,
      value: json.encode(wallets.map((w) => w.toJson()).toList()),
    );
  }

  /// Add [record], or replace the entry that already carries its id.
  Future<void> putWallet(WalletRecord record) async {
    // A growable copy: listWallets may hand back a fixed-length list.
    final wallets = List<WalletRecord>.of(await listWallets());
    final i = wallets.indexWhere((w) => w.id == record.id);
    if (i >= 0) {
      wallets[i] = record;
    } else {
      wallets.add(record);
    }
    await _writeRegistry(wallets);
  }

  /// The wallet currently open, or null when there is none.
  ///
  /// A pointer at a wallet that is no longer in the registry reads as null
  /// rather than as that id: the caller's next step is to open a wallet, and
  /// opening one that has been removed would read secrets that are gone.
  Future<String?> activeWalletId() async {
    final id = await _storage.read(key: _keyActiveWallet);
    if (id == null || id.isEmpty) return null;
    final wallets = await listWallets();
    return wallets.any((w) => w.id == id) ? id : null;
  }

  /// Open [id]. Refuses an id the registry does not carry.
  Future<void> setActiveWallet(String id) async {
    final wallets = await listWallets();
    if (!wallets.any((w) => w.id == id)) {
      throw ArgumentError.value(id, 'id', 'no such wallet in the registry');
    }
    await _storage.write(key: _keyActiveWallet, value: id);
  }

  /// Bring a pre-registry wallet into the registry, moving nothing.
  ///
  /// Call on boot. It is a no-op when there is no wallet on the device, and
  /// when the registry already names one and a wallet is already open.
  ///
  /// ⛔ RESUMABLE. Adoption is two writes: the registry row, then the
  /// pointer at the open wallet. Stopping between them used to be permanent
  /// — the next run saw a non-empty registry, returned early, and left the
  /// pointer null forever. Each write is therefore checked on its own, so a
  /// run that was cut short finishes on the next boot.
  ///
  /// The adopted wallet keeps the original keys, so an interrupted run
  /// leaves the wallet itself exactly as it was.
  Future<void> adoptExistingWallet({String name = 'Main wallet'}) async {
    if (!await hasWallet()) return;

    var wallets = await listWallets();

    if (wallets.isEmpty) {
      final address = await readAddress();
      if (address == null || address.isEmpty) return;

      final created = DateTime.tryParse(
              await _storage.read(key: _keyCreatedAt) ?? '') ??
          DateTime.now();

      await putWallet(WalletRecord(
        id: WalletRecord.primaryId,
        name: name,
        address: address,
        network: await readNetwork(),
        createdAt: created,
      ));
      wallets = await listWallets();
    }

    // A pointer that names a wallet still in the registry is the owner's
    // own choice of which wallet is open; leave it alone. Only a missing or
    // dangling one is repaired, and only to a wallet that exists.
    final pointer = await _storage.read(key: _keyActiveWallet);
    final valid = pointer != null && wallets.any((w) => w.id == pointer);
    if (!valid && wallets.isNotEmpty) {
      final target = wallets.any((w) => w.isPrimary)
          ? WalletRecord.primaryId
          : wallets.first.id;
      await _storage.write(key: _keyActiveWallet, value: target);
    }
  }

  // ── Backup Management ──

  /// Mark that the user has confirmed their seed phrase backup.
  Future<void> confirmBackup() async {
    await _storage.write(key: _keyBackupConfirmed, value: 'true');
  }

  /// Check if the user has confirmed their seed phrase backup.
  Future<bool> isBackupConfirmed() async {
    final val = await _storage.read(key: _keyBackupConfirmed);
    return val == 'true';
  }

  // ── Danger Zone ──

  /// Wipe all wallet data from this device. IRREVERSIBLE.
  /// User must have their seed phrase to recover.
  ///
  /// SS-10: uses `deleteAll()` rather than deleting a fixed list of named keys.
  /// The old named-key list missed the XMSS vault seed (`xmss_vault_seed_v1`),
  /// which `XmssKeyManager` writes to this SAME secure-storage namespace
  /// (identical Android `encryptedSharedPreferences` + iOS accessibility
  /// options) — so a "wiped" device leaked the prior user's fund-controlling
  /// vault seed. `deleteAll()` clears the mnemonic, the vault seed, and any
  /// future secret in this namespace, and can't drift out of sync.
  ///
  /// Earlier builds also wrote identity and swap state through a default
  /// storage instance ([legacyDefaultKeys]). On iOS those items carry the
  /// default keychain accessibility, which this instance's `deleteAll` does
  /// not match, so a wipe deletes each by name through the shared instance,
  /// which has that accessibility.
  Future<void> wipeWallet() async {
    await _storage.deleteAll();
    for (final key in [...legacyDefaultKeys, ...sessionKeys]) {
      await kSharedSecureStorage.delete(key: key);
    }
  }

  /// The session settings the session notifier keeps through the shared
  /// instance: the auto-lock timeout, lock on background, the failed-attempt
  /// count and the lockout end. A wipe removes them, so the next wallet on
  /// the device starts from the defaults; the notifier's own list of its
  /// keys is pinned to this one by a test.
  static const sessionKeys = [
    'soq_session_timeout_v1',
    'soq_lock_on_bg_v1',
    'soq_failed_attempts_v1',
    'soq_locked_until_v1',
  ];

  /// Keys the 2.1 build wrote through a default storage instance: the social
  /// sign-in session and the pending treasury swap. Neither feature exists in
  /// this build; a wipe still has to remove what an upgrade carried over.
  static const legacyDefaultKeys = [
    'soq_social_provider',
    'soq_social_user_id',
    'soq_social_email',
    'soq_social_display_name',
    'soq_pending_swap_v1',
  ];
}
