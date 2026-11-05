import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/services/backup_service.dart';
import 'package:soqushield/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'lite_test_support.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

const _password = 'a-long-enough-passphrase';

/// A v1 file — PBKDF2-SHA256 at 100k — built the way the old exporter did, so
/// the compatibility test does not depend on keeping dead encrypt code around.
Uint8List _legacyV1File(String mnemonic, String password) {
  final salt = Uint8List.fromList(List.generate(32, (i) => i));
  final nonce = Uint8List.fromList(List.generate(12, (i) => 200 - i));
  final key = (PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, 100000, 32)))
      .process(Uint8List.fromList(utf8.encode(password)));
  final payload = utf8.encode(json.encode({
    'version': 1,
    'mnemonic': mnemonic,
    'address': 'sq1legacy',
    'network': 'mainnet',
    'accountIndex': 0,
  }));
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
  return Uint8List.fromList([
    0x53, 0x4f, 0x51, 0x42, // "SOQB"
    0x01, // v1
    ...salt,
    ...nonce,
    ...cipher.process(Uint8List.fromList(payload)),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('BackupService - Format Validation', () {
    // The minimum-length boundary below reaches the storage read, so the
    // in-memory secure storage has to be in place for this group too.
    setUp(installSecureStorageMock);

    test('magic bytes are correct', () {
      // "SOQB" = 0x53, 0x4F, 0x51, 0x42
      expect([0x53, 0x4F, 0x51, 0x42], [83, 79, 81, 66]);
    });

    test('importBackup rejects too-small files', () async {
      final backup = BackupService(SecureStorageService(
        storage: const FlutterSecureStorage(),
      ));

      expect(
        () => backup.importBackup(Uint8List(10), 'password123'),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('too small'),
        )),
      );
    });

    test('importBackup rejects wrong magic bytes', () async {
      final backup = BackupService(SecureStorageService(
        storage: const FlutterSecureStorage(),
      ));

      final badFile = Uint8List(100);
      badFile[0] = 0xFF; // Wrong magic

      expect(
        () => backup.importBackup(badFile, 'password123'),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Not a valid'),
        )),
      );
    });

    test('importBackup rejects wrong version', () async {
      final backup = BackupService(SecureStorageService(
        storage: const FlutterSecureStorage(),
      ));

      final badFile = Uint8List(100);
      badFile[0] = 0x53; // S
      badFile[1] = 0x4F; // O
      badFile[2] = 0x51; // Q
      badFile[3] = 0x42; // B
      badFile[4] = 0xFF; // Wrong version

      expect(
        () => backup.importBackup(badFile, 'password123'),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Unsupported backup version'),
        )),
      );
    });

    test('exportBackup rejects a password shorter than the minimum', () async {
      final backup = BackupService(SecureStorageService(
        storage: const FlutterSecureStorage(),
      ));

      expect(
        () => backup.exportBackup('short'),
        throwsA(isA<BackupException>().having((e) => e.message, 'message',
            contains('at least ${BackupService.minPasswordLength}'))),
      );
      // The boundary itself: one short fails, exactly the minimum is allowed
      // through to the storage read (which returns null — no wallet here).
      expect(
        () => backup.exportBackup('x' * (BackupService.minPasswordLength - 1)),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
          backup.exportBackup('x' * BackupService.minPasswordLength),
          completion(isNull));
    });
  });

  group('the file this wallet writes today', () {
    late BackupService backup;

    setUp(() async {
      installSecureStorageMock();
      final storage = SecureStorageService();
      await storage.storeWallet(
        mnemonic: _mnemonic,
        keys: WalletKeys(
          publicKey: Uint8List(WalletKeys.pubKeySize),
          address: 'sq1test',
          derivationPath: "m/44'/21329'/0'/0/0",
          accountIndex: 0,
          createdAt: DateTime(2026, 1, 1),
        ),
        network: SoqNetwork.mainnet,
      );
      backup = BackupService(storage);
    });

    test('is Argon2id (v2), and round-trips', () async {
      final bytes = (await backup.exportBackup(_password))!;
      expect(bytes.sublist(0, 4), [0x53, 0x4f, 0x51, 0x42]);
      expect(bytes[4], 0x02, reason: 'new exports are v2 / Argon2id');

      expect(await backup.importBackup(bytes, _password), _mnemonic);
    });

    test('a wrong password does not open it', () async {
      final bytes = (await backup.exportBackup(_password))!;
      await expectLater(
        backup.importBackup(bytes, '${_password}x'),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('wrong password'))),
      );
    });

    test('salt and nonce are fresh on every export', () async {
      final a = (await backup.exportBackup(_password))!;
      final b = (await backup.exportBackup(_password))!;
      expect(a.sublist(5, 37), isNot(b.sublist(5, 37)), reason: 'salt');
      expect(a.sublist(37, 49), isNot(b.sublist(37, 49)), reason: 'nonce');
    });

    test('a flipped ciphertext byte is rejected, not silently accepted',
        () async {
      final bytes = (await backup.exportBackup(_password))!;
      bytes[bytes.length - 20] ^= 0xFF;
      await expectLater(
          backup.importBackup(bytes, _password), throwsA(isA<BackupException>()));
    });
  });

  group('backups taken before the Argon2id change still restore', () {
    setUp(installSecureStorageMock);

    test('a v1 PBKDF2 file imports', () async {
      final backup = BackupService(SecureStorageService());
      final v1 = _legacyV1File(_mnemonic, _password);
      expect(v1[4], 0x01);
      expect(await backup.importBackup(v1, _password), _mnemonic);
    });

    test('a v1 file with the wrong password still fails closed', () async {
      final backup = BackupService(SecureStorageService());
      await expectLater(
        backup.importBackup(_legacyV1File(_mnemonic, _password), 'not-it-at-all'),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('BackupException', () {
    test('toString includes message', () {
      const err = BackupException('test error');
      expect(err.toString(), contains('test error'));
    });
  });

  group('the v2 key is Argon2id at the profile it claims', () {
    // ⛔ A KNOWN-ANSWER TEST, not a round trip. Round-tripping through one
    // implementation still passes if the parameters are weakened or the
    // algorithm swapped, which is exactly the failure worth catching: it
    // would silently halve the cost of cracking a stolen backup, and it
    // would break every v2 file already written.
    //
    // The vector below was produced by argon2-cffi 25.1.0 (the reference C
    // library), independently of pointycastle:
    //
    //   hash_secret_raw(secret=b'correct horse battery staple',
    //                   salt=bytes(range(32)), time_cost=3,
    //                   memory_cost=65536, parallelism=1, hash_len=32,
    //                   type=Type.ID, version=19)
    test('matches a vector from the reference C implementation', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final key = deriveBackupKey(
          'correct horse battery staple', salt, BackupService.versionArgon2id);
      expect(
        key.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '6ed12d7d594a6ae56c7ad1725982ae0d41317bd2b239dd1e0916d913d4da0757',
      );
    });

    test('the profile constants are the ones OWASP recommends', () {
      expect(BackupService.argonMemoryKiB, 64 * 1024);
      expect(BackupService.argonIterations, 3);
      expect(BackupService.argonLanes, 1);
      expect(BackupService.keyLength, 32);
    });

    test('a v1 file still derives under PBKDF2, not Argon2id', () {
      final salt = Uint8List.fromList(List.generate(32, (i) => i));
      final v1 = deriveBackupKey('x' * 12, salt, BackupService.versionPbkdf2);
      final v2 = deriveBackupKey('x' * 12, salt, BackupService.versionArgon2id);
      expect(v1, isNot(equals(v2)),
          reason: 'the version byte must actually select the KDF');
    });
  });
}
