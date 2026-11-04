// The exported backup passes through the app's temporary folder only for
// the share sheet: the app's copy exists while the sheet is open and is gone
// once it closes, whether the sheet succeeded or failed; a copy an earlier
// export left behind goes first; the share plugin's own cache copy, which
// the receiving app may still be reading, is left to the plugin.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/services/backup_handoff.dart';

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('soqushield-handoff-');
  });

  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  test('the copy feeds the sheet, is gone after it, and a stale copy goes first',
      () async {
    final stale = File('${folder.path}/soqushield_backup_1.soqbackup')
      ..writeAsStringSync('left by a dead process');
    final other = File('${folder.path}/unrelated.txt')..writeAsStringSync('x');
    final cache = Directory('${folder.path}/share_plus')..createSync();
    final pluginCopy = File('${cache.path}/copy.soqbackup')
      ..writeAsStringSync('the plugin\'s copy');
    String? shared;
    await handOffBackup(Uint8List.fromList([1, 2, 3]), folder: folder,
        share: (file) async {
      shared = file.path;
      expect(File(file.path).readAsBytesSync(), [1, 2, 3],
          reason: 'the sheet is handed the backup bytes');
      expect(stale.existsSync(), isFalse,
          reason: 'a copy a previous export left is gone before the sheet');
    });
    expect(shared, endsWith('.soqbackup'));
    expect(File(shared!).existsSync(), isFalse,
        reason: 'the app\'s copy is gone once the sheet has closed');
    expect(other.existsSync(), isTrue, reason: 'nothing else is touched');
    expect(pluginCopy.existsSync(), isTrue,
        reason: 'the plugin\'s copy may still be read by the receiving app');
  });

  test('a sheet that fails still leaves no copy of the app\'s own', () async {
    await expectLater(
        handOffBackup(Uint8List.fromList([9]),
            folder: folder, share: (_) async => throw StateError('no sheet')),
        throwsStateError);
    expect(folder.listSync(), isEmpty);
  });

  test('a folder that cannot be listed stops the export before the sheet',
      () async {
    // A path that is a file, not a folder: listing it fails with an error
    // other than not-found, as a permission or I/O failure would.
    final notAFolder = File('${folder.path}/not-a-folder')
      ..writeAsStringSync('x');
    var sheetOpened = false;
    await expectLater(
        handOffBackup(Uint8List.fromList([7]),
            folder: Directory(notAFolder.path),
            share: (_) async => sheetOpened = true),
        throwsA(isA<BackupCleanupError>()));
    expect(sheetOpened, isFalse, reason: 'no sheet opens after a failed sweep');
  });

  test('a folder that does not exist holds no earlier copy to sweep', () async {
    final missing = Directory('${folder.path}/missing');
    await expectLater(
        handOffBackup(Uint8List.fromList([5]),
            folder: missing, share: (_) async {}),
        throwsA(isA<FileSystemException>()),
        reason: 'the sweep passes; writing into a missing folder then fails');
  });
}
