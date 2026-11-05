import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import '../services/secure_storage_service.dart';
import '../services/xmss_key_manager.dart';

/// Encrypted wallet backup service.
///
/// Exports to `.soqbackup` format — AES-256-GCM encrypted JSON under a
/// password-derived key. The user provides the password; the file contains no
/// plaintext secrets.
///
/// Format (both versions share a layout; only the KDF differs):
///   4 bytes:  magic "SOQB"
///   1 byte:   version
///   32 bytes: KDF salt
///   12 bytes: AES-GCM nonce
///   N bytes:  AES-256-GCM ciphertext (JSON payload + 16-byte tag)
///
/// ── v2 (written today): Argon2id ──
/// This file holds the 24 words. It leaves the device — into cloud storage, a
/// chat, an email — so the password is the ONLY thing between an attacker who
/// has the file and the wallet. PBKDF2 (v1, below) is a poor defence there: it
/// is compute-hard but not MEMORY-hard, so a GPU or ASIC runs thousands of
/// guesses in parallel at negligible cost per guess, and raising the iteration
/// count buys only linear time while the attacker's hardware advantage stays
/// exponential.
///
/// Argon2id at 64 MiB forces every single guess to allocate 64 MiB, which is
/// what actually destroys parallel cracking. Measured locally it costs ~450 ms
/// against ~1.2 s for PBKDF2 at 600k iterations — better protection for less
/// waiting. Parameters are OWASP's recommended Argon2id profile.
///
/// ── v1 (read-only): PBKDF2-SHA256, 100k ──
/// Still imported so existing backups keep working. Never written.
class BackupService {
  static const _magic = [0x53, 0x4f, 0x51, 0x42]; // "SOQB"

  /// The version written by [exportBackup].
  static const _version = 0x02;

  /// v1, PBKDF2-SHA256. Import-only.
  static const _versionPbkdf2 = 0x01;
  static const _pbkdf2Iterations = 100000;

  /// v2, Argon2id — OWASP's recommended profile (m=64 MiB, t=3, p=1).
  static const _versionArgon2id = 0x02;
  static const _argonMemoryKiB = 64 * 1024;
  static const _argonIterations = 3;
  static const _argonLanes = 1;

  static const _keyLength = 32; // AES-256

  /// Minimum password length for a NEW export.
  ///
  /// A strong KDF cannot rescue a short human-chosen password: Argon2id only
  /// multiplies the cost per guess, and the guess list for 8 human-chosen
  /// characters is short enough that the multiplier still loses. Length is the
  /// one factor that moves the exponent. Existing shorter-password backups
  /// still import — this gate is on writing, not reading.
  static const minPasswordLength = 12;

  final SecureStorageService _storage;

  BackupService(this._storage);

  /// Export wallet data as an encrypted `.soqbackup` byte array.
  ///
  /// The [password] must be at least [minPasswordLength] characters. It is
  /// used to derive the AES-256 key via Argon2id (format v2).
  ///
  /// Returns the encrypted backup bytes, or null if no wallet exists.
  Future<Uint8List?> exportBackup(String password) async {
    if (password.length < minPasswordLength) {
      throw BackupException(
          'Password must be at least $minPasswordLength characters');
    }

    // Gather wallet data
    final mnemonic = await _storage.readMnemonic();
    if (mnemonic == null) return null;

    final address = await _storage.readAddress();
    final network = await _storage.readNetwork();
    final accountIndex = await _storage.readAccountIndex();

    // SB-2 (Option A): include the XMSS vault keystate so a vault created with a
    // random seed — which the mnemonic alone cannot regenerate — is recoverable
    // from this encrypted backup. Null when no vault has been created.
    final xmssVault = await XmssKeyManager().exportVaultMap();

    final payload = json.encode({
      'version': 1,
      'mnemonic': mnemonic,
      'address': address,
      'network': network.name,
      'accountIndex': accountIndex,
      'xmssVault': ?xmssVault,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'SoquShield',
    });

    // A3-02: Generate random salt and nonce using platform CSPRNG.
    // SECURITY FIX: Previous code seeded FortunaRandom with
    // DateTime.now().microsecond % 256 — producing only 256 possible seeds.
    // Now uses dart:math Random.secure() which delegates to the OS CSPRNG
    // (/dev/urandom on iOS/Android, CryptGenRandom on Windows).
    final secureRandom = math.Random.secure();
    final salt = Uint8List.fromList(
      List.generate(32, (_) => secureRandom.nextInt(256)),
    );
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => secureRandom.nextInt(256)),
    );

    // Derive key via PBKDF2-SHA256
    final key = _deriveKey(password, salt, _version);

    // Encrypt with AES-256-GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          nonce,
          Uint8List(0), // no AAD
        ),
      );

    final plaintext = Uint8List.fromList(utf8.encode(payload));
    final ciphertext = cipher.process(plaintext);

    // Build file: magic + version + salt + nonce + ciphertext
    final buf = BytesBuilder();
    buf.add(_magic);
    buf.addByte(_version);
    buf.add(salt);
    buf.add(nonce);
    buf.add(ciphertext);

    return buf.toBytes();
  }

  /// Import wallet data from an encrypted `.soqbackup` file.
  ///
  /// Decrypts using [password], validates the payload, and stores
  /// the mnemonic to secure storage.
  ///
  /// Returns the wallet address on success.
  Future<String> importBackup(Uint8List fileBytes, String password) async {
    // Validate format
    if (fileBytes.length < 49) {
      throw BackupException('File too small to be a valid backup');
    }

    // Check magic bytes
    if (fileBytes[0] != _magic[0] ||
        fileBytes[1] != _magic[1] ||
        fileBytes[2] != _magic[2] ||
        fileBytes[3] != _magic[3]) {
      throw BackupException('Not a valid .soqbackup file');
    }

    final version = fileBytes[4];
    // v1 (PBKDF2) is still read so backups taken before the Argon2id change
    // keep restoring; only v2 is written.
    if (version != _versionArgon2id && version != _versionPbkdf2) {
      throw BackupException('Unsupported backup version: $version');
    }

    // Extract components
    final salt = fileBytes.sublist(5, 37);
    final nonce = fileBytes.sublist(37, 49);
    final ciphertext = fileBytes.sublist(49);

    // Derive the key with the KDF this file's version names.
    final key = _deriveKey(password, salt, version);

    // Decrypt
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false, // decrypt
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List(0),
          ),
        );

      final plaintext = cipher.process(Uint8List.fromList(ciphertext));
      final payloadStr = utf8.decode(plaintext);
      final payload = json.decode(payloadStr) as Map<String, dynamic>;

      final mnemonic = payload['mnemonic'] as String?;

      if (mnemonic == null || mnemonic.isEmpty) {
        throw BackupException('Backup file contains no mnemonic');
      }

      // SB-2 (Option A): restore the XMSS vault keystate if the backup carries
      // it. importVaultMap() is a no-op when a vault already exists on-device,
      // so this never clobbers a live seed.
      final xmssVault = payload['xmssVault'];
      if (xmssVault is Map<String, dynamic>) {
        await XmssKeyManager().importVaultMap(xmssVault);
      }

      return mnemonic;
    } catch (e) {
      if (e is BackupException) rethrow;
      throw BackupException('Decryption failed — wrong password?');
    }
  }

  /// Derive the AES-256 key, with the KDF [version] names.
  ///
  /// The version byte is what selects the KDF, so a v1 file keeps opening
  /// under PBKDF2 while everything written today uses Argon2id.
  Uint8List _deriveKey(String password, Uint8List salt, int version) {
    final pw = Uint8List.fromList(utf8.encode(password));
    try {
      if (version == _versionPbkdf2) {
        final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
          ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));
        return pbkdf2.process(pw);
      }

      final argon2 = Argon2BytesGenerator()
        ..init(Argon2Parameters(
          Argon2Parameters.ARGON2_id,
          salt,
          version: Argon2Parameters.ARGON2_VERSION_13,
          iterations: _argonIterations,
          memory: _argonMemoryKiB,
          lanes: _argonLanes,
          desiredKeyLength: _keyLength,
        ));
      final out = Uint8List(_keyLength);
      argon2.deriveKey(pw, 0, out, 0);
      return out;
    } finally {
      // The password bytes are the input to the only thing guarding the seed.
      pw.fillRange(0, pw.length, 0);
    }
  }
}

/// Backup operation error.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}
