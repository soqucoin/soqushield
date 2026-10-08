// The Network tab's shape after the density cut: one sentence of weather in
// words under the clock, three cards closed at first with a one-line summary
// each, open on a tap and closed on the next. The Send diagram's balance
// shrinks to its column instead of running into the trunk. The manual names
// what the screens now show.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/guide/guide_content.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/launch_state_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/network/network_screen.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/figures.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _stagenetAddress =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

WalletState _wallet() => WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _stagenetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: SoqNetwork.stagenet,
      backupConfirmed: true,
      isInitialized: true,
    );

class _SeenLive extends MainnetSeenLiveNotifier {
  @override
  bool build() => false;
}

ChainWeather _chain({required Duration sinceTip}) => ChainWeather(
      reachable: true,
      height: 112105,
      tipTime: DateTime.now().subtract(sinceTip),
      difficulty: 407.84,
      hashrate: 20398783697.58,
      mempoolTx: 3,
      peers: 10,
      fetchedAt: DateTime.now(),
    );

PoolWeather _pool({int? miners = 5, String? overall = 'operational'}) =>
    PoolWeather(
      reachable: true,
      fetchedAt: DateTime.now(),
      poolHashrate: 1.3e9,
      activeMiners: miners,
      workers: 11,
      blocksPerHour: 52,
      blocks24h: 1324,
      luck24h: 98,
      overall: overall,
      regions: const [],
      nextPayoutEta: '3h 51m',
      feeRate: 0.015,
      scheme: 'PPLNS',
      latestBlocks: const [],
    );

/// The screen with the chain poll answering [chain], or still loading when
/// [chain] is null; under the platform's reduced-motion setting when
/// [reduced].
Widget _screen(
        {required ChainWeather? chain, PoolWeather? pool, bool reduced = false}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        mainnetSeenLiveProvider.overrideWith(_SeenLive.new),
        chainWeatherProvider.overrideWith((ref) => chain == null
            ? const Stream<ChainWeather>.empty()
            : Stream.value(chain)),
        poolWeatherProvider.overrideWith((ref) => pool == null
            ? const Stream<PoolWeather>.empty()
            : Stream.value(pool)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: const NetworkPilotScreen(),
          ),
        ),
      ),
    );

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String _weatherText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('weather line'))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  group('the Network cards', () {
    testWidgets(
        'are closed at first with their summaries, open one at a time on a '
        'tap, and close on the next', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 42)), pool: _pool()));
      await _settle(tester);
      expect(find.text('CHAIN · STAGENET'), findsOneWidget);
      expect(find.text('EMISSION'), findsOneWidget);
      expect(find.text('SOQUPOOL'), findsOneWidget);
      expect(find.text('HEIGHT'), findsNothing, reason: 'the chain grid waits');
      expect(find.text('BLOCK REWARD'), findsNothing);
      expect(find.text('POOL HASHRATE'), findsNothing);
      expect(find.text('DIFFICULTY 407.8 · MEMPOOL 3 TX · 10 PEERS'),
          findsOneWidget, reason: 'the chain card\'s second line');
      expect(find.text('100,000 SOQ A BLOCK'), findsOneWidget);
      expect(find.textContaining('5 MINERS · 52 BLOCKS / HR · '), findsOneWidget,
          reason: 'the pool card\'s line: miners, blocks an hour, hashrate');

      await tester.tap(find.byKey(const ValueKey('card chain')));
      await _settle(tester);
      expect(find.text('HEIGHT'), findsOneWidget, reason: 'the chain opens');
      expect(find.text('BLOCK REWARD'), findsNothing,
          reason: 'the others stay closed');

      await tester.tap(find.byKey(const ValueKey('card chain')));
      await _settle(tester);
      expect(find.text('HEIGHT'), findsNothing, reason: 'a second tap closes');

      await tester.tap(find.byKey(const ValueKey('card pool')));
      await _settle(tester);
      expect(find.text('POOL HASHRATE'), findsOneWidget);
      expect(find.text('1,324'), findsOneWidget, reason: 'blocks in 24 h');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('under reduced motion a card opens at once, and no layout '
        'error is raised on the way', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 42)),
          pool: _pool(),
          reduced: true));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('card chain')));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no size animation');
      expect(find.text('HEIGHT'), findsOneWidget, reason: 'open in one frame');
      await tester.tap(find.byKey(const ValueKey('card chain')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('HEIGHT'), findsNothing, reason: 'closed in one frame');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('each card header is one button for a screen reader, with '
        'its state', (tester) async {
      _surface(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 42)), pool: _pool()));
      await _settle(tester);
      for (final (id, start) in [
        ('chain', 'CHAIN · STAGENET. LAST BLOCK '),
        ('emission', 'EMISSION. 100,000 SOQ A BLOCK. NEXT 50,000 SOQ IN '),
        ('pool', 'SOQUPOOL. 5 MINERS · 52 BLOCKS / HR · '),
      ]) {
        final node = tester.getSemantics(find.byKey(ValueKey('card $id')));
        expect(node.label, startsWith(start), reason: id);
        expect(node.label, endsWith(' Closed.'), reason: id);
        expect(node.flagsCollection.isButton, isTrue, reason: id);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
            reason: 'a screen reader can open $id');
      }
      expect(find.text('HEIGHT'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('card chain')));
      await _settle(tester);
      final header =
          tester.getSemantics(find.byKey(const ValueKey('card chain')));
      expect(header.label, endsWith(' Open.'));
      expect(header.label, isNot(contains('HEIGHT')),
          reason: 'the figures are not folded into the header');
      // Each figure is one node of its own, after the header.
      final height = tester.getSemantics(find.text('112,105'));
      expect(height.label, contains('HEIGHT'));
      expect(height.label, contains('112,105'));
      expect(height.label, isNot(contains('LAST BLOCK')),
          reason: 'one figure per node');
      handle.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the weather in words', () {
    testWidgets('reads the chain against its target and the pool', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 42)), pool: _pool()));
      await _settle(tester);
      expect(_weatherText(tester),
          'Blocks are arriving on time. SOQUPOOL is operational with 5 miners.');
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 95)),
          pool: _pool(miners: 1)));
      await _settle(tester);
      expect(_weatherText(tester),
          'The next block is a little late. SOQUPOOL is operational with 1 miner.');
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 150)),
          pool: _pool(overall: 'degraded')));
      await _settle(tester);
      expect(_weatherText(tester),
          'The next block is running late. SOQUPOOL reports degraded.');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('says nothing about a chain it has not read: offline, '
        'syncing, or a stale figure; and nothing about a pool that did not '
        'answer', (tester) async {
      _surface(tester);
      await tester.pumpWidget(
          _screen(chain: ChainWeather.unreachable(DateTime.now()), pool: _pool()));
      await _settle(tester);
      expect(find.byKey(const ValueKey('weather line')), findsNothing,
          reason: 'offline Stagenet: no sentence, and no pool sentence either');
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(_screen(chain: null, pool: _pool()));
      await _settle(tester);
      expect(find.byKey(const ValueKey('weather line')), findsNothing,
          reason: 'syncing: the card says so, the sentence does not');
      await tester.pumpWidget(const SizedBox.shrink());

      final stale = ChainWeather(
        reachable: true,
        height: 112105,
        tipTime: DateTime.now().subtract(const Duration(seconds: 42)),
        difficulty: 407.84,
        hashrate: 20398783697.58,
        mempoolTx: 3,
        peers: 10,
        fetchedAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      await tester.pumpWidget(_screen(chain: stale, pool: _pool()));
      await _settle(tester);
      expect(_weatherText(tester), 'SOQUPOOL is operational with 5 miners.',
          reason: 'a figure older than the poll period: the pool alone');
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(_screen(
          chain: _chain(sinceTip: const Duration(seconds: 42)),
          pool: PoolWeather(reachable: false, fetchedAt: DateTime.now())));
      await _settle(tester);
      expect(_weatherText(tester), 'Blocks are arriving on time.',
          reason: 'the pool did not answer: its card says so, not the sentence');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the Send diagram', () {
    test('a balance that fits keeps its size; a long one shrinks to its '
        'column, whole', () {
      double widthAt(String text, double size) => (TextPainter(
            text: TextSpan(
                text: text,
                style: TextStyle(
                    fontSize: size,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w600)),
            textDirection: TextDirection.ltr,
          )..layout())
              .width;
      final natural = widthAt('1234567.89', 19);
      // Room to spare: the size stays.
      expect(fitFontSize('1234567.89', 19, natural + 10, weight: FontWeight.w600), 19);
      // Half the room: the size halves and the whole figure fits.
      final column = natural / 2;
      final fitted =
          fitFontSize('1234567.89', 19, column, weight: FontWeight.w600);
      expect(fitted, lessThan(19));
      expect(fitted, greaterThanOrEqualTo(8));
      expect(widthAt('1234567.89', fitted), lessThanOrEqualTo(column + 0.5),
          reason: 'the digits stay whole and inside the column');
      // The floor holds for an absurd column.
      expect(fitFontSize('1234567.89', 19, 1, weight: FontWeight.w600), 8);
    });

    test('a label smaller than the floor never grows; with its own floor it '
        'shrinks', () {
      expect(fitFontSize('EXCEEDS BALANCE', 7.5, 10, font: kLabel), 7.5,
          reason: 'the default floor of 8 must not lift a 7.5 label');
      expect(
          fitFontSize('EXCEEDS BALANCE', 7.5, 10, minSize: 6.5, font: kLabel),
          6.5);
      expect(fitFontSize('FEE', 7.5, 1000, minSize: 6.5, font: kLabel), 7.5,
          reason: 'a label that fits keeps its size');
    });
  });

  group('the Field Manual', () {
    test('names the cards, the share chip and the network row', () {
      final network = guideArticleById('network')!;
      expect(network.sections.any((s) => (s.body ?? '').contains('Tap a card')),
          isTrue);
      expect(network.sections.any((s) => s.steps.any((t) => t.startsWith('CHAIN:'))),
          isTrue);
      final receive = guideArticleById('receive')!;
      expect(receive.sections.any((s) => s.steps.any((t) => t.contains('SHARE ADDRESS'))),
          isTrue);
      final wallet = guideArticleById('wallet')!;
      expect(wallet.sections.any((s) => s.steps.any((t) => t.startsWith('NETWORK shows'))),
          isTrue);
    });

    test('names no screen the lite app does not have', () {
      final text = guideCategories
          .expand((c) => c.articles)
          .expand((a) => a.sections)
          .map((s) => '${s.heading ?? ''} ${s.body ?? ''} ${s.steps.join(' ')} ${s.note ?? ''}')
          .join(' ');
      for (final absent in ['Observatory', 'Lightning', 'swap', 'SOQ-TEC', 'address book', 'Phantom']) {
        expect(text.contains(absent), isFalse, reason: '$absent is not in the lite app');
      }
    });
  });
}
