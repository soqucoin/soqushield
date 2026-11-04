// The Network tab's motion fires on real events only and comes to rest. The
// first cases are the attacks: a head that spins free of the chain, a tick
// lit before the head reaches it, a reveal on every poll, a scanline on a
// plain tap or a scroll flick, a buzz on every pointer event, a list that
// stops scrolling, a line that never leaves or glides nowhere, a pool flare
// on a poll whose figures repeat (every poll carries a new read time), and
// the platform's reduced-motion setting, under which the line stands still
// under the finger and nothing else moves.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:soqushield/theme/block_clock_figure.dart';
import 'package:soqushield/theme/instrument.dart';
import 'package:soqushield/theme/motion.dart';
import 'package:soqushield/theme/network_motion.dart';

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

ChainWeather _chain(
        {int height = 112105, Duration sinceTip = const Duration(seconds: 30)}) =>
    ChainWeather(
      reachable: true,
      height: height,
      tipTime: DateTime.now().subtract(sinceTip),
      difficulty: 407.84,
      hashrate: 20398783697.58,
      mempoolTx: 3,
      peers: 10,
      fetchedAt: DateTime.now(),
    );

PoolWeather _pool({
  DateTime? at,
  int miners = 5,
  int workers = 11,
  int blocks24h = 1324,
  double hashrate = 1.3e9,
  double luck = 98,
  double? effort = 41.7,
  String eta = '3h 51m',
  double fee = 0.015,
  String overall = 'operational',
  List<PoolRegion> regions = const [],
  List<PoolBlock> latest = const [],
}) =>
    PoolWeather(
      reachable: true,
      fetchedAt: at ?? DateTime.now(),
      poolHashrate: hashrate,
      activeMiners: miners,
      workers: workers,
      blocksPerHour: 52,
      blocks24h: blocks24h,
      luck24h: luck,
      roundEffortPct: effort,
      overall: overall,
      regions: regions,
      nextPayoutEta: eta,
      feeRate: fee,
      scheme: 'PPLNS',
      latestBlocks: latest,
    );

/// The screen with the chain poll fed by [chain] and the pool poll by
/// [pool], under the platform's reduced-motion setting when [reduced].
Widget _screen({
  required Stream<ChainWeather> chain,
  Stream<PoolWeather> Function()? pool,
  bool reduced = false,
}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        mainnetSeenLiveProvider.overrideWith(_SeenLive.new),
        chainWeatherProvider.overrideWith((ref) => chain),
        poolWeatherProvider.overrideWith(
            (ref) => pool == null ? const Stream<PoolWeather>.empty() : pool()),
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

BlockClockPainter _clock(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BlockClockPainter))
    .painter as BlockClockPainter;

ScanOverlayState _scan(WidgetTester tester) =>
    tester.state(find.byType(ScanOverlay)) as ScanOverlayState;

PoolDotPainter _dot(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PoolDotPainter))
    .painter as PoolDotPainter;

/// The colour a lit text is heading to: the end of its colour tween.
Color? _litColor(WidgetTester tester, String text) =>
    (tester
            .widgetList<TweenAnimationBuilder<Color?>>(find.ancestor(
                of: find.text(text),
                matching: find.byType(TweenAnimationBuilder<Color?>)))
            .first
            .tween as ColorTween)
        .end;

/// The colour a lit text shows this frame: its Text's style.
Color? _shownColor(WidgetTester tester, String text) => tester
    .widget<Text>(find.descendant(
        of: find
            .ancestor(
                of: find.text(text),
                matching: find.byType(TweenAnimationBuilder<Color?>))
            .first,
        matching: find.text(text)))
    .style
    ?.color;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;
  setUp(() {
    installSecureStorageMock();
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  int buzzes() => platformCalls
      .where((c) =>
          c.method == 'HapticFeedback.vibrate' &&
          c.arguments == 'HapticFeedbackType.selectionClick')
      .length;

  group('the comet head and the tick lights', () {
    test('the head sits at the true fraction, on its second lap too', () {
      expect(cometHeadAngle(0), closeTo(-math.pi / 2, 1e-9));
      expect(cometHeadAngle(0.25), closeTo(0, 1e-9));
      expect(cometHeadAngle(1.25), closeTo(0, 1e-9), reason: 'a late block');
    });

    test('a tick lights as the head passes it and never before', () {
      // At 0.26 of a 60-second lap the head is 0.6 s past the third tick.
      final lit = tickFlareAlpha(0.26, 3, 60);
      expect(lit, closeTo(math.exp(-0.6 / 0.5), 1e-6));
      expect(tickFlareAlpha(0.26, 4, 60), 0, reason: 'not reached yet');
      expect(tickFlareAlpha(0.25, 3, 60), 1,
          reason: 'the head exactly on a tick is a crossing, lit in full');
      expect(tickFlareAlpha(1.0, 0, 60), 1,
          reason: 'the head back at twelve lights it in full');
      expect(tickFlareAlpha(0.26, 0, 60), lessThan(0.001),
          reason: 'twelve was passed 15.6 s ago');
      expect(tickFlareAlpha(0, 0, 60), 0, reason: 'nothing has moved');
      expect(tickFlareAlpha(1.002, 0, 60), greaterThan(0.7),
          reason: 'the second lap lights twelve again');
      expect(tickFlareAlpha(0.5, 7, 60), 0, reason: 'ahead of the head');
      expect(tickFlareAlpha(0.5, 1, 0), 0, reason: 'no lap, no light');
    });

    testWidgets(
        'the clock carries the head on a live clocked chain, not while '
        'loading and not under reduced motion', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(_screen(chain: feed.stream));
      await tester.pump();
      expect(_clock(tester).motion, isFalse, reason: 'loading');
      feed.add(_chain());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_clock(tester).motion, isTrue);
      expect(_clock(tester).targetSeconds, 60);
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(
          _screen(chain: Stream.value(_chain()), reduced: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_clock(tester).motion, isFalse, reason: 'reduced motion');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the fraction advances between frames without a timer tick',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(chain: Stream.value(_chain())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final before = _clock(tester).fraction;
      expect(before, greaterThan(0.4));
      // Real time passes; the breath repaints the figure every frame and the
      // fraction is read then, so no second has to tick for it to move.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_clock(tester).fraction, greaterThan(before + 0.003));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the reveal', () {
    testWidgets(
        'runs once when the figures arrive, again on a pull to refresh, and '
        'never on a poll', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(
          _screen(chain: feed.stream, pool: () => Stream.value(_pool())));
      await tester.pump();
      expect(_scan(tester).reveal, lessThan(0), reason: 'nothing arrived');

      feed.add(_chain(height: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).reveal, inInclusiveRange(0.0, 1.0),
          reason: 'the figures arrived');
      expect(_scan(tester).lineY, isNotNull);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_scan(tester).reveal, lessThan(0), reason: 'at rest');
      expect(_scan(tester).lineY, isNull);

      feed.add(_chain(height: 101));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).reveal, lessThan(0), reason: 'a poll is no reveal');

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).reveal, inInclusiveRange(0.0, 1.0),
          reason: 'a pull to refresh reveals again');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_scan(tester).reveal, lessThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('never runs under reduced motion', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(_screen(chain: feed.stream, reduced: true));
      await tester.pump();
      feed.add(_chain());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).reveal, lessThan(0));
      expect(_scan(tester).lineY, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the scanner', () {
    testWidgets(
        'a plain tap shows nothing; a held finger takes the line, lights the '
        'row under it, buzzes as it crosses into another card, and the line '
        'glides to rest on release', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: Stream.value(_chain()), pool: () => Stream.value(_pool())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400)); // the reveal
      expect(_scan(tester).lineY, isNull);

      // A tap on a card opens it and shows no line.
      await tester.tap(find.byKey(const ValueKey('card chain')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_scan(tester).lineY, isNull, reason: 'a tap is no scan');
      expect(find.text('112,105'), findsOneWidget, reason: 'the card opened');
      expect(_litColor(tester, '112,105'), Instrument.readout);

      // A finger that moves before the hold is a scroll flick: nothing.
      final overlayTop = tester.getTopLeft(find.byType(ScanOverlay)).dy;
      final at = tester.getCenter(find.text('112,105'));
      final flick = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 30));
      await flick.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_scan(tester).lineY, isNull, reason: 'a flick is a scroll');
      expect(buzzes(), 0);
      await flick.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(_scan(tester).lineY, isNull);

      // A finger held on the HEIGHT figure.
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_scan(tester).lineY, isNull, reason: 'not held long enough yet');
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      expect(_scan(tester).lineY, closeTo(at.dy - overlayTop, 1.0));
      expect(_litColor(tester, '112,105'), Instrument.leadEdge,
          reason: 'the row under the finger crests');
      expect(_shownColor(tester, '112,105'), Instrument.leadEdge,
          reason: 'and shows it on the first frame, with no ease in');
      expect(_litColor(tester, 'HEIGHT'), Instrument.readout,
          reason: 'its label brightens');
      expect(_shownColor(tester, 'HEIGHT'), Instrument.readout);
      expect(buzzes(), 0, reason: 'no card crossed yet');

      // Up to the chain card's header: the same card, no buzz.
      final header = tester.getCenter(find.byKey(const ValueKey('card chain')));
      await gesture.moveTo(header);
      await tester.pump();
      expect(_scan(tester).lineY, closeTo(header.dy - overlayTop, 1.0));
      expect(buzzes(), 0);
      // Down into the emission card: one buzz.
      final emission =
          tester.getCenter(find.byKey(const ValueKey('card emission')));
      await gesture.moveTo(emission);
      await tester.pump();
      expect(buzzes(), 1, reason: 'crossed into another card');
      expect(_litColor(tester, '112,105'), Instrument.readout,
          reason: 'the figure left behind settles');
      await tester.pump(const Duration(milliseconds: 200));
      final settling = _shownColor(tester, '112,105');
      expect(settling, isNot(Instrument.leadEdge),
          reason: 'half way through the release it has left the crest');
      expect(settling, isNot(Instrument.readout),
          reason: 'and has not reached rest: the settle takes the release time');
      await tester.pump(const Duration(milliseconds: 250));
      expect(_shownColor(tester, '112,105'), Instrument.readout,
          reason: 'at rest after the release time');

      // Release: the line glides to the nearest row edge, then fades. The
      // list bounces between gestures, so the rows are read at the moment of
      // release, from the widgets themselves: the three card headers and the
      // open chain card's six figures, those inside the overlay.
      final fingerY = _scan(tester).lineY!;
      final overlay = tester.getRect(find.byType(ScanOverlay));
      final rows = <Rect>[
        for (final id in ['chain', 'emission', 'pool'])
          tester.getRect(find.byKey(ValueKey('card $id'))),
        for (final label in ['HEIGHT', 'LAST BLOCK', 'HASHRATE', 'DIFFICULTY', 'MEMPOOL', 'PEERS'])
          tester.getRect(find
              .ancestor(of: find.text(label), matching: find.byType(MergeSemantics))
              .first),
      ];
      final edges = rows
          .where((r) => r.overlaps(overlay))
          .expand((r) => [r.top, r.bottom])
          .map((e) => e - overlayTop)
          .toList();
      final expected = edges.reduce(
          (a, b) => (a - fingerY).abs() <= (b - fingerY).abs() ? a : b);
      await gesture.up();
      await tester.pump();
      expect(_scan(tester).fingerDown, isFalse);
      expect(_scan(tester).lineY, closeTo(fingerY, 0.5), reason: 'gliding from the finger');
      await tester.pump(MotionTiming.glide);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_scan(tester).lineY, closeTo(expected, 0.5),
          reason: 'the line sits on the nearest row edge');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).lineY, isNotNull, reason: 'fading');
      await tester.pump(const Duration(milliseconds: 500));
      expect(_scan(tester).lineY, isNull, reason: 'at rest');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'a release during the reveal leaves the reveal its line, with no glide',
        (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(
          _screen(chain: feed.stream, pool: () => Stream.value(_pool())));
      await tester.pump();
      final at = tester.getCenter(find.byKey(const ValueKey('card chain')));
      final gesture = await tester.startGesture(at);
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      expect(_scan(tester).fingerDown, isTrue);
      feed.add(_chain());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scan(tester).reveal, inInclusiveRange(0.0, 1.0));
      await gesture.up();
      await tester.pump();
      expect(_scan(tester).releasing, isFalse, reason: 'no glide under a reveal');
      expect(_scan(tester).lineY, isNotNull, reason: 'the reveal keeps its line');
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_scan(tester).lineY, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a second pointer is ignored while a finger holds the line',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: Stream.value(_chain()), pool: () => Stream.value(_pool())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      final overlayTop = tester.getTopLeft(find.byType(ScanOverlay)).dy;
      final first = tester.getCenter(find.byKey(const ValueKey('card chain')));
      final held = await tester.startGesture(first);
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      expect(_scan(tester).lineY, closeTo(first.dy - overlayTop, 1.0));
      final second = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('card emission'))),
          pointer: 7);
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      expect(_scan(tester).lineY, closeTo(first.dy - overlayTop, 1.0),
          reason: 'the line stays with the first finger');
      await second.up();
      await tester.pump();
      expect(_scan(tester).fingerDown, isTrue, reason: 'the first finger holds');
      await held.up();
      await tester.pump();
      expect(_scan(tester).fingerDown, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a reveal that lands during the release glide ends the glide',
        (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(
          _screen(chain: feed.stream, pool: () => Stream.value(_pool())));
      await tester.pump();
      // A held finger, released: the glide runs.
      final at = tester.getCenter(find.byKey(const ValueKey('card chain')));
      final gesture = await tester.startGesture(at);
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_scan(tester).releasing, isTrue);
      // The figures arrive: the reveal takes the line and the glide ends.
      feed.add(_chain());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_scan(tester).reveal, inInclusiveRange(0.0, 1.0));
      expect(_scan(tester).releasing, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('the buzz limiter allows one click per gap', () {
      final limiter = BuzzLimiter();
      final t0 = DateTime(2026, 10, 8, 12);
      expect(limiter.allow(t0), isTrue);
      expect(limiter.allow(t0.add(const Duration(milliseconds: 60))), isFalse);
      expect(limiter.allow(t0.add(const Duration(milliseconds: 119))), isFalse);
      expect(limiter.allow(t0.add(const Duration(milliseconds: 120))), isTrue);
    });

    testWidgets(
        'the list still scrolls under the overlay (a guard the base passes)',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: Stream.value(_chain()), pool: () => Stream.value(_pool())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      for (final id in ['chain', 'emission', 'pool']) {
        await tester.tap(find.byKey(ValueKey('card $id')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      final before = tester.getTopLeft(find.byKey(const ValueKey('card chain'))).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final after = tester.getTopLeft(find.byKey(const ValueKey('card chain'))).dy;
      expect(after, lessThan(before - 100), reason: 'the list scrolled');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'under reduced motion the line stands still under the finger and '
        'goes at once on release', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_screen(
          chain: Stream.value(_chain()), pool: () => Stream.value(_pool()), reduced: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final overlayTop = tester.getTopLeft(find.byType(ScanOverlay)).dy;
      final at = tester.getCenter(find.byKey(const ValueKey('card chain')));
      final gesture = await tester.startGesture(at);
      await tester.pump(MotionTiming.arm);
      await tester.pump();
      expect(_scan(tester).lineY, closeTo(at.dy - overlayTop, 1.0));
      await gesture.up();
      await tester.pump();
      expect(_scan(tester).lineY, isNull, reason: 'no glide, no fade');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the pool dot', () {
    testWidgets(
        'flares once when the figures change, never on the first answer and '
        'never on a poll that repeats them with a new read time',
        (tester) async {
      _surface(tester);
      final pool = StreamController<PoolWeather>();
      addTearDown(pool.close);
      await tester.pumpWidget(
          _screen(chain: Stream.value(_chain()), pool: () => pool.stream));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final first = DateTime(2026, 10, 8, 12);
      pool.add(_pool(at: first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dot(tester).up, isTrue);
      expect(_dot(tester).flareValue, lessThan(0),
          reason: 'the first answer is an arrival');

      // The production poll: the same figures a minute later.
      pool.add(_pool(at: first.add(const Duration(seconds: 60))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dot(tester).flareValue, lessThan(0),
          reason: 'a repeated figure with a new read time is no update');

      pool.add(_pool(at: first.add(const Duration(seconds: 120)), miners: 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dot(tester).flareValue, inInclusiveRange(0.0, 1.0),
          reason: 'a changed figure is an update');
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_dot(tester).flareValue, lessThan(0), reason: 'at rest');

      pool.add(_pool(at: first.add(const Duration(seconds: 180)), miners: 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dot(tester).flareValue, lessThan(0), reason: 'repeated again');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
        'the figure key ignores the read time, the continuous measurements and '
        'a raw change that renders the same, and changes with each count and '
        'state', () {
      final a = poolFigureKey(_pool(at: DateTime(2026, 10, 8, 12)));
      expect(poolFigureKey(_pool(at: DateTime(2026, 10, 8, 13))), a,
          reason: 'the read time');
      expect(poolFigureKey(_pool(hashrate: 1.31e9)), a, reason: 'hashrate');
      expect(poolFigureKey(_pool(luck: 103.4)), a, reason: 'luck');
      expect(poolFigureKey(_pool(effort: 58.2)), a, reason: 'round effort');
      expect(poolFigureKey(_pool(eta: '3h 50m')), a, reason: 'the countdown');
      expect(poolFigureKey(_pool(fee: 0.015004)), a,
          reason: 'a fee that renders as 1.50% still');
      final t0 = DateTime(2026, 10, 8, 12);
      final one = _pool(latest: [PoolBlock(height: 112100, time: t0)]);
      final aged = _pool(latest: [
        PoolBlock(height: 112100, time: t0.add(const Duration(minutes: 5)))
      ]);
      expect(poolFigureKey(aged), poolFigureKey(one), reason: 'a block\'s age');
      final seventh = _pool(latest: [
        for (var i = 0; i < 7; i++) PoolBlock(height: 112100 - i, time: t0)
      ]);
      final seventhChanged = _pool(latest: [
        for (var i = 0; i < 6; i++) PoolBlock(height: 112100 - i, time: t0),
        PoolBlock(height: 100, time: t0),
      ]);
      expect(poolFigureKey(seventhChanged), poolFigureKey(seventh),
          reason: 'the card shows six blocks');

      expect(poolFigureKey(_pool(miners: 6)), isNot(a), reason: 'miners');
      expect(poolFigureKey(_pool(workers: 12)), isNot(a), reason: 'workers');
      expect(poolFigureKey(_pool(blocks24h: 1325)), isNot(a),
          reason: 'the day\'s blocks');
      expect(poolFigureKey(_pool(fee: 0.0169)), isNot(a), reason: 'the fee');
      expect(poolFigureKey(_pool(overall: 'degraded')), isNot(a),
          reason: 'the status');
      expect(
          poolFigureKey(_pool(regions: const [
            PoolRegion(region: 'us-west', up: true, workers: 4)
          ])),
          isNot(poolFigureKey(_pool(regions: const [
            PoolRegion(region: 'us-west', up: false, workers: 4)
          ]))),
          reason: 'a region\'s state');
      expect(poolFigureKey(_pool(latest: [PoolBlock(height: 112101, time: t0)])),
          isNot(poolFigureKey(one)),
          reason: 'a new block');
    });

    testWidgets('a duplicated height in the latest blocks keys two rows',
        (tester) async {
      _surface(tester);
      final twice = PoolWeather(
        reachable: true,
        fetchedAt: DateTime.now(),
        poolHashrate: 1.3e9,
        activeMiners: 5,
        workers: 11,
        blocksPerHour: 52,
        blocks24h: 1324,
        luck24h: 98,
        overall: 'operational',
        regions: const [],
        nextPayoutEta: '3h 51m',
        feeRate: 0.015,
        scheme: 'PPLNS',
        latestBlocks: [
          PoolBlock(height: 112100, time: DateTime.now()),
          PoolBlock(height: 112100, time: DateTime.now()),
        ],
      );
      await tester.pumpWidget(
          _screen(chain: Stream.value(_chain()), pool: () => Stream.value(twice)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.tap(find.byKey(const ValueKey('card pool')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('112,100'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the manual', () {
    test('tells the reader about the finger and the head, and adds no claim',
        () {
      final network = guideArticleById('network')!;
      final section = network.sections
          .firstWhere((s) => s.heading == 'Reading with a finger');
      expect(section.body, contains('Hold a finger on the figures'));
      expect(section.body, contains('reduce-motion'));
      expect(section.body, contains('every figure is already in the text'));
    });
  });
}
