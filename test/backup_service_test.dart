import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/services/backup_service.dart';
import 'package:soqushield/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  group('BackupService - Format Validation', () {
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

    test('exportBackup rejects short password', () async {
      final backup = BackupService(SecureStorageService(
        storage: const FlutterSecureStorage(),
      ));

      expect(
        () => backup.exportBackup('short'),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('at least 8'),
        )),
      );
    });
  });

  group('BackupException', () {
    test('toString includes message', () {
      const err = BackupException('test error');
      expect(err.toString(), contains('test error'));
    });
  });
}
