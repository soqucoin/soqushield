// Copyright (c) 2026 Soqucoin Labs Inc.
// Distributed under the MIT software license.
//
// utxo_asset_heal_test.dart — Regression tests for bead y60: gettxout emits
// all-lowercase `assettype` while the old refresh() read camelCase
// `assetType`, silently re-tagging every USDSOQ UTXO as SOQ. The corruption
// was sticky (merge paths preserve existing tags), so USDSOQ sends found no
// spendable coins and mis-tagged v7 coins were selected as SOQ inputs.
// Covers: refresh() field-name + script classification, evidence
// preservation, and the load()-time heal pass.

import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/models/utxo.dart';
import 'package:soqushield/services/rpc_service.dart';
import 'package:soqushield/services/utxo_service.dart';

/// Fake RPC that serves a canned gettxout response per outpoint.
class _FakeRpc extends RpcService {
  final Map<String, Map<String, dynamic>?> txouts = {};

  @override
  Future<Map<String, dynamic>?> getTxOut(String txid, int vout,
          {bool includeMempool = true}) async =>
      txouts['$txid:$vout'];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final v7Spk = '5720${'aa' * 32}'; // OP_7 PUSH_32 <32 bytes>
  final v1Spk = '5120${'bb' * 32}'; // OP_1 PUSH_32 <32 bytes>

  Utxo mkUtxo(String txid, String spk, AssetType asset) => Utxo(
        txid: txid,
        vout: 0,
        value: 1.0,
        valueSat: 100000000,
        scriptPubKey: spk,
        address: 'ssq1test',
        confirmations: 6,
        assetType: asset,
      );

  group('refresh() asset classification (bead y60)', () {
    test('lowercase assettype=1 from gettxout is honored', () async {
      final rpc = _FakeRpc();
      final svc = UtxoService(rpc);
      await svc.addUtxo(mkUtxo('a' * 64, v7Spk, AssetType.soq)); // corrupted
      rpc.txouts['${'a' * 64}:0'] = {
        'confirmations': 9,
        'value': 1.0,
        'assettype': 1, // node's real spelling
        'scriptPubKey': {'hex': v7Spk},
      };

      await svc.refresh();
      expect(svc.utxos.single.assetType, AssetType.usdsoq);
      expect(svc.utxos.single.confirmations, 9);
    });

    test('missing asset byte falls back to script-level v7 detection',
        () async {
      final rpc = _FakeRpc();
      final svc = UtxoService(rpc);
      await svc.addUtxo(mkUtxo('b' * 64, v7Spk, AssetType.soq)); // corrupted
      rpc.txouts['${'b' * 64}:0'] = {
        'confirmations': 3,
        'value': 1.0,
        // no assettype/assetType at all
        'scriptPubKey': {'hex': v7Spk},
      };

      await svc.refresh();
      expect(svc.utxos.single.assetType, AssetType.usdsoq);
    });

    test('no chain evidence preserves the local tag (never downgrades)',
        () async {
      final rpc = _FakeRpc();
      final svc = UtxoService(rpc);
      await svc.addUtxo(mkUtxo('c' * 64, '', AssetType.usdsoq));
      rpc.txouts['${'c' * 64}:0'] = {
        'confirmations': 2,
        'value': 1.0,
        // no asset byte, no scriptPubKey — zero evidence
      };

      await svc.refresh();
      expect(svc.utxos.single.assetType, AssetType.usdsoq);
    });

    test('v1 output with assettype=0 stays SOQ', () async {
      final rpc = _FakeRpc();
      final svc = UtxoService(rpc);
      await svc.addUtxo(mkUtxo('d' * 64, v1Spk, AssetType.soq));
      rpc.txouts['${'d' * 64}:0'] = {
        'confirmations': 5,
        'value': 1.0,
        'assettype': 0,
        'scriptPubKey': {'hex': v1Spk},
      };

      await svc.refresh();
      expect(svc.utxos.single.assetType, AssetType.soq);
    });
  });

  group('heal pass (bead y60)', () {
    test('v7 script tagged SOQ is healed to USDSOQ', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('e' * 64, v7Spk, AssetType.soq));

      await svc.debugHealAssetTags();
      expect(svc.utxos.single.assetType, AssetType.usdsoq);
    });

    test('v1 script tagged USDSOQ is healed to SOQ', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('f' * 64, v1Spk, AssetType.usdsoq));

      await svc.debugHealAssetTags();
      expect(svc.utxos.single.assetType, AssetType.soq);
    });

    test('empty/non-definitive script is left untouched', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('1' * 64, '', AssetType.usdsoq));
      final v5Spk = '5520${'cc' * 32}'; // authority marker — not a holding
      await svc.addUtxo(mkUtxo('2' * 64, v5Spk, AssetType.soq));

      await svc.debugHealAssetTags();
      expect(svc.utxos[0].assetType, AssetType.usdsoq);
      expect(svc.utxos[1].assetType, AssetType.soq);
    });

    test('healed USDSOQ becomes selectable for USDSOQ sends', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('3' * 64, v7Spk, AssetType.soq)); // corrupted

      expect(svc.selectUtxos(50000000, 0, assetType: AssetType.usdsoq),
          isNull); // the reported failure: balance visible, nothing spendable

      await svc.debugHealAssetTags();
      final selected =
          svc.selectUtxos(50000000, 0, assetType: AssetType.usdsoq);
      expect(selected, isNotNull);
      expect(selected!.single.assetType, AssetType.usdsoq);
    });
  });

  // Regression for bead usdsoq-send-post-swap-assettag: a freshly-minted v7
  // USDSOQ UTXO synced while the REST bridge still reported it as SOQ (asset
  // index lag) was cached SOQ and the old "preserve local tag" merge kept it
  // SOQ forever, so post-swap USDSOQ sends failed with "insufficient funds"
  // even though the balance displayed. syncFromRemote now reconciles toward the
  // authoritative remote tag (the bridge classifies by scripthash), so a stuck
  // wallet self-heals on its next sync.
  group('syncFromRemote asset reconciliation (post-swap)', () {
    test('stale local SOQ tag is corrected to USDSOQ from remote', () async {
      final svc = UtxoService(_FakeRpc());
      // Wallet cached the mint output as SOQ during the bridge lag window,
      // with the (wrong) v1 script the app fabricates for a SOQ tag.
      await svc.addUtxo(mkUtxo('a' * 64, v1Spk, AssetType.soq));

      // Next sync: the bridge now classifies it correctly as USDSOQ (v7).
      await svc.syncFromRemote([mkUtxo('a' * 64, v7Spk, AssetType.usdsoq)]);

      expect(svc.utxos.single.assetType, AssetType.usdsoq);
      expect(svc.utxos.single.scriptPubKey, v7Spk); // script corrected too
    });

    test('corrected UTXO becomes selectable for a USDSOQ send', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('b' * 64, v1Spk, AssetType.soq));
      expect(svc.selectUtxos(50000000, 0, assetType: AssetType.usdsoq),
          isNull); // the reported post-swap failure

      await svc.syncFromRemote([mkUtxo('b' * 64, v7Spk, AssetType.usdsoq)]);

      final selected =
          svc.selectUtxos(50000000, 0, assetType: AssetType.usdsoq);
      expect(selected, isNotNull);
      expect(selected!.single.assetType, AssetType.usdsoq);
    });

    test('a genuine SOQ UTXO is untouched by sync', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('c' * 64, v1Spk, AssetType.soq));

      await svc.syncFromRemote([mkUtxo('c' * 64, v1Spk, AssetType.soq)]);

      expect(svc.utxos.single.assetType, AssetType.soq);
    });

    test('spent UTXO absent from remote is pruned', () async {
      final svc = UtxoService(_FakeRpc());
      await svc.addUtxo(mkUtxo('d' * 64, v7Spk, AssetType.usdsoq));

      await svc.syncFromRemote([]); // no longer in the remote set

      expect(svc.utxos, isEmpty);
    });
  });
}
