// Motion fires once per real event and comes to rest, and never on anything
// else. The first cases are the attacks: a poll that repeats a height, a
// height that falls, the first answer after loading, a copy that never
// happened, a rebuild with no change, and the platform's reduced-motion
// setting, under which every effect shows its end state and nothing moves.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/launch_state_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/screens/auth/welcome_pilot_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/screens/receive/receive_pilot_screen.dart';
import 'package:soqushield/screens/settings/settings_pilot_screen.dart';
import 'package:soqushield/services/auth_service.dart';
import 'package:soqushield/services/weather_service.dart';
import 'package:soqushield/theme/instrument.dart';
import 'package:soqushield/theme/motion.dart';

import 'lite_test_support.dart';

const _address =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

WalletState _wallet() => WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _address,
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

ChainWeather _chain(int height) => ChainWeather(
      reachable: true,
      height: height,
      tipTime: DateTime.now().subtract(const Duration(seconds: 30)),
      difficulty: 400,
      hashrate: 2e10,
      mempoolTx: 1,
      peers: 8,
      fetchedAt: DateTime.now(),
    );

void _surface(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Device auth that reports a biometric sensor, so Settings shows the
/// biometric row once its availability has loaded.
class _BiometricAuthService extends FakeAuthService {
  @override
  Future<bool> isBiometricAvailable() async => true;
}

/// A screen under the app's providers, with the chain poll fed by [feed]
/// and the platform's reduced-motion setting at [reduced], or driven by
/// [reducedSwitch] so a test can flip it while an effect runs.
Widget _app(Widget screen,
        {required Stream<ChainWeather> feed,
        bool reduced = false,
        ValueListenable<bool>? reducedSwitch,
        AuthService? auth}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        mainnetSeenLiveProvider.overrideWith(_SeenLive.new),
        chainWeatherProvider.overrideWith((ref) => feed),
      ],
      child: MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: reducedSwitch ?? ValueNotifier<bool>(reduced),
          builder: (context, r, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: r),
            child: screen,
          ),
        ),
      ),
    );

CustodyLinePainter _custody(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is CustodyLinePainter))
    .painter as CustodyLinePainter;

QrLockOnPainter _qrLockOn(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is QrLockOnPainter))
    .painter as QrLockOnPainter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;
  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
  });

  bool buzzed() =>
      platformCalls.any((c) => c.method == 'HapticFeedback.vibrate');
  bool copied(String text) => platformCalls.any((c) =>
      c.method == 'Clipboard.setData' &&
      (c.arguments as Map)['text'] == text);

  group('home: the heartbeat', () {
    testWidgets(
        'fires once per height increase, silent, and never on the first '
        'answer, a repeated height or a falling one; the lock-on frames only '
        'a heartbeat', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(_app(const HomePilotScreen(), feed: feed.stream));
      await tester.pump();
      final figure =
          tester.state(find.byType(HomePilotScreen)) as InstrumentFigureMixin;
      // The appear billet runs and lands; it frames nothing.
      expect(figure.pulse.isAnimating, isTrue, reason: 'the appear billet');
      await tester.pump(const Duration(milliseconds: 1400));
      expect(figure.pulse.isAnimating, isFalse);
      expect(_custody(tester).lockOn, lessThan(0),
          reason: 'no block landed, so no brackets');

      // The first answer after loading is not a block.
      feed.add(_chain(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse, reason: 'first answer');
      expect(_custody(tester).chainValue, 'BLOCK 100', reason: 'the fact');

      // The same height polled again is not a block.
      feed.add(_chain(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse, reason: 'repeated height');

      // A new block: one silent outward billet, then the brackets.
      feed.add(_chain(101));
      await tester.pump();
      expect(figure.pulse.isAnimating, isTrue, reason: 'a new block');
      expect(figure.figureDir, 1);
      expect(buzzed(), isFalse, reason: 'the heartbeat is silent');
      await tester.pump(const Duration(milliseconds: 1250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse);
      final landed = _custody(tester).lockOn;
      expect(landed, inInclusiveRange(0.0, 1.0),
          reason: 'the billet landed, the brackets run');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_custody(tester).lockOn, lessThan(0), reason: 'at rest again');

      // A falling height (a reorg, a stale node) is not a block.
      feed.add(_chain(99));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse, reason: 'falling height');
      expect(_custody(tester).lockOn, lessThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'under reduced motion the breath holds, a new block shows its end '
        'state and nothing moves', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(
          _app(const HomePilotScreen(), feed: feed.stream, reduced: true));
      await tester.pump();
      final figure =
          tester.state(find.byType(HomePilotScreen)) as InstrumentFigureMixin;
      expect(figure.reducedMotion, isTrue);
      expect(figure.breath.isAnimating, isFalse, reason: 'the breath holds');
      expect(figure.pulse.isAnimating, isFalse, reason: 'no appear billet');

      feed.add(_chain(100));
      await tester.pump();
      feed.add(_chain(101));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse, reason: 'no billet');
      expect(_custody(tester).chainValue, 'BLOCK 101',
          reason: 'the fact shows');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_custody(tester).lockOn, lessThan(0), reason: 'no brackets');

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('receive: the lock-on and the copy', () {
    testWidgets(
        'the brackets lock onto the QR on entry and settle to a frame; the '
        'copy confirmation fires only on a copy and comes to rest',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(_app(const ReceivePilotScreen(),
          feed: const Stream<ChainWeather>.empty()));
      await tester.pump();
      final lockOn = _qrLockOn(tester);
      expect(lockOn.progress.isAnimating, isTrue, reason: 'converging');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(lockOn.progress.isAnimating, isFalse);
      expect(lockOn.progress.value, 1.0, reason: 'the frame at rest');
      expect(tester.widget<ReceiveQr>(find.byType(ReceiveQr)).data, _address,
          reason: 'the code is the bare address, untouched');

      final buttonRing = tester.state<RingPulseState>(find.ancestor(
          of: find.byType(InstrumentButton), matching: find.byType(RingPulse)));
      final wipe = tester.state<TintWipeState>(find.byType(TintWipe));
      expect(buttonRing.active, isFalse, reason: 'nothing copied yet');
      expect(wipe.active, isFalse);
      expect(copied(_address), isFalse);

      await tester.tap(find.text('COPY ADDRESS'));
      await tester.pump();
      expect(copied(_address), isTrue);
      expect(buttonRing.active, isTrue, reason: 'the ring under the finger');
      expect(wipe.active, isTrue, reason: 'the wipe across the address');
      expect(find.text(_address), findsOneWidget,
          reason: 'the address itself never changes');
      await tester.pump(const Duration(milliseconds: 1200));
      expect(buttonRing.active, isFalse,
          reason: 'the ring rests within its 350 ms');
      expect(wipe.active, isFalse,
          reason: 'the wipe rests after its 350 ms delay and 700 ms sweep');

      // A rebuild with no copy fires nothing.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(buttonRing.active, isFalse);
      expect(wipe.active, isFalse);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'under reduced motion the frame is in place at once and a copy is a '
        'short blip, no ring', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_app(const ReceivePilotScreen(),
          feed: const Stream<ChainWeather>.empty(), reduced: true));
      await tester.pump();
      final lockOn = _qrLockOn(tester);
      expect(lockOn.progress.isAnimating, isFalse);
      expect(lockOn.progress.value, 1.0, reason: 'the frame, in place');

      final buttonRing = tester.state<RingPulseState>(find.ancestor(
          of: find.byType(InstrumentButton), matching: find.byType(RingPulse)));
      final wipe = tester.state<TintWipeState>(find.byType(TintWipe));
      await tester.tap(find.text('COPY ADDRESS'));
      await tester.pump();
      expect(copied(_address), isTrue);
      expect(buttonRing.active, isFalse, reason: 'no ring');
      expect(wipe.active, isTrue, reason: 'the blip');
      await tester.pump(const Duration(milliseconds: 200));
      expect(wipe.active, isFalse, reason: 'over within 150 ms');

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('settings: the toggle ring', () {
    testWidgets('rings once when a setting changes and not on a rebuild',
        (tester) async {
      _surface(tester);
      await tester.pumpWidget(_app(const SettingsPilotScreen(),
          feed: const Stream<ChainWeather>.empty()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final row = find.ancestor(
          of: find.text('Lock on background'), matching: find.byType(RingPulse));
      expect(row, findsOneWidget);
      final ring = tester.state<RingPulseState>(row);
      expect(ring.active, isFalse, reason: 'nothing changed yet');

      await tester.tap(find.text('Lock on background'));
      await tester.pump();
      expect(ring.active, isTrue, reason: 'the setting changed');
      await tester.pump(const Duration(milliseconds: 400));
      expect(ring.active, isFalse, reason: 'at rest');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ring.active, isFalse, reason: 'a rebuild rings nothing');

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'the biometric row appearing after its availability loads rings no '
        'toggle', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_app(const SettingsPilotScreen(),
          feed: const Stream<ChainWeather>.empty(),
          auth: _BiometricAuthService()));
      expect(find.text('Biometric lock'), findsNothing,
          reason: 'the first frame, before the availability loads');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Biometric lock'), findsOneWidget,
          reason: 'the row is inserted above Lock on background');
      for (final element in find.byType(RingPulse).evaluate()) {
        final state = (element as StatefulElement).state as RingPulseState;
        expect(state.active, isFalse,
            reason: 'no setting changed, so no ring; each ring stays with '
                'its own row');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the wipe comes to rest', () {
    test('the wash is off the text at both ends of the sweep', () {
      expect(tintWipeStops(0), everyElement(0.0),
          reason: 'before the sweep the band is left of the text');
      expect(tintWipeStops(1), everyElement(1.0),
          reason: 'on the last frame the band and its wash have left');
      for (var p = 0.0; p <= 1.0; p += 0.05) {
        final stops = tintWipeStops(p);
        for (var i = 1; i < stops.length; i++) {
          expect(stops[i], greaterThanOrEqualTo(stops[i - 1]),
              reason: 'stops stay ordered at $p');
        }
      }
    });

    testWidgets(
        'the wipe tints the text mid-sweep and has fully left it on its last '
        'frame, so the rest state is not a cut', (tester) async {
      _surface(tester);
      final key = GlobalKey();
      var copies = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return RepaintBoundary(
              key: key,
              child: TintWipe(
                trigger: copies,
                child: Container(width: 300, height: 20, color: Colors.white),
              ),
            );
          }),
        ),
      ));
      Future<List<int>> rgbAt(double fx) => tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            final x = (fx * image.width).floor();
            final y = image.height ~/ 2;
            final i = (y * image.width + x) * 4;
            return [bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2)];
          }).then((v) => v!);
      rebuild(() => copies++);
      await tester.pump();
      final wipe = tester.state<TintWipeState>(find.byType(TintWipe));
      expect(wipe.active, isTrue);
      await tester.pump(const Duration(milliseconds: 350));
      expect(await rgbAt(0.5), isNot([255, 255, 255]),
          reason: 'mid-sweep the wash sits on the text');
      await tester.pump(const Duration(milliseconds: 340));
      expect(wipe.active, isTrue, reason: 'the last animated frame');
      expect(await rgbAt(0.90), [255, 255, 255],
          reason: 'the wash has left the right of the text');
      expect(await rgbAt(0.98), [255, 255, 255],
          reason: 'and its edge');
      await tester.pump(const Duration(milliseconds: 50));
      expect(wipe.active, isFalse);
      expect(await rgbAt(0.5), [255, 255, 255], reason: 'at rest, as it began');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the shared pulse, the other sweeps and reduced motion in flight', () {
    testWidgets(
        'a refresh during a pending heartbeat lands at the key and frames '
        'nothing; the next block still frames', (tester) async {
      _surface(tester);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);
      await tester.pumpWidget(_app(const HomePilotScreen(), feed: feed.stream));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      final figure =
          tester.state(find.byType(HomePilotScreen)) as InstrumentFigureMixin;
      feed.add(_chain(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      feed.add(_chain(101));
      await tester.pump();
      expect(figure.pulse.isAnimating, isTrue, reason: 'the heartbeat');
      await tester.pump(const Duration(milliseconds: 300));
      // Pull-to-refresh restarts the shared pulse inward mid-flight.
      figure.fireFigure(-1, haptic: false);
      expect(figure.figureDir, -1);
      await tester.pump(); // the restarted pulse's first tick
      await tester.pump(const Duration(milliseconds: 1250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(figure.pulse.isAnimating, isFalse);
      expect(_custody(tester).lockOn, lessThan(0),
          reason: 'the bead landed at the key, nothing to frame');
      // The pending flag was cleared, not kept for a later completion.
      feed.add(_chain(102));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_custody(tester).lockOn, inInclusiveRange(0.0, 1.0),
          reason: 'the next block frames as usual');
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'the welcome lattice comes online once through the guarded start, '
        'and under reduced motion is settled with no sweep', (tester) async {
      _surface(tester);
      await tester.pumpWidget(_app(const WelcomePilotScreen(),
          feed: const Stream<ChainWeather>.empty()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      var figure = tester.state(find.byType(WelcomePilotScreen))
          as InstrumentFigureMixin;
      expect(figure.pulse.isAnimating, isTrue, reason: 'crystallising');
      expect(buzzed(), isFalse, reason: 'silent, as before');
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(_app(const WelcomePilotScreen(),
          feed: const Stream<ChainWeather>.empty(), reduced: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      figure = tester.state(find.byType(WelcomePilotScreen))
          as InstrumentFigureMixin;
      expect(figure.pulse.isAnimating, isFalse, reason: 'settled, no sweep');
      expect(figure.breath.isAnimating, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'reduced motion switched on while an effect runs ends it at its end '
        'state: the billet, the brackets, the ring, the wipe, the QR frame',
        (tester) async {
      _surface(tester);
      final reduced = ValueNotifier<bool>(false);
      final feed = StreamController<ChainWeather>();
      addTearDown(feed.close);

      // Home, mid-billet.
      await tester.pumpWidget(_app(const HomePilotScreen(),
          feed: feed.stream, reducedSwitch: reduced));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      final figure =
          tester.state(find.byType(HomePilotScreen)) as InstrumentFigureMixin;
      feed.add(_chain(100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      feed.add(_chain(101));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(figure.pulse.isAnimating, isTrue);
      reduced.value = true;
      await tester.pump();
      expect(figure.reducedMotion, isTrue);
      expect(figure.pulse.isAnimating, isFalse, reason: 'the billet ends');
      expect(figure.breath.isAnimating, isFalse, reason: 'the breath holds');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(_custody(tester).lockOn, lessThan(0),
          reason: 'the pending heartbeat had nothing to land');

      // Home, mid-brackets.
      reduced.value = false;
      await tester.pump();
      expect(figure.breath.isAnimating, isTrue, reason: 'the breath resumes');
      feed.add(_chain(102));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_custody(tester).lockOn, inInclusiveRange(0.0, 1.0));
      reduced.value = true;
      await tester.pump();
      expect(_custody(tester).lockOn, lessThan(0), reason: 'the frame ends');
      await tester.pumpWidget(const SizedBox.shrink());

      // Receive, mid-converge; then a copy mid-ring and mid-wipe.
      reduced.value = false;
      await tester.pumpWidget(_app(const ReceivePilotScreen(),
          feed: const Stream<ChainWeather>.empty(), reducedSwitch: reduced));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final lockOn = _qrLockOn(tester);
      expect(lockOn.progress.isAnimating, isTrue, reason: 'converging');
      reduced.value = true;
      await tester.pump();
      expect(lockOn.progress.isAnimating, isFalse);
      expect(lockOn.progress.value, 1.0, reason: 'the frame, in place');
      reduced.value = false;
      await tester.pump();
      await tester.tap(find.text('COPY ADDRESS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final buttonRing = tester.state<RingPulseState>(find.ancestor(
          of: find.byType(InstrumentButton), matching: find.byType(RingPulse)));
      final wipe = tester.state<TintWipeState>(find.byType(TintWipe));
      expect(buttonRing.active, isTrue);
      expect(wipe.active, isTrue);
      reduced.value = true;
      await tester.pump();
      expect(buttonRing.active, isFalse, reason: 'the ring ends');
      expect(wipe.active, isFalse, reason: 'the wipe ends, the text as it began');
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
