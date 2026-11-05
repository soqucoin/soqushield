import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Hands an encrypted backup to the system share sheet as a `.soqbackup`
/// file through [folder], the app's temporary folder, and removes the app's
/// copy once the sheet has closed, whether the share succeeded or failed,
/// so the backup rests nowhere the app itself keeps. Any copy a previous
/// export left behind (a process death during the sheet) goes first.
///
/// Only a copy that is already gone is passed over. A folder that cannot be
/// listed or a copy that cannot be deleted raises [BackupCleanupError]:
/// before the sheet, the export stops; after it, the caller reports it.
///
/// On Android the share plugin copies the file into a cache folder of its
/// own and hands that copy to the receiving app, which may still be reading
/// it when the sheet returns (a background upload); the plugin replaces that
/// copy at the next share, and this helper leaves it alone. [share] is the
/// sheet call, injected so a test can stand in for it.
Future<void> handOffBackup(
  Uint8List bytes, {
  required Directory folder,
  required Future<void> Function(XFile file) share,
}) async {
  await _sweep(folder);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${folder.path}/soqushield_backup_$stamp.soqbackup');
  try {
    await file.writeAsBytes(bytes, flush: true);
    await share(XFile(file.path));
  } finally {
    await _remove(file);
  }
}

/// A backup copy in the app's temporary folder could not be removed, or the
/// folder could not be listed to find one.
class BackupCleanupError implements Exception {
  BackupCleanupError(this.cause);

  final FileSystemException cause;

  @override
  String toString() => 'BackupCleanupError: ${cause.message}';
}

/// Removes the copies earlier exports may have left in [folder].
Future<void> _sweep(Directory folder) async {
  try {
    await for (final entity in folder.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          name.startsWith('soqushield_backup_') &&
          name.endsWith('.soqbackup')) {
        await _remove(entity);
      }
    }
  } on PathNotFoundException {
    // No folder, so no copy an earlier export left.
  } on FileSystemException catch (e) {
    throw BackupCleanupError(e);
  }
}

Future<void> _remove(File file) async {
  try {
    await file.delete();
  } on PathNotFoundException {
    // Already gone: nothing to do.
  } on FileSystemException catch (e) {
    throw BackupCleanupError(e);
  }
}
