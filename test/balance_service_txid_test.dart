// The raw-transaction read takes its id from the history service. The attack:
// an id that is not 64 hex characters is refused before any request, since a
// '../' segment in it would resolve to another route on the same host. A real
// id is still fetched.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/services/balance_service.dart';

void main() {
  test('an id that is not 64 hex characters never reaches the network',
      () async {
    final requests = <Uri>[];
    final service = BalanceService(
      client: MockClient((r) async {
        requests.add(r.url);
        return http.Response('{"data":"00"}', 200);
      }),
      network: SoqNetwork.mainnet,
    );
    final id = 'f' * 64;
    for (final bad in [
      '../../admin',
      '',
      'f' * 63,
      '$id/..',
      '$id?next=1',
      '$id\n',
    ]) {
      await expectLater(service.getRawTransaction(bad), throwsFormatException,
          reason: 'id "$bad"');
    }
    expect(requests, isEmpty);

    expect(await service.getRawTransaction(id), '00');
    expect(requests.single.path, '/api/v2/tx/$id');
  });
}
