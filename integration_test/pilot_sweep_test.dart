/// SoquShield screen sweep — Tier 1 (Automated, mocked auth/wallet RPC).
///
/// Renders every screen the live app routes an authenticated user to and
/// asserts each mounts without throwing — the class of bug that device-verify
/// surfaces (a RangeError and a disposed-ref crash that only showed at
/// runtime, not in `flutter analyze`).
///
/// Run: flutter test integration_test/pilot_sweep_test.dart -d `<device>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Every screen reachable by an authenticated user on the real router
  // (onboarding/lock surfaces need other auth states and are covered in e2e_test).
  const routes = <String, String>{
    '/': 'Wallet / home (custody line)',
    '/send': 'Send',
    '/receive': 'Receive',
    '/activity': 'Activity',
    '/settings': 'Settings',
    '/guide': 'Field Manual',
    '/guide/send': 'Field Manual article',
  };

  group('Screen sweep — every authenticated screen mounts cleanly', () {
    routes.forEach((route, label) {
      testWidgets('$label  [$route]', (tester) async {
        await tester.pumpWidget(buildTestApp(initialRoute: route));
        await tester.pumpSteady();

        // No uncaught exception during build / layout / paint / timers.
        expect(tester.takeException(), isNull,
            reason: '$label threw during render');
        // Actually rendered a surface (not a blank/error fallback).
        expect(find.byType(Scaffold), findsWidgets,
            reason: '$label produced no Scaffold');
      });
    });
  });
}
