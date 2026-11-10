// The point scene on the onboarding screens: the mark and the module lattice
// in points, the scan while the device checks a credential, the burst on
// Activate, and one still frame under reduced motion.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/auth/create_account_pilot_screen.dart';
import 'package:soqushield/screens/auth/lock_pilot_screen.dart';
import 'package:soqushield/screens/auth/welcome_pilot_screen.dart';
import 'package:soqushield/services/auth_service.dart' show AuthOutcome;
import 'package:soqushield/theme/instrument.dart';
import 'package:soqushield/theme/point_scene.dart';

import 'lite_test_support.dart';

/// Device auth whose check does not answer until the test says so.
class _HeldAuth extends FakeAuthService {
  final answer = Completer<AuthOutcome>();
  @override
  Future<AuthOutcome> authenticate() => answer.future;
}

/// A wallet whose creation does not finish until the test says so.
class _HeldWallet extends MockWalletNotifier {
  _HeldWallet() : super(const WalletState());
  final done = Completer<void>();
  @override
  Future<void> createWallet(String name) => done.future;
}

Widget _app(
  Widget screen, {
  FakeAuthService? auth,
  MockWalletNotifier? wallet,
  bool reduced = false,
}) => ProviderScope(
  overrides: [
    authProvider.overrideWith(() => MockAuthNotifier(AuthStatus.locked)),
    authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
    sessionProvider.overrideWith(MockSessionNotifier.new),
    if (wallet != null) walletProvider.overrideWith(() => wallet),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        for (final p in ['/welcome', '/seed-backup', '/seed-restore'])
          GoRoute(path: p, builder: (_, _) => Text('at $p')),
      ],
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  ),
);

PointScenePainter _painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<PointScenePainter>()
    .single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSecureStorageMock);

  // The welcome screen on a phone held on its side: the figure gives way, so
  // both actions stay inside the safe area and the restore action answers a tap.
  for (final (name, size, inset) in const [
    ('a phone on its side', Size(852, 393), 21.0),
    ('a small phone on its side', Size(667, 375), 0.0),
    ('the smallest phone on its side', Size(568, 320), 0.0),
  ]) {
    testWidgets('on $name the welcome screen keeps both actions in reach', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.view.padding = FakeViewPadding(bottom: inset);
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(const WelcomePilotScreen()));
      await t.pump();
      expect(t.takeException(), isNull);

      final restore = find.widgetWithText(
        GestureDetector,
        'I ALREADY HAVE A WALLET',
      );
      final safeBottom = size.height - inset;
      for (final action in [find.byType(InstrumentButton), restore]) {
        final box = t.getRect(action);
        expect(box.top, greaterThanOrEqualTo(0));
        expect(box.bottom, lessThanOrEqualTo(safeBottom));
      }
      final figure = t.getSize(find.byType(PointScene)).height;
      expect(figure, lessThan(208));
      expect(figure, greaterThanOrEqualTo(64));

      await t.tap(restore);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('at /seed-restore'), findsOneWidget);
    });
  }

  testWidgets('on an upright phone the welcome figure keeps its full height', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 932);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const WelcomePilotScreen()));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(PointScene)).height, 208);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  test('the lattice is a cube of nodes joined along its three axes', () {
    final lattice = PointField.lattice(perAxis: 6);
    expect(lattice.count, 216);
    expect(lattice.hasEdges, isTrue);
    expect(lattice.reach, greaterThan(0));
    expect(PointField.mark().hasEdges, isFalse);
  });

  testWidgets(
    'a scene paints both figures, thrown and settled, without error',
    (t) async {
      final scatter = ValueNotifier(0.0);
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              SizedBox(
                height: 200,
                width: 300,
                child: PointScene(
                  field: PointField.mark(),
                  scatter: scatter,
                  scan: true,
                ),
              ),
              SizedBox(
                height: 200,
                width: 300,
                child: PointScene(
                  field: PointField.lattice(),
                  scatter: scatter,
                ),
              ),
            ],
          ),
        ),
      );
      for (final thrown in [0.0, 2.4, 7.0, 0.0]) {
        scatter.value = thrown;
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull, reason: 'scatter $thrown');
      }
      await t.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('the lock scans its mark only while the device checks the '
      'credential', (t) async {
    final auth = _HeldAuth();
    await t.pumpWidget(_app(const LockPilotScreen(), auth: auth));
    await t.pump();
    expect(_painter(t).scan, isFalse, reason: 'before the prompt');
    expect(_painter(t).field.hasEdges, isFalse, reason: 'the mark');
    await t.pump(const Duration(milliseconds: 500)); // the prompt's settle
    await t.pump();
    expect(find.text('AUTHENTICATING'), findsOneWidget);
    expect(_painter(t).scan, isTrue);

    auth.answer.complete(AuthOutcome.failed);
    await t.pump();
    await t.pump();
    expect(find.text('AUTHENTICATION FAILED'), findsOneWidget);
    expect(_painter(t).scan, isFalse);
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 11));
  });

  testWidgets('Activate bursts the lattice and brings it back to rest', (
    t,
  ) async {
    final wallet = _HeldWallet();
    await t.pumpWidget(_app(const CreateAccountPilotScreen(), wallet: wallet));
    await t.pump();
    final painter = _painter(t);
    expect(painter.field.hasEdges, isTrue, reason: 'the lattice');
    expect(painter.scatter!.value, 0, reason: 'at rest before Activate');

    await t.enterText(find.byType(TextField), 'Personal');
    await t.tap(find.text('ACTIVATE'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 750));
    expect(find.text('GENERATING KEYS'), findsOneWidget);
    expect(_painter(t).scatter!.value, greaterThan(2), reason: 'thrown apart');
    await t.pump(const Duration(milliseconds: 800));
    expect(_painter(t).scatter!.value, closeTo(0, 1e-9), reason: 'in order');

    wallet.done.complete();
    await t.pump();
    await t.pump();
    expect(find.text('at /seed-backup'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('under reduced motion each figure is one still frame', (t) async {
    for (final screen in const <Widget>[
      LockPilotScreen(),
      CreateAccountPilotScreen(),
    ]) {
      await t.pumpWidget(_app(screen, auth: _HeldAuth(), reduced: true));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(_painter(t).still, isTrue, reason: '${screen.runtimeType}');
      final held = _painter(t).clock.value;
      await t.pump(const Duration(milliseconds: 200));
      expect(_painter(t).clock.value, held, reason: 'the clock is stopped');
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 11));
    }
  });
}
