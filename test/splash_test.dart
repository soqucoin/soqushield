// The splash: the Soqucoin mark assembles out of points, the text follows it
// in, and the screen routes by auth status at the same moment it always did.
// Under reduced motion it is one still frame with nothing left to animate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/screens/splash_pilot_screen.dart';
import 'package:soqushield/theme/point_scene.dart';
import 'package:soqushield/theme/mark_points.dart';

import 'lite_test_support.dart';

const _lines = [
  'SOQUSHIELD',
  'SELF-CUSTODIAL · POST-QUANTUM',
  'ML-DSA-44 · FIPS 204',
];

GoRouter _router() => GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashPilotScreen()),
    for (final p in ['/', '/lock', '/welcome'])
      GoRoute(path: p, builder: (_, _) => Text('at $p')),
  ],
);

Widget _app(
  GoRouter router,
  AuthStatus status, {
  ValueNotifier<bool>? reduced,
}) => ProviderScope(
  overrides: [authProvider.overrideWith(() => MockAuthNotifier(status))],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => ValueListenableBuilder<bool>(
      valueListenable: reduced ?? ValueNotifier(false),
      builder: (context, r, _) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: r),
        child: child!,
      ),
    ),
  ),
);

double _opacity(WidgetTester t, String line) => t
    .widget<Opacity>(
      find.ancestor(of: find.text(line), matching: find.byType(Opacity)).first,
    )
    .opacity;

PointScenePainter _painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<PointScenePainter>()
    .single;

Future<void> _leave(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 6)); // the splash's own delays
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the mark is 2,000 distinct points on its grid', () {
    expect(kMarkPoints.length, 4000);
    final seen = <int>{};
    for (var i = 0; i < kMarkPoints.length; i += 2) {
      seen.add(kMarkPoints[i] * kMarkGrid + kMarkPoints[i + 1]);
    }
    expect(seen.length, 2000);
    expect(PointField.mark().count, 2000);
    expect(PointField.mark(count: 500).count, 500);
    expect(PointField.mark(count: 9000).count, 2000);
  });

  test('the assembly runs from scattered to whole and stays whole', () {
    expect(PointScenePainter.assemblyAt(0), 0);
    var last = 0.0;
    for (var s = 0.1; s <= 3; s += 0.1) {
      final a = PointScenePainter.assemblyAt(s);
      expect(a, greaterThanOrEqualTo(last));
      last = a;
    }
    expect(
      PointScenePainter.assemblyAt(PointScenePainter.assembleSeconds),
      1,
    );
    expect(PointScenePainter.assemblyAt(60), 1);
  });

  testWidgets('the mark gathers first, the text follows, and the mark is '
      'whole before the splash routes', (t) async {
    await t.pumpWidget(_app(_router(), AuthStatus.locked));
    await t.pump();
    expect(_painter(t).still, isFalse);
    for (final line in _lines) {
      expect(_opacity(t, line), 0, reason: '$line waits for the mark');
    }
    await t.pump(const Duration(milliseconds: 2300));
    for (final line in _lines) {
      expect(_opacity(t, line), 1, reason: '$line is in');
    }
    expect(PointScenePainter.assemblyAt(_painter(t).clock.value), 1);
    expect(find.text('at /lock'), findsNothing, reason: 'not before 2.5 s');
    expect(t.takeException(), isNull);
    await _leave(t);
  });

  for (final (status, path) in [
    (AuthStatus.noAccount, '/welcome'),
    (AuthStatus.locked, '/lock'),
    (AuthStatus.authenticated, '/'),
  ]) {
    testWidgets('$status leaves the splash for $path at 2.5 s', (t) async {
      await t.pumpWidget(_app(_router(), status));
      await t.pump(const Duration(milliseconds: 2400));
      expect(find.byType(SplashPilotScreen), findsOneWidget);
      await t.pump(const Duration(milliseconds: 200));
      await t.pump();
      expect(find.text('at $path'), findsOneWidget);
      await _leave(t);
    });
  }

  testWidgets('reduced motion shows the finished frame at once and animates '
      'nothing', (t) async {
    await t.pumpWidget(
      _app(_router(), AuthStatus.locked, reduced: ValueNotifier(true)),
    );
    await t.pump();
    expect(_painter(t).still, isTrue);
    for (final line in _lines) {
      expect(_opacity(t, line), 1);
    }
    final at = _painter(t).clock.value;
    await t.pump(const Duration(milliseconds: 500));
    expect(_painter(t).clock.value, at, reason: 'the clock is stopped');
    await t.pump(const Duration(milliseconds: 2100));
    await t.pump();
    expect(find.text('at /lock'), findsOneWidget, reason: 'it still routes');
    await _leave(t);
  });

  testWidgets('reduced motion switched on and off during the splash holds '
      'the finished frame, then lets it move again', (t) async {
    final reduced = ValueNotifier(false);
    await t.pumpWidget(_app(_router(), AuthStatus.locked, reduced: reduced));
    await t.pump(const Duration(milliseconds: 300));
    expect(_opacity(t, 'SOQUSHIELD'), 0);

    reduced.value = true;
    await t.pump();
    expect(_painter(t).still, isTrue);
    expect(_opacity(t, 'SOQUSHIELD'), 1);
    final held = _painter(t).clock.value;
    await t.pump(const Duration(milliseconds: 100));
    expect(_painter(t).clock.value, held, reason: 'the clock is stopped');

    reduced.value = false;
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(_painter(t).still, isFalse);
    expect(_opacity(t, 'SOQUSHIELD'), 1, reason: 'the mark does not regather');
    final moving = _painter(t).clock.value;
    await t.pump(const Duration(milliseconds: 100));
    expect(_painter(t).clock.value, greaterThan(moving));
    expect(t.takeException(), isNull);
    await _leave(t);
  });

  testWidgets('every line fits a narrow phone at the largest text size', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(_app(_router(), AuthStatus.locked));
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
    for (final line in _lines) {
      final box = t.getRect(find.text(line));
      expect(box.left, greaterThanOrEqualTo(0), reason: line);
      expect(box.right, lessThanOrEqualTo(320), reason: line);
    }
    final mark = _painter(t).frame;
    expect(t.getRect(find.text('SOQUSHIELD')).top, greaterThan(mark.bottom));
    await _leave(t);
  });
}
