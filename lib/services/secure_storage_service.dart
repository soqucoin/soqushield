import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/wallet_keys.dart';

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

  /// Read the stored account index.
  Future<int> readAccountIndex() async {
    final idx = await _storage.read(key: _keyAccountIndex);
    return int.tryParse(idx ?? '0') ?? 0;
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
    for (final key in legacyDefaultKeys) {
      await kSharedSecureStorage.delete(key: key);
    }
  }

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
