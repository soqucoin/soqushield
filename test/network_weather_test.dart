// The Network screen and what feeds it: the emission schedule against the
// node's constants, the chain reader against the shapes the live node
// returns (captured 2026-10-06) and the pools reader against the explorer's
// (captured 2026-11-27), the formatters, and the screen in its three states
// (Stagenet live, Mainnet not yet answered, Mainnet live) on the large and
// the small surface.

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
// The explorer's shapes, trimmed (captured 2026-11-27): the tip as text, and
// the mining summary over the day of blocks ending at it. The explorer names
// a pool whose payout address it knows and groups the rest by that address.
// A link is present as it is live, and must never reach the model.
const _tip = 65897;
const _f2 = 'sq1pyvjd6up35lqtm0mjxu5khj6a69y8wdas657nyxphtc4343u5ymnsgmgyul';
const _lp = 'sq1psjvu5zemy90t56ms25ql6vnpdawt9pga4lpvkr8gaapysukrxhgszyfc2n';
const _nine = 'sq1pu43lfdnte6tmfwzhvy8y8j8ga0xghd9j9hhaazczrl2ellfynqtsv270c8';
const _okm = 'sq1p8k44sc8da0mn0uz23ghpsd9psu9fy7yzedphxjjr87l2ztlguttqu3rxdx';
List<int> _heights(int count) =>
    [for (var i = 0; i < count; i++) _tip - 1400 + i * 7];
Map<String, dynamic> _group(String name, int blocks,
        {Map<String, dynamic>? details}) =>
    {
      'name': name,
      'details': details,
      'blocks': _heights(blocks),
      'totalFees': '0.04206',
      'totalSubsidy': '${blocks * 100000}',
      'totalTransactions': blocks + 8,
      'totalWeight': blocks * 4300,
      'subsidyCount': blocks,
    };
Map<String, dynamic> _summary() => {
      'miners': {
        'F2Pool': _group('F2Pool', 104, details: {
          'name': 'F2Pool',
          'link': 'https://www.f2pool.com',
          'identifiedBy': 'payout address $_f2',
        }),
        'address-only:$_lp': _group('address-only:$_lp', 16, details: {
          'name': _lp,
          'type': 'address-only',
          'identifiedBy': 'payout address $_lp',
        }),
        'LuxxPool': _group('LuxxPool', 13),
        'address-only:$_nine': _group('address-only:$_nine', 7),
        'Mining-Dutch': _group('Mining-Dutch', 4),
        'address-only:$_okm': _group('address-only:$_okm', 1),
      },
      'minerNamesSortedByBlockCount': [
        'F2Pool', 'address-only:$_lp', 'LuxxPool', 'address-only:$_nine',
        'Mining-Dutch', 'address-only:$_okm',
      ],
      'overall': {
        'blockCount': 145, 'totalFees': '0.096456', 'totalSubsidy': '14500000',
        'totalTransactions': 154, 'totalWeight': 637752, 'subsidyCount': 145,
      },
    };

/// A JSON answer as the live hosts send one: UTF-8, labelled as such.
http.Response _ok(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

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

/// The explorer's two endpoints; [failing] answer 500; [summary] replaces the
/// summary (a string is sent as the body itself); [seen] records the requests.
MockClient _explorer({
  Set<String> failing = const {},
  Object? summary,
  String tip = '$_tip',
  List<Uri>? seen,
}) =>
    MockClient((req) async {
      seen?.add(req.url);
      final p = req.url.path;
      if (failing.contains(p)) return http.Response('down', 500);
      return switch (p) {
        '/api/blocks/tip/height' => http.Response(tip, 200),
        '/api/mining/miner-summary' => summary is String
            ? http.Response(summary, 200)
            : _ok(summary ?? _summary()),
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
        {required ChainWeather chain, PoolsWeather? pools, bool seenLive = false}) =>
    ProviderScope(
      overrides: [
        authProvider.overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet(network))),
        mainnetSeenLiveProvider.overrideWith(() => _SeenLive(seenLive)),
        chainWeatherProvider.overrideWith((ref) => Stream.value(chain)),
        poolsWeatherProvider.overrideWith((ref) => pools == null
            ? const Stream<PoolsWeather>.empty()
            : Stream.value(pools)),
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

  group('the pools reader', () {
    test('reads every pool over the day ending at the tip, by name or by '
        'address, most blocks first, and never a link or a member', () async {
      final seen = <Uri>[];
      final p = await fetchPoolsWeather(client: _explorer(seen: seen));
      expect(p.reachable, isTrue);
      expect(seen.map((u) => u.path),
          ['/api/blocks/tip/height', '/api/mining/miner-summary']);
      expect(seen[1].queryParameters,
          {'startHeight': '${_tip - 1439}', 'endHeight': '$_tip'},
          reason: 'one day of blocks at sixty seconds, ending at the tip');
      expect(p.startHeight, _tip - 1439);
      expect(p.endHeight, _tip);
      expect(p.blocks, 145);
      expect(p.pools.map((s) => s.label), [
        'F2Pool', 'sq1psjvu5z…zyfc2n', 'LuxxPool', 'sq1pu43lfd…v270c8',
        'Mining-Dutch', 'sq1p8k44sc…u3rxdx',
      ]);
      expect(p.pools.map((s) => s.blocks), [104, 16, 13, 7, 4, 1]);
      expect(p.pools[0].address, isNull);
      expect(p.pools[1].address, _lp);
      expect(p.pools[1].name, isEmpty);
      expect(p.shareOf(p.pools[0]), closeTo(0.7172, 0.0001));
      expect(fmtShare(p.shareOf(p.pools[0])), '72%');
      // The reader names a link, a finder or the explorer's own details
      // nowhere: not as a key it reads, not as a field it keeps.
      final reader = File('lib/services/weather_service.dart').readAsStringSync();
      for (final word in ["'link'", "'finder'", "'details'", "'identifiedBy'"]) {
        expect(reader, isNot(contains(word)), reason: word);
      }
    });

    test('the tip not answering, or not a height, or the summary not '
        'answering or not an object, is unreachable', () async {
      Future<bool> reachable(MockClient c) async =>
          (await fetchPoolsWeather(client: c)).reachable;
      expect(await reachable(_explorer(failing: {'/api/blocks/tip/height'})),
          isFalse);
      expect(await reachable(_explorer(tip: 'soon')), isFalse);
      expect(await reachable(_explorer(tip: '-5')), isFalse);
      expect(await reachable(_explorer(failing: {'/api/mining/miner-summary'})),
          isFalse);
      expect(await reachable(_explorer(summary: '[1, 2]')), isFalse,
          reason: 'a body that is not an object');
      expect(await reachable(_explorer(summary: 'not json')), isFalse);
      expect((await fetchPoolsWeather(client: _explorer(tip: 'soon'))).pools,
          isEmpty);
    });

    test('talks to the Mainnet explorer only, over one day of blocks, and '
        'starts at genesis when the chain is shorter', () async {
      final seen = <Uri>[];
      await fetchPoolsWeather(client: _explorer(seen: seen));
      final host = Uri.parse(SoqNetwork.mainnet.explorerUrl!).host;
      expect(seen.map((u) => u.host).toSet(), {host});
      expect(seen.map((u) => u.scheme).toSet(), {'https'});
      expect(kPoolsWindow, 1440);
      final young = <Uri>[];
      await fetchPoolsWeather(client: _explorer(tip: '20', seen: young));
      expect(young[1].queryParameters, {'startHeight': '0', 'endHeight': '20'});
    });

    test('a hostile answer reads as bounded text: control and invisible '
        'characters go, a long name is cut, a bad address reads as a name, '
        'an empty or blockless group is dropped, and more than 24 groups are '
        'capped at the biggest', () async {
      final many = {for (var i = 0; i < 30; i++) 'pool $i': _group('pool $i', i + 1)};
      final hostile = {
        'miners': {
          ...many,
          'F2\u202EPool\u0000': _group('x', 100),
          'address-only:NOT an address': _group('x', 50),
          '   \u200B': _group('x', 40),
          'none': {'blocks': <int>[]},
          'string blocks': {'blocks': 'ten'},
          'x' * 100: _group('x', 60),
          // The explorer's counts are not read: the heights are.
          'counted': {'blocks': [1, 2], 'subsidyCount': 1000},
        },
      };
      final p = await fetchPoolsWeather(client: _explorer(summary: hostile));
      expect(p.reachable, isTrue);
      expect(p.pools.length, 24);
      expect(p.pools[0].label, 'F2Pool');
      expect(p.pools[1].label, 'x' * 40);
      expect(p.pools[2].label, 'address-only:NOT an address');
      final labels = p.pools.map((s) => s.label).toList();
      expect(labels, isNot(contains('none')));
      expect(labels, isNot(contains('string blocks')));
      expect(labels, isNot(contains('')));
      expect(labels, isNot(contains('counted')),
          reason: 'two blocks fall below the 24 biggest');
      expect(p.pools.last.blocks, 10, reason: '100, 60, 50, then 30 down to 10');
      expect(p.blocks, p.pools.fold(0, (sum, s) => sum + s.blocks));
    });

    test('every field takes every JSON shape without a throw', () async {
      final shapes = <Object?>[null, true, 0, -1, 1.5, 'x', [], [1, 'a'], {}, {'a': 1}];
      for (final shape in shapes) {
        for (final body in [
          {'miners': shape},
          {'miners': {'F2Pool': shape}},
          {'miners': {'F2Pool': {'blocks': shape}}},
          {'miners': {'address-only:$_f2': {'blocks': shape}}},
          {'overall': shape, 'minerNamesSortedByBlockCount': shape},
        ]) {
          final p = await fetchPoolsWeather(client: _explorer(summary: body));
          expect(p.reachable, isTrue, reason: 'shape $shape in $body answered');
        }
      }
    });

    test('a tie in blocks sorts by label, and an empty window has no shares',
        () async {
      final tie = {'miners': {'Zeta': _group('Zeta', 5), 'Alpha': _group('Alpha', 5)}};
      final p = await fetchPoolsWeather(client: _explorer(summary: tie));
      expect(p.pools.map((s) => s.label), ['Alpha', 'Zeta']);
      final empty =
          await fetchPoolsWeather(client: _explorer(summary: {'miners': {}}));
      expect(empty.reachable, isTrue);
      expect(empty.pools, isEmpty);
      expect(empty.blocks, 0);
      expect(empty.shareOf(const PoolShare(name: 'x', blocks: 1)), 0);
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
    test('share', () {
      expect(fmtShare(0.7172), '72%');
      expect(fmtShare(1), '100%');
      expect(fmtShare(0), '0%');
      expect(fmtShare(0.004), '<1%');
      expect(fmtShare(0.006), '1%');
      expect(fmtShare(double.nan), '—');
      expect(fmtShare(-0.1), '—');
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

    test('a returning watcher gets a fresh pools poll at once, on the '
        'Mainnet explorer', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var sub = container.listen(poolsWeatherProvider, (_, _) {});
      await until(() => overrides.urls.isNotEmpty);
      expect(overrides.urls.first.host,
          Uri.parse(SoqNetwork.mainnet.explorerUrl!).host);
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = overrides.urls.length;
      sub = container.listen(poolsWeatherProvider, (_, _) {});
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
    Future<PoolsWeather> livePools() => fetchPoolsWeather(client: _explorer());

    for (final size in [_large, _small]) {
      testWidgets('Stagenet live reads the chain, the schedule and the pools '
          'on ${size.width.toInt()} wide', (tester) async {
        _surface(tester, size);
        await tester.pumpWidget(_screen(SoqNetwork.stagenet,
            chain: liveChain, pools: await livePools()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('SOQUCOIN · ML-DSA-44 · LIVE'), findsOneWidget);
        expect(find.text('CHAIN · STAGENET'), findsOneWidget);
        // The weather in words, then the cards: closed at first, with their
        // one-line summaries; the grids wait for a tap.
        expect(find.textContaining('Blocks are arriving on time.'), findsOneWidget);
        expect(
            find.textContaining(
                '6 pools found the last day\'s blocks; F2Pool found 72%.'),
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
        // The pools card sits below the fold on the small surface and the
        // list builds lazily: bring each part into view before reading it.
        await tester.scrollUntilVisible(find.text('6 MINING'), 120, scrollable: list);
        await tester.pump();
        expect(find.text('POOLS'), findsOneWidget);
        expect(find.text('6 MINING'), findsOneWidget);
        expect(find.text('F2POOL 72% · SQ1PSJVU5Z…ZYFC2N 11% · 4 MORE'),
            findsOneWidget, reason: 'the pools card\'s line, closed');
        expect(find.text('145 BLOCKS · LAST 24 H · MAINNET'), findsOneWidget);
        expect(find.text('F2POOL'), findsNothing, reason: 'closed');
        await tester.tap(find.byKey(const ValueKey('card pools')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(find.text('MINING-DUTCH'), 120,
            scrollable: list);
        await tester.pump();
        expect(find.text('F2POOL'), findsOneWidget);
        expect(find.text('72%'), findsOneWidget);
        expect(find.text('104 BLOCKS'), findsOneWidget);
        expect(find.text('SQ1PSJVU5Z…ZYFC2N'), findsOneWidget,
            reason: 'a pool the explorer has no name for, by its address');
        expect(find.text('1 BLOCK'), findsOneWidget, reason: 'the singular');
        expect(find.textContaining(RegExp(r'^~[0-9.]+ [kMGTPE]?H/s$')),
            findsNothing,
            reason: 'no hashrate per pool on Stagenet: the pools are '
                'Mainnet\'s, the figure would be this chain\'s');
        await tester.scrollUntilVisible(
            find.textContaining('reads only what the chain shows'), 120,
            scrollable: list);
        await tester.pump();
        expect(find.textContaining('reads only what the chain shows'),
            findsOneWidget);
        expect(find.textContaining('f2pool'), findsNothing,
            reason: 'no link on screen');
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
          chain: liveChain, pools: await livePools()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.bySemanticsLabel('Under a minute since the last block. '
              'Block 112,105. Network hashrate 20.4 GH/s.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pools: await livePools()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Block clock offline.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });

    testWidgets('Mainnet not yet answered waits: the clock is offline, the '
        'schedule reads from genesis and the pools section waits', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pools: await livePools()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SOQUCOIN · ML-DSA-44 · OFFLINE'), findsOneWidget);
      expect(find.textContaining('Connecting to Mainnet'), findsOneWidget);
      expect(find.byKey(const ValueKey('weather line')), findsNothing,
          reason: 'nothing was read, so no sentence under the clock');
      expect(find.text('100,000 SOQ A BLOCK AT GENESIS'), findsOneWidget,
          reason: 'the emission card\'s line, closed');
      expect(find.text('WAITING FOR THE NETWORK'), findsOneWidget,
          reason: 'the pools card\'s line, closed');
      await tester.tap(find.byKey(const ValueKey('card emission')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('BLOCK REWARD · GENESIS'), findsOneWidget);
      expect(find.text('100,000 SOQ'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('card pools')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('appears here once Mainnet answers'),
          findsOneWidget);
      expect(find.text('6 MINING'), findsNothing,
          reason: 'the pools report on the chain they mine, not yet this one');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Mainnet after launch, unreachable, says it is reconnecting',
        (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: offline, pools: await livePools(), seenLive: true));
      await tester.pump();
      expect(find.text('Reconnecting to the network.'), findsOneWidget);
      expect(find.textContaining('Connecting to Mainnet'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Mainnet live shows the pools, each with the hashrate its '
        'share of the blocks stands for', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.mainnet,
          chain: liveChain, pools: await livePools(), seenLive: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CHAIN · MAINNET'), findsOneWidget);
      expect(find.text('6 MINING'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('card pools')), 120, scrollable: list);
      await tester.tap(find.byKey(const ValueKey('card pools')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(find.text('~14.6 GH/s'), 120,
          scrollable: list);
      await tester.pump();
      expect(find.text('~14.6 GH/s'), findsOneWidget,
          reason: '72% of the network\'s 20.4 GH/s');
      await tester.scrollUntilVisible(find.text('~140.7 MH/s'), 120,
          scrollable: list);
      await tester.pump();
      expect(find.text('~140.7 MH/s'), findsOneWidget,
          reason: '1 of 145 blocks of 20.4 GH/s');
      expect(tester.takeException(), isNull);
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

    testWidgets('hostile figures never break the build: a share over the '
        'whole, a total of nothing, a tip without a time', (tester) async {
      _surface(tester, _large);
      final odd = PoolsWeather(
        reachable: true,
        blocks: 3,
        pools: const [
          PoolShare(name: 'Over', blocks: 5),
          PoolShare(name: '', address: 'sq1pshort', blocks: 0),
        ],
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
      await tester.pumpWidget(_screen(SoqNetwork.stagenet, chain: noTip, pools: odd));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // The hostile figures sit in the grids: open every card to build them.
      for (final id in ['chain', 'emission', 'pools']) {
        await tester.tap(find.byKey(ValueKey('card $id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('OVER'), findsOneWidget, reason: 'the rows built');
      expect(find.text('100%'), findsOneWidget, reason: 'a share is at most the whole');
      expect(find.text('SQ1PSHORT'), findsOneWidget, reason: 'a short address, whole');
      expect(find.text('0%'), findsOneWidget);
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
      final line = find.textContaining('Connecting to Mainnet');
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
          chain: liveChain, pools: await livePools()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('6 MINING'), 120, scrollable: list);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'nothing overflows at the limit');
      // Every card open as well.
      for (final id in ['chain', 'emission', 'pools']) {
        await tester.scrollUntilVisible(find.byKey(ValueKey('card $id')), 120,
            scrollable: list);
        await tester.tap(find.byKey(ValueKey('card $id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.scrollUntilVisible(
          find.textContaining('reads only what the chain shows'), 120,
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
        'pools (they report on Mainnet)', (tester) async {
      _surface(tester, _large);
      await tester.pumpWidget(_screen(SoqNetwork.stagenet,
          chain: liveChain, pools: await livePools(), seenLive: true));
      await tester.pump();
      expect(find.text('POOLS'), findsNothing);
      expect(find.text('6 MINING'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

