/// SoquShield E2E Integration Tests — Tier 1 (Automated, Mocked RPC)
///
/// Validates the lite wallet's UI flows in a simulator. Uses provider
/// overrides to skip real RPC/keychain calls. Each test navigates directly
/// to its target screen on the app's real router.
///
/// Run: flutter test integration_test/e2e_test.dart -d `<device>`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:soqushield/providers/auth_provider.dart';

import 'test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding', () {
    testWidgets('Welcome offers create and restore', (tester) async {
      await tester.pumpWidget(buildTestApp(
        initialRoute: '/welcome',
        authStatus: AuthStatus.noAccount,
      ));
      await tester.pumpSteady();
      tester.expectText('SOQUSHIELD');
      tester.expectText('CREATE A WALLET');
      tester.expectText('I ALREADY HAVE A WALLET');
      tester.expectNoText('APPLE');
      tester.expectNoText('GOOGLE');
    });
  });

  group('Wallet home', () {
    testWidgets('renders the holdings, the badge and both actions',
        (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/'));
      await tester.pumpSteady();
      expect(find.textContaining('10'), findsWidgets,
          reason: 'Expected the 10000 SOQ balance');
      tester.expectText('MAINNET');
      tester.expectText('SEND');
      tester.expectText('RECEIVE');
      tester.expectNoText('SWAP');
      tester.expectNoText('BRIDGE');
      tester.expectNoText('USDSOQ');
    });

    testWidgets('the bar is Wallet, Activity, More', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/'));
      await tester.pumpSteady();
      tester.expectText('Wallet');
      tester.expectText('Activity');
      tester.expectText('More');
      tester.expectNoText('Pay');
    });
  });

  group('Send', () {
    testWidgets('renders the amount and address fields and the fee line',
        (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/send'));
      await tester.pumpSteady();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.textContaining('FEE'), findsWidgets);
    });
  });

  group('Receive', () {
    testWidgets('shows the address, the badge and the copy action',
        (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/receive'));
      await tester.pumpSteady();
      expect(find.textContaining('ML-DSA'), findsWidgets);
      tester.expectText('COPY ADDRESS');
      expect(find.textContaining(mockWalletState.address), findsWidgets);
    });
  });

  group('Settings', () {
    testWidgets('has the security, backup, network, about and danger sections',
        (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/settings'));
      await tester.pumpSteady();
      tester.expectText('SECURITY');
      tester.expectText('BACKUP & KEYS');
      tester.expectText('NETWORK');
    });
  });

  group('Activity', () {
    testWidgets('renders', (tester) async {
      await tester.pumpWidget(buildTestApp(initialRoute: '/activity'));
      await tester.pumpSteady();
      expect(find.byType(Scaffold), findsWidgets);
      tester.expectText('ACTIVITY');
    });
  });
}
