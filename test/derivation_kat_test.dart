import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/services/key_service.dart';
import 'package:soqushield/models/wallet_keys.dart';

// CANONICAL key-derivation conformance (bead c7t). KeyService MUST reproduce
// the shared known-answer vectors in test/derivation.kat.json — the SAME file
// the web wallet is tested against (soqu-web/wallet/derivation.kat.json). If
// this fails, the app's derivation drifted from the node/web and seeds are no
// longer portable. Do NOT edit the vectors to make it pass; see
// soqu-web/wallet/DERIVATION.md.
void main() {
  test('KeyService matches the canonical derivation vectors', () async {
    final kat = jsonDecode(File('test/derivation.kat.json').readAsStringSync())
        as Map<String, dynamic>;
    final mnemonic = kat['mnemonic'] as String;
    final ks = KeyService();
    expect(ks.validateMnemonic(mnemonic), isTrue);
    final seed = SeedPhrase(words: mnemonic.split(' '), backupConfirmed: true);
    const nets = {'stagenet': SoqNetwork.stagenet, 'mainnet': SoqNetwork.mainnet};

    for (final v in (kat['vectors'] as List).cast<Map<String, dynamic>>()) {
      final net = nets[v['network']]!;
      final keys = await ks.deriveFromMnemonic(
        seed,
        network: net,
        accountIndex: v['accountIndex'] as int,
      );
      expect(keys.address, v['address'],
          reason: 'DERIVATION DRIFT: ${v['network']} idx${v['accountIndex']} — '
              'app no longer matches the node/web canonical address');
    }
  });
}
