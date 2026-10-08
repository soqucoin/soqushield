import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/app_version.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/services/rpc_service.dart';

/// Mainnet-readiness pins (bead m4f P1/P2): the handful of places where a
/// wrong value silently ships a broken mainnet client.
void main() {
  group('Endpoint truth', () {
    test('RpcService.hostFor maps each network to its permanent hostname', () {
      expect(RpcService.hostFor(SoqNetwork.mainnet), 'mainnet-rpc.soqu.org');
      expect(RpcService.hostFor(SoqNetwork.stagenet), 'staging-rpc.soqu.org');
    });

    test('no endpoint references the decommissioned sim proxy', () {
      expect(RpcService.hostFor(SoqNetwork.mainnet).contains('sim'), isFalse);
      expect(SoqNetwork.mainnet.electrumApiUrl.contains('sim'), isFalse);
      expect(SoqNetwork.mainnet.electrumApiUrl, 'https://mainnet-api.soqu.org');
    });
  });

  group('Version drift', () {
    test('kAppVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([\d.]+)', multiLine: true)
          .firstMatch(pubspec)!;
      expect(kAppVersion, 'v${m.group(1)}');
    });
  });
}
