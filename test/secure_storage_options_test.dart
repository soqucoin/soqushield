// One secure-storage option set across the app. On Android the plugin
// re-initialises from each call's options and, on a call that asks for the
// encrypted file, moves every key into it, so an instance without the option
// reads null for anything the wallet's instance has touched since. Every
// construction under lib/ therefore asks for the encrypted file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The file with its comment lines removed, so a construction named in a
/// doc comment does not count.
String _code(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('every FlutterSecureStorage constructed under lib/ asks for the '
      'encrypted preferences on Android', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    var constructions = 0;
    for (final f in files) {
      final src = _code(f);
      final built = 'FlutterSecureStorage('.allMatches(src).length;
      if (built == 0) continue;
      constructions += built;
      final encrypted =
          'AndroidOptions(encryptedSharedPreferences: true)'.allMatches(src).length;
      expect(encrypted, built,
          reason: '${f.path}: each construction carries the Android option, '
              'or uses kSharedSecureStorage');
    }
    // The wallet's instance, the shared instance and the vault's.
    expect(constructions, 3);
  });

  test('the services outside the storage service use the shared instance', () {
    for (final path in const [
      'lib/services/utxo_service.dart',
      'lib/services/auth_service.dart',
      'lib/providers/session_provider.dart',
    ]) {
      expect(_code(File(path)), contains('kSharedSecureStorage'),
          reason: '$path reads and writes through the shared instance');
    }
  });
}
