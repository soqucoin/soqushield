// The Network screen and what feeds it: the emission schedule against the
// node's constants, the chain and pool readers against the shapes the live
// endpoints return (captured 2026-10-06), the formatters, and the screen in
// its three states (Stagenet live, Mainnet before launch, Mainnet live) on
// the large and the small surface.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/main.dart' show kMaxTextScale;
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/launch_state_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/network/network_screen.dart';
import 'package:soqushield/services/emission.dart';
import 'package:soqushield/services/rpc_service.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/block_clock_figure.dart';

import 'lite_test_support.dart';

/// Records every host the app opens a request to and refuses the request.
class _RecordingHttpClient implements HttpClient {
  final List<Uri> urls;
  _RecordingHttpClient(this.urls);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    urls.add(url);
    throw const SocketException('no network in tests');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingOverrides extends HttpOverrides {
  final List<Uri> urls = [];
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(urls);
}

const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';
const _large = Size(430, 932);
const _small = Size(375, 667);

// The live shapes, trimmed. A finder is present in the pool's rows as it is
// live, and must never reach the model.
const _miningInfo = {
  'blocks': 112105,
  'currentblocksize': 1000,
  'difficulty': 407.8413068844807,
  'errors': '',
  'networkhashps': 20398783697.58386,
  'pooledtx': 3,
  'chain': 'stagenet',
};
const _tipHash = 'cd4c273094b0bdf13f330a5452fa5c290c4e4d3998c02859de08b8a03206a910';
const _tipBlock = {
  'hash': _tipHash,
  'height': 112105,
  'time': 1791257700,
  'mediantime': 1791257598,
  'difficulty': 407.8413068844807,
  'tx': ['aa'],
};
const _poolIndex = {
  'ActiveMiners': 5,
  'BlocksPerHour': 52,
  // One feed for every chain the pool mines: a Dogecoin row sits between the
  // Soqucoin rows live, and a row naming no chain is not this chain's.
  'LatestBlocks': [
    {'chain': 'Soqucoin', 'blockHeight': 112127, 'finder': 'someone', 'effort': 0, 'reward': 0, 'created': '2026-10-06 04:08:09.059411 +0000 UTC', 'minutesAgo': 1},
    {'chain': 'Dogecoin', 'blockHeight': 5985771, 'finder': 'someone', 'effort': 0, 'reward': 0, 'created': '2026-10-06 04:07:40.000000 +0000 UTC', 'minutesAgo': 1},
    {'chain': 'Soqucoin', 'blockHeight': 112126, 'finder': 'someone', 'effort': 0, 'reward': 0, 'created': '2026-10-06 04:07:18.301183 +0000 UTC', 'minutesAgo': 2},
    {'blockHeight': 112125, 'finder': 'someone', 'effort': 0, 'reward': 0, 'minutesAgo': 3},
    {'chain': 'Soqucoin', 'blockHeight': 112121, 'finder': 'someone', 'effort': 5.9e-7, 'reward': 100000, 'minutesAgo': 9},
  ],
  'NetworkDifficulty': 97030382.37515819,
  'NetworkHashrate': {'Rate': '6.95', 'Denomination': 'PH/s', 'Raw': 6945705316994654},
  'PoolHashRate': {'Rate': '20.51', 'Denomination': 'GH/s', 'Raw': 20512397503},
  'TotalBlocks': 99554,
  'Workers': 7,
};
const _poolLuck = {
  'currentRound': {'sharesSinceLastBlock': 76.2, 'expectedShares': 229.5, 'effortPct': 33.18, 'durationMinutes': 1},
  'luck24h': 99.40773836252089,
  'luck7d': 97.9957751222312,
  'blocksLast24h': 1324,
  'blocksLast7d': 9488,
};
const _poolStatus = {
  'chains': [{'chain': 'soqucoin', 'feed': 'live'}],
  'events': [],
  'nodes': [
    {'region': 'US-West', 'status': 'up', 'workers': 11},
    {'region': 'EU', 'status': 'up', 'workers': 0},
    {'region': 'Asia', 'status': 'down', 'workers': 0},
  ],
  'overall': 'operational',
  'payouts': {'hours_utc': [0, 4, 8, 12, 16, 20], 'next_eta': '3h 51m (next cycle 08:00 UTC)'},
};
const _poolTerms = {'scheme': 'PPLNS', 'fee_rate': 0.015, 'post_mainnet_fee_rate': 0.0169};

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

/// A proxy answering the three chain calls; [down] answers nothing.
MockClient _rpc({bool down = false}) => MockClient((req) async {
      if (down) throw Exception('no route');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final result = switch (body['method']) {
        'getmininginfo' => _miningInfo,
        'getnetworkinfo' => {'version': 2050000, 'connections': 10},
        'getbestblockhash' => _tipHash,
        'getblock' => _tipBlock,
        _ => null,
      };
      if (result == null) {
        return _ok({'result': null, 'error': {'code': -32601, 'message': 'no'}, 'id': 1});
      }
      return _ok({'result': result, 'error': null, 'id': 1});
    });

/// The pool's four endpoints; [failing] answer 500.
MockClient _poolApi({Set<String> failing = const {}}) => MockClient((req) async {
      final p = req.url.path;
      if (failing.contains(p)) return http.Response('down', 500);
      return switch (p) {
        '/pool' => _ok(_poolIndex),
        '/pool/luck' => _ok(_poolLuck),
        '/pool/status' => _ok(_poolStatus),
        '/pool/terms' => _ok(_poolTerms),
        _ => http.Response('not found', 404),
      };
    });

WalletState _wallet(SoqNetwork network) => WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: network == SoqNetwork.mainnet ? _mainnetAddress : _stagenetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: network,
      backupConfirmed: true,
      isInitialized: true,
    );

class _SeenLive extends MainnetSeenLiveNotifier {
  final bool seen;
  _SeenLive(this.seen);
  @override
  bool build() => seen;
}

Widget _screen(SoqNetwork network,
        {required ChainWeather chain, PoolWeather? pool, bool seenLive = false}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet(network))),
        mainnetSeenLiveProvider.overrideWith(() => _SeenLive(seenLive)),
        chainWeatherProvider.overrideWith((ref) => Stream.value(chain)),
        poolWeatherProvider.overrideWith((ref) => pool == null
            ? const Stream<PoolWeather>.empty()
            : Stream.value(pool)),
      ],
      child: const MaterialApp(home: NetworkPilotScreen()),
    );

void _surface(WidgetTester tester, Size logical) {
  tester.view.physicalSize = logical * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the emission schedule (soqucoin main c6b7824c1)', () {
    test('pays 100,000 SOQ for the first 250,000 blocks, halves three times '
        'and settles on the 2,500 SOQ tail at block 1,000,000', () {
      expect(Emission.subsidyAt(0), 100000);
      expect(Emission.subsidyAt(249999), 100000);
      expect(Emission.subsidyAt(250000), 50000);
      expect(Emission.subsidyAt(499999), 50000);
      expect(Emission.subsidyAt(500000), 25000);
      expect(Emission.subsidyAt(750000), 12500);
      expect(Emission.subsidyAt(999999), 12500);
      expect(Emission.subsidyAt(1000000), 2500);
      expect(Emission.subsidyAt(50000000), 2500);
    });

    test('names the next change and the time to it at 60-second blocks', () {
      expect(Emission.nextChangeAfter(0), 250000);
      expect(Emission.nextChangeAfter(112127), 250000);
      expect(Emission.nextChangeAfter(250000), 500000);
      expect(Emission.nextChangeAfter(999999), 1000000);
      expect(Emission.nextChangeAfter(1000000), isNull);
      expect(Emission.timeBetween(112127, 250000), const Duration(minutes: 137873));
      expect(fmtEta(Emission.timeBetween(112127, 250000)), '~95 D');
    });
  });

  group('the chain reader', () {
    test('reads the tip, its time, the difficulty, the hashrate and the mempool',
        () async {
      final w = await fetchChainWeather(SoqNetwork.stagenet,
          rpc: RpcService(client: _rpc(), network: SoqNetwork.stagenet));
      expect(w.reachable, isTrue);
      expect(w.height, 112105);
      expect(w.tipTime, DateTime.fromMillisecondsSinceEpoch(1791257700 * 1000, isUtc: true));
      expect(w.difficulty, closeTo(407.84, 0.01));
      expect(w.hashrate, closeTo(20398783697.58, 0.01));
      expect(w.mempoolTx, 3);
      expect(w.peers, 10);
      final later = w.tipTime!.add(const Duration(seconds: 42));
      expect(w.sinceTip(later), const Duration(seconds: 42));
      expect(w.sinceTip(w.tipTime!.subtract(const Duration(seconds: 5))), Duration.zero,
          reason: 'a tip ahead of the clock reads zero, never negative');
    });

    test('a node that does not answer is unreachable with zero fields', () async {
      final w = await fetchChainWeather(SoqNetwork.mainnet,
          rpc: RpcService(client: _rpc(down: true), network: SoqNetwork.mainnet));
      expect(w.reachable, isFalse);
      expect(w.height, 0);
      expect(w.tipTime, isNull);
    });

    test('the height is the fetched tip\'s when a block lands between the '
        'mining summary and the tip, and the summary\'s count otherwise', () async {
      MockClient proxy(Map<String, dynamic> tip) => MockClient((req) async {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final result = switch (body['method']) {
              'getmininginfo' => _miningInfo,
              'getnetworkinfo' => {'connections': 10},
              'getbestblockhash' => _tipHash,
              'getblock' => tip,
              _ => null,
            };
            return _ok({'result': result, 'error': null, 'id': 1});
          });
      // The summary counted 112105 blocks; the tip fetched after it is 112106.
      final raced = await fetchChainWeather(SoqNetwork.stagenet,
          rpc: RpcService(
              client: proxy({..._tipBlock, 'height': 112106, 'time': 1791257760}),
              network: SoqNetwork.stagenet));
      expect(raced.height, 112106, reason: 'the height the tip time belongs to');
      expect(raced.tipTime,
          DateTime.fromMillisecondsSinceEpoch(1791257760 * 1000, isUtc: true));
      final noHeight = await fetchChainWeather(SoqNetwork.stagenet,
          rpc: RpcService(
              client: proxy({'hash': _tipHash, 'time': 1791257700}),
              network: SoqNetwork.stagenet));
      expect(noHeight.height, 112105, reason: 'the summary is the fallback');
    });
  });

  group('the pool reader', () {
    test('reads the public figures and never the finder of a block', () async {
      final p = await fetchPoolWeather(client: _poolApi());
      expect(p.reachable, isTrue);
      expect(p.poolHashrate, 20512397503);
      expect(p.activeMiners, 5);
      expect(p.workers, 7);
      expect(p.blocksPerHour, 52);
      expect(p.blocks24h, 1324);
      expect(p.blocks7d, 9488);
      expect(p.luck24h, closeTo(99.41, 0.01));
      expect(p.luck7d, closeTo(98.0, 0.01));
      expect(p.roundEffortPct, closeTo(33.18, 0.01));
      expect(p.overall, 'operational');
      expect(p.regions.map((r) => r.region), ['US-West', 'EU', 'Asia']);
      expect(p.regions.where((r) => r.up).length, 2);
      expect(p.nextPayoutEta, '3h 51m (next cycle 08:00 UTC)');
      expect(p.feeRate, 0.015);
      expect(p.scheme, 'PPLNS');
      expect(p.latestBlocks.map((b) => b.height), [112127, 112126, 112121],
          reason: 'the Dogecoin row and the row naming no chain are not this '
              'chain\'s blocks');
      expect(p.latestBlocks.map((b) => b.height), isNot(contains(5985771)));
      expect(p.latestBlocks.map((b) => b.height), isNot(contains(112125)));
      expect(p.latestBlocks[0].time, DateTime.utc(2026, 10, 6, 4, 8, 9));
      expect(p.latestBlocks[2].time.isBefore(p.fetchedAt), isTrue,
          reason: 'a row without a created time falls back to minutesAgo');
      // The reader names the finder nowhere: not as a key it reads, not as a
      // field it keeps.
      final reader = File('lib/services/weather_service.dart').readAsStringSync();
      expect(reader, isNot(contains("['finder']")));
      expect(reader, isNot(contains("'finder'")));
    });

    test('one endpoint down leaves its fields null and the rest read', () async {
      final p = await fetchPoolWeather(client: _poolApi(failing: {'/pool/luck'}));
      expect(p.reachable, isTrue);
      expect(p.luck24h, isNull);
      expect(p.blocks24h, isNull);
      expect(p.activeMiners, 5);
    });

    test('every endpoint down is unreachable', () async {
      final p = await fetchPoolWeather(
          client: _poolApi(failing: {'/pool', '/pool/luck', '/pool/status', '/pool/terms'}));
      expect(p.reachable, isFalse);
    });

    test('talks to the pool API host only', () {
      expect(kPoolApiHost, 'api.soqupool.com');
    });

    test('a wrong-typed string field, an infinite number or an absurd age '
        'reads as absent, and the pool still reads as answering', () async {
      // Written as text: a JSON encoder will not emit an infinite number,
      // a hostile host can.
      final hostile = MockClient((req) async => switch (req.url.path) {
            '/pool' => http.Response(
                '{"ActiveMiners": 1e400, "Workers": 7, "BlocksPerHour": 52, '
                '"PoolHashRate": {"Raw": 20512397503}, '
                '"LatestBlocks": [{"chain": "Soqucoin", "blockHeight": 112127, "minutesAgo": 1e15}, '
                '{"chain": "Soqucoin", "blockHeight": 112126, "minutesAgo": 3}]}',
                200),
            '/pool/luck' => http.Response(
                '{"luck24h": 1e400, "luck7d": 97.99, "blocksLast24h": 1324}', 200),
            '/pool/status' => _ok({
                ...Map<String, dynamic>.from(_poolStatus),
                'overall': 7,
                'payouts': {'next_eta': ['soon']},
              }),
            '/pool/terms' => _ok({'scheme': 42, 'fee_rate': 0.015}),
            _ => http.Response('not found', 404),
          });
      final p = await fetchPoolWeather(client: hostile);
      expect(p.reachable, isTrue);
      expect(p.activeMiners, isNull);
      expect(p.luck24h, isNull);
      expect(p.overall, isNull);
      expect(p.nextPayoutEta, isNull);
      expect(p.scheme, isNull);
      expect(p.feeRate, 0.015);
      expect(p.latestBlocks.map((b) => b.height), [112126],
          reason: 'a row whose age cannot be a recent block is dropped');
    });

    test('unknown shapes read as absent fields, with the pool answering', () async {
      final broken = MockClient((req) async => _ok({
            'ActiveMiners': 5,
            'LatestBlocks': 'x',
            'PoolHashRate': 3,
            'nodes': 5,
            'currentRound': 'none',
            'payouts': 'later',
          }));
      final p = await fetchPoolWeather(client: broken);
      expect(p.reachable, isTrue, reason: 'unknown shapes are absent fields');
      expect(p.poolHashrate, isNull);
      expect(p.regions, isEmpty);
      expect(p.latestBlocks, isEmpty);
    });

    test('every field takes every JSON shape without a throw', () async {
      // Each pool field, given each shape JSON can carry; the reader must
      // absorb them all (the catch round the parse is a backstop no known
      // shape reaches).
      final shapes = <Object?>[null, true, 0, -1, 1.5, 'x', [], [1, 'a'], {}, {'a': 1}];
      const fields = [
        'ActiveMiners', 'Workers', 'BlocksPerHour', 'PoolHashRate', 'LatestBlocks',
        'luck24h', 'luck7d', 'blocksLast24h', 'blocksLast7d', 'currentRound',
        'overall', 'nodes', 'payouts', 'fee_rate', 'scheme',
      ];
      for (final shape in shapes) {
        final body = {for (final f in fields) f: shape};
        final c = MockClient((req) async => _ok(body));
        final p = await fetchPoolWeather(client: c);
        expect(p.reachable, isTrue, reason: 'shape $shape answered');
      }
      // Rows of every shape inside the lists.
      final rows = MockClient((req) async => _ok({
            'LatestBlocks': [...shapes, {'blockHeight': 'x'}, {'blockHeight': 5, 'created': 7}],
            'nodes': [...shapes, {'region': 3}, {'region': 'EU', 'status': 9, 'workers': 'z'}],
          }));
      final p = await fetchPoolWeather(client: rows);
      expect(p.latestBlocks, isEmpty);
      expect(p.regions.map((r) => r.region), ['EU']);
    });

    test('a chain answer with a negative height or a tip without a time reads '
        'safely', () async {
      final odd = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        // The mining summary is written as text to carry an infinite number.
        if (body['method'] == 'getmininginfo') {
          return http.Response(
              '{"result": {"blocks": -300000, "difficulty": 407.8, '
              '"networkhashps": 1e400, "pooledtx": 3}, "error": null, "id": 1}',
              200);
        }
        final result = switch (body['method']) {
          'getnetworkinfo' => {'connections': 10},
          'getbestblockhash' => _tipHash,
          'getblock' => {..._tipBlock, 'height': -300000, 'time': 'now'},
          _ => null,
        };
        return _ok({'result': result, 'error': null, 'id': 1});
      });
      final w = await fetchChainWeather(SoqNetwork.stagenet,
          rpc: RpcService(client: odd, network: SoqNetwork.stagenet));
      expect(w.reachable, isTrue);
      expect(w.height, 0, reason: 'no block before genesis, from the tip or the summary');
      expect(w.hashrate, 0, reason: 'a non-finite figure is absent');
      expect(w.tipTime, isNull);
      expect(fmtHashrate(double.infinity), '—');
      expect(fmtDifficulty(double.nan), '—');
      expect(Emission.subsidyAt(-250000), 100000);
      expect(Emission.nextChangeAfter(-1), 250000);
    });
  });

  group('the formatters', () {
    test('hashrate', () {
      expect(fmtHashrate(20398783697.58), '20.4 GH/s');
      expect(fmtHashrate(6945705316994654), '6.95 PH/s');
      expect(fmtHashrate(850), '850 H/s');
      expect(fmtHashrate(1500), '1.50 kH/s');
    });
    test('difficulty', () {
      expect(fmtDifficulty(407.8413), '407.8');
      expect(fmtDifficulty(97030382.4), '97.0M');
      expect(fmtDifficulty(12345), '12.3k');
    });
    test('the clock and the spans', () {
      expect(fmtClock(const Duration(seconds: 42)), '0:42');
      expect(fmtClock(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(fmtClock(const Duration(hours: 1, minutes: 2, seconds: 33)), '1:02:33');
      expect(fmtEta(const Duration(days: 96, hours: 5)), '~96 D');
      expect(fmtEta(const Duration(hours: 5)), '~5 H');
      expect(fmtEta(const Duration(minutes: 12)), '~12 MIN');
      expect(fmtAgo(const Duration(seconds: 20)), 'JUST NOW');
      expect(fmtAgo(const Duration(minutes: 9)), '9 MIN AGO');
      expect(fmtAgo(const Duration(hours: 3)), '3 HR AGO');
    });
    test('the clock time of a block, in UTC whatever the phone\'s zone', () {
      expect(fmtUtcTime(DateTime.utc(2026, 10, 6, 7, 2, 16)), '07:02:16 UTC');
      expect(fmtUtcTime(DateTime.utc(2026, 10, 6, 7, 2, 16).toLocal()), '07:02:16 UTC');
    });
    test('the spoken time since the last block holds still within a minute', () {
      expect(fmtSpokenSince(const Duration(seconds: 42)), 'under a minute');
      expect(fmtSpokenSince(const Duration(seconds: 59)), 'under a minute');
      expect(fmtSpokenSince(const Duration(minutes: 1, seconds: 30)), '1 minute');
      expect(fmtSpokenSince(const Duration(minutes: 12, seconds: 5)), '12 minutes');
      expect(fmtSpokenSince(const Duration(hours: 1)), '1 hour');
      expect(fmtSpokenSince(const Duration(hours: 2, minutes: 1)), '2 hours 1 minute');
    });
  });

  group('the launch flag', () {
    test('preloaded preferences give the stored value at the first read, '
        'before any frame', () async {
      SharedPreferences.setMockInitialValues({MainnetSeenLiveNotifier.key: true});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
          overrides: [preloadedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      expect(container.read(mainnetSeenLiveProvider), isTrue,
          reason: 'an install that has seen Mainnet live opens on the '
              'reconnecting line, never the pre-launch one');
    });

    test('without a preload the flag reads false until the preferences '
        'load (the window the preload closes)', () async {
      SharedPreferences.setMockInitialValues({MainnetSeenLiveNotifier.key: true});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(mainnetSeenLiveProvider), isFalse);
      for (var i = 0; i < 50 && !container.read(mainnetSeenLiveProvider); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(mainnetSeenLiveProvider), isTrue);
    });

    test('the entry point loads the preferences before the first frame and '
        'hands them to the scope', () {
      final entry = File('lib/main.dart').readAsStringSync();
      expect(entry, contains('preloadedPreferencesProvider.overrideWithValue(prefs)'));
      expect(entry.indexOf('await SharedPreferences.getInstance()'),
          allOf(greaterThan(0), lessThan(entry.lastIndexOf('runApp('))));
    });
  });

  group('the polls', () {
    late _RecordingOverrides overrides;
    setUp(() {
      installSecureStorageMock();
      SharedPreferences.setMockInitialValues({});
      overrides = _RecordingOverrides();
      HttpOverrides.global = overrides;
    });
    tearDown(() => HttpOverrides.global = null);

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('the chain poll is kept across watchers: a returning watcher reads the '
        'last figure without a new request until the next tick', () async {
      final container = ProviderContainer(overrides: [
        walletProvider.overrideWith(
            () => MockWalletNotifier(_wallet(SoqNetwork.stagenet))),
      ]);
      addTearDown(container.dispose);
      var sub = container.listen(chainWeatherProvider, (_, _) {});
      await until(() => overrides.urls.isNotEmpty);
      expect(overrides.urls, isNotEmpty, reason: 'the first poll ran');
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = overrides.urls.length;
      sub = container.listen(chainWeatherProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(overrides.urls.length, before,
          reason: 'no reload on a return; the home keeps its figures');
      expect(container.read(chainWeatherProvider).hasValue, isTrue);
      sub.close();
    });

    test('a returning watcher gets a fresh pool poll at once', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var sub = container.listen(poolWeatherProvider, (_, _) {});
      await until(() => overrides.urls.isNotEmpty);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = overrides.urls.length;
      sub = container.listen(poolWeatherProvider, (_, _) {});
      await until(() => overrides.urls.length > before);
      expect(overrides.urls.length, greaterThan(before));
      sub.close();
    });
  });

  group('the Network screen', () {
    setUp(() {
      installSecureStorageMock();
      SharedPreferences.setMockInitialValues({});
    });

    final liveChain = ChainWeather(
      reachable: true,
      height: 112105,
      tipTime: DateTime.now().subtract(const Duration(seconds: 42)),
      difficulty: 407.84,
      hashrate: 20398783697.58,
      mempoolTx: 3,
      peers: 10,
      fetchedAt: DateTime.now(),
    );
    final offline = ChainWeather.unreachable(DateTime.now());
    Future<PoolWeather> livePool() => fetchPoolWeather(client: _poolApi());

    for (final size in [_large, _small]) {
      testWidgets('Stagenet live reads the chain, the schedule and the pool '
          'on ${size.width.toInt()} wide', (tester) async {
        _surface(tester, size);
        await tester.pumpWidget(_screen(SoqNetwork.stagenet,
            chain: liveChain, pool: await livePool()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('SOQUCOIN · ML-DSA-44 · LIVE'), findsOneWidget);
        expect(find.text('CHAIN · STAGENET'), findsOneWidget);
        // The weather in words, then the cards: closed at first, with their
        // one-line summaries; the grids wait for a tap.
        expect(find.textContaining('Blocks are arriving on time.'), findsOneWidget);
        expect(find.textContaining('SOQUPOOL is operational with 5 miners.'),
            findsOneWidget);
        expect(find.text('LAST BLOCK ${fmtUtcTime(liveChain.tipTime!)}'),
            findsOneWidget, reason: 'the chain card\'s line');
        expect(find.text('HEIGHT'), findsNothing, reason: 'closed at first');
        final list = find.byType(Scrollable).first;
        await tester.tap(find.byKey(const ValueKey('card chain')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('card emission')), 120,
            scrollable: list);
        await tester.tap(find.byKey(const ValueKey('card emission')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(find.text('HEIGHT'), -120,
            scrollable: list);
        await tester.pump();
        // The clock's figures stand as text too, at the system size.
        expect(find.text('HEIGHT'), findsOneWidget);
        expect(find.text('112,105'), findsOneWidget);
        expect(find.text('LAST BLOCK'), findsOneWidget);
        expect(find.text(fmtUtcTime(liveChain.tipTime!)), findsOneWidget);
        expect(find.text('TARGET SPACING 60 S'), findsOneWidget);
        expect(find.text('20.4 GH/s'), findsWidgets);
        expect(find.text('407.8'), findsOneWidget);
        expect(find.text('3 TX'), findsOneWidget);
        expect(find.text('PEERS'), findsOneWidget);
        expect(find.text('10'), findsOneWidget, reason: 'the peer count');
        await tester.scrollUntilVisible(find.text('100,000 SOQ'), 120,
            scrollable: list);
        await tester.pump();
        expect(find.text('100,000 SOQ'), findsOneWidget);
        expect(find.text('50,000 SOQ'), findsOneWidget);
        expect(find.text('UNTIL BLOCK 250,000'), findsOneWidget);
        // The pool card sits below the fold on the small surface and the
        // list builds lazily: bring each part into view before reading it.
        await tester.scrollUntilVisible(find.text('OPERATIONAL'), 120, scrollable: list);
        await tester.pump();
        expect(find.text('SOQUPOOL'), findsOneWidget);
        expect(find.text('OPERATIONAL'), findsOneWidget);
        expect(find.textContaining('5 MINERS · 52 BLOCKS / HR'), findsOneWidget,
            reason: 'the pool card\'s line, closed');
        await tester.tap(find.byKey(const ValueKey('card pool')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(find.text('3h 51m'), 120, scrollable: list);
        await tester.pump();
        expect(find.text('1,324'), findsOneWidget);
        expect(find.text('1.50%'), findsOneWidget);
        expect(find.text('3h 51m'), findsOneWidget);
        expect(find.text('2 OF 3 UP'), findsOneWidget);
        expect(find.text('US-WEST · EU · ASIA DOWN'), findsOneWidget,
            reason: 'the region that is down is named');
        await tester.scrollUntilVisible(
            find.textContaining('reads only what the pool publishes'), 120,
            scrollable: list);
        await tester.pump();
        expect(find.textContaining('reads only what the pool publishes'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('112,127'), 120, scrollable: list);
        await tester.pump();
        expect(find.text('LATEST BLOCKS'), findsOneWidget);
        expect(find.text('112,127'), findsOneWidget);
        expect(find.text('someone'), findsNothing, reason: 'no finder on screen');
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('the painted clock is spoken as one label, to the minute, '
        'with the height and the hashrate', (tester) async {
      // Disposed at the end of the body: the test's own end-of-test check
      // runs before a tear-down would.
      final semantics = tester.ensureSemantics();
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.stagenet,
          chain: liveChain, pool: await livePool()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.bySemanticsLabel('Under a minute since the last block. '
              'Block 112,105. Network hashrate 20.4 GH/s.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pool: await livePool()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Block clock offline.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });

    testWidgets('Mainnet before launch waits: the clock is offline, the '
        'schedule reads from genesis and the pool section waits', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pool: await livePool()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsOneWidget);
      expect(find.textContaining('Mainnet opens at launch'), findsOneWidget);
      expect(find.byKey(const ValueKey('weather line')), findsNothing,
          reason: 'nothing was read, so no sentence under the clock');
      expect(find.text('100,000 SOQ A BLOCK AT GENESIS'), findsOneWidget,
          reason: 'the emission card\'s line, closed');
      expect(find.text('OPENS AT MAINNET LAUNCH'), findsOneWidget,
          reason: 'the pool card\'s line, closed');
      await tester.tap(find.byKey(const ValueKey('card emission')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BLOCK REWARD · GENESIS'), findsOneWidget);
      expect(find.text('100,000 SOQ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('card pool')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('figures appear here when Mainnet opens'), findsOneWidget);
      expect(find.text('OPERATIONAL'), findsNothing,
          reason: 'the pool reports on the chain it mines, not yet this one');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Mainnet after launch, unreachable, says it is reconnecting',
        (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pool: await livePool(), seenLive: true));
      await tester.pump();
      expect(find.text('Reconnecting to the network.'), findsOneWidget);
      expect(find.textContaining('Mainnet opens at launch'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Mainnet live shows the pool', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: liveChain, pool: await livePool(), seenLive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CHAIN · MAINNET'), findsOneWidget);
      expect(find.text('OPERATIONAL'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a chain figure older than the poll period shows no clock',
        (tester) async {
      _surface(tester, _large);
      final stale = ChainWeather(
        reachable: true,
        height: 112105,
        tipTime: DateTime.now().subtract(const Duration(minutes: 5)),
        difficulty: 407.84,
        hashrate: 20398783697.58,
        mempoolTx: 3,
        peers: 10,
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await tester.pumpWidget(_screen(SoqNetwork.stagenet, chain: stale));
      await tester.pump();
      final painter = tester
          .widget<CustomPaint>(find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is BlockClockPainter))
          .painter as BlockClockPainter;
      expect(painter.centreValue, '—',
          reason: 'a five-minute-old figure is not a stalled chain');
      expect(painter.leftValue, 'BLOCK 112,105',
          reason: 'the figures themselves still read');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('hostile figures never break the build: an infinite luck, a '
        'non-finite effort, a tip without a time', (tester) async {
      _surface(tester, _large);
      final odd = PoolWeather(
        reachable: true,
        luck24h: double.infinity,
        luck7d: double.nan,
        roundEffortPct: double.nan,
        overall: 'operational',
        fetchedAt: DateTime.now(),
      );
      final noTip = ChainWeather(
        reachable: true,
        height: 112105,
        tipTime: null,
        difficulty: 407.84,
        hashrate: 20398783697.58,
        mempoolTx: 3,
        peers: 10,
        fetchedAt: DateTime.now(),
      );
      await tester.pumpWidget(_screen(SoqNetwork.stagenet, chain: noTip, pool: odd));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // The hostile figures sit in the grids: open every card to build them.
      for (final id in ['chain', 'emission', 'pool']) {
        await tester.tap(find.byKey(ValueKey('card $id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('LUCK · 24 H'), findsOneWidget, reason: 'the grid built');
      expect(find.text('—'), findsWidgets, reason: 'absent figures read as dashes');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the waiting line fits its slot at the text-scale limit',
        (tester) async {
      _surface(tester, _small);
      tester.platformDispatcher.textScaleFactorTestValue = kMaxTextScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet, chain: offline));
      await tester.pump();
      final line = find.textContaining('Mainnet opens at launch');
      expect(line, findsOneWidget);
      final para = tester.renderObject<RenderParagraph>(line);
      expect(para.textSize.height, lessThanOrEqualTo(para.size.height + 0.5),
          reason: 'the slot grows for the wrapped line instead of clipping it');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final size in const [_small, Size(360, 640)]) {
    testWidgets('Stagenet live fits the small surface at the text-scale limit '
        'on ${size.width.toInt()} by ${size.height.toInt()}',
        (tester) async {
      _surface(tester, size);
      tester.platformDispatcher.textScaleFactorTestValue = kMaxTextScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_screen(SoqNetwork.stagenet,
          chain: liveChain, pool: await livePool()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('OPERATIONAL'), 120, scrollable: list);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'nothing overflows at the limit');
      // Every card open as well.
      for (final id in ['chain', 'emission', 'pool']) {
        await tester.scrollUntilVisible(find.byKey(ValueKey('card $id')), 120,
            scrollable: list);
        await tester.tap(find.byKey(ValueKey('card $id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.scrollUntilVisible(find.text('LATEST BLOCKS'), 120,
          scrollable: list);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'nothing overflows at the limit with every card open');
      await tester.pumpWidget(const SizedBox.shrink());
    });
    }

    testWidgets('the home\'s network row reads SYNCING, never OFFLINE, while '
        'the chain poll loads', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
          authServiceProvider.overrideWithValue(FakeAuthService()),
          sessionProvider.overrideWith(MockSessionNotifier.new),
          walletProvider.overrideWith(
              () => MockWalletNotifier(_wallet(SoqNetwork.stagenet))),
          mainnetSeenLiveProvider.overrideWith(() => _SeenLive(false)),
          // A poll that has not answered yet: the derived status line reads
          // SYNCING, and so must the row.
          chainWeatherProvider.overrideWith(
              (ref) => const Stream<ChainWeather>.empty()),
        ],
        child: const MaterialApp(home: HomePilotScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SOQUCOIN · ML-DSA-44 · SYNCING'), findsOneWidget);
      expect(find.text('SYNCING'), findsOneWidget, reason: 'the row');
      expect(find.text('OFFLINE'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Stagenet on an install that has seen Mainnet live shows no '
        'pool (the pool has moved on)', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.stagenet,
          chain: liveChain, pool: await livePool(), seenLive: true));
      await tester.pump();
      expect(find.text('OPERATIONAL'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

