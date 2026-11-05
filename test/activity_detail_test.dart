// Tapping an Activity row opens that transaction's detail sheet. The first
// cases are the attacks: a hash from the history service that is not 64 hex
// characters never becomes an explorer link (the service is remote, so the
// hash is data until it is checked), and a Stagenet row gets no link, since
// no public explorer reads Stagenet. Then the sheet: the amount to the
// satoshi where the row rounds (to the cent from 2^26 SOQ), the full hash,
// the copy action and the explorer button.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/router.dart';
import 'package:soqushield/screens/activity/activity_detail_sheet.dart';
import 'package:soqushield/screens/activity/activity_pilot_screen.dart';
import 'package:soqushield/screens/shell.dart';
import 'package:soqushield/theme/app_theme.dart';
import 'package:soqushield/theme/fmt.dart';

import 'lite_test_support.dart';

const _txid =
    '824e36edbd426881285cfc3b78c8d2506014836aac4f539fd4c726b9b1f865f9';

WalletState _wallet(SoqNetwork network, {TxType type = TxType.received}) =>
    WalletState(
      network: network,
      isInitialized: true,
      backupConfirmed: true,
      recentTransactions: [
        WalletTransaction(
          txid: _txid,
          type: type,
          amount: 1234.56789012,
          timestamp: DateTime(2026, 10, 14, 23, 54),
        ),
      ],
    );

Widget _app(WalletState wallet) => ProviderScope(
      overrides: [
        // Shown balances, read from no storage: this file is about the sheet.
        quietDisplayPrefs,
        walletProvider.overrideWith(() => MockWalletNotifier(wallet)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ActivityPilotScreen(),
      ),
    );

Future<Finder> _openSheet(WidgetTester tester, WalletState wallet,
    {String row = 'Received'}) async {
  await tester.pumpWidget(_app(wallet));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
  return find.byType(ActivityDetailSheet);
}

void main() {
  group('the explorer link', () {
    test('a hash that is not 64 hex characters gets none', () {
      for (final hash in [
        '',
        '../../admin',
        _txid.substring(1),
        '${_txid}0',
        '${_txid.substring(1)}g',
        '${_txid.substring(0, 32)}/${_txid.substring(33)}',
        '$_txid?next=https://example.com',
        ' $_txid',
        '$_txid\n',
      ]) {
        expect(explorerTxUrl(hash, SoqNetwork.mainnet), isNull,
            reason: 'hash "$hash"');
      }
    });

    test('a Stagenet hash gets none: no public explorer reads Stagenet', () {
      expect(explorerTxUrl(_txid, SoqNetwork.stagenet), isNull);
    });

    test('a Mainnet hash links to its page on the explorer', () {
      final page = Uri.parse('https://explorer.soqu.org/tx/$_txid');
      expect(explorerTxUrl(_txid, SoqNetwork.mainnet), page);
      expect(explorerTxUrl(_txid.toUpperCase(), SoqNetwork.mainnet), page);
    });
  });

  testWidgets('tapping a row opens its detail sheet', (tester) async {
    final sheet = await _openSheet(tester, _wallet(SoqNetwork.mainnet));
    expect(sheet, findsOneWidget);

    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet('RECEIVED'), findsOneWidget);
    // The row rounds an amount of 1,000 or more to whole SOQ; the sheet
    // shows it to the satoshi.
    expect(find.text('+1235 SOQ'), findsOneWidget);
    expect(inSheet('+1,234.56789012'), findsOneWidget);
    expect(inSheet('SOQ'), findsOneWidget);
    expect(inSheet('OCT 14, 2026'), findsOneWidget);
    expect(inSheet('MAINNET'), findsOneWidget);
    expect(inSheet(_txid), findsOneWidget);
    expect(inSheet('COPY HASH'), findsOneWidget);
    expect(inSheet('VIEW ON EXPLORER'), findsOneWidget);
    expect(tester.widget<ActivityDetailSheet>(sheet).explorerUrl,
        Uri.parse('https://explorer.soqu.org/tx/$_txid'));
  });

  testWidgets('a sent row reads as sent', (tester) async {
    final sheet = await _openSheet(
        tester, _wallet(SoqNetwork.mainnet, type: TxType.sent),
        row: 'Sent');
    expect(find.descendant(of: sheet, matching: find.text('SENT')),
        findsOneWidget);
    expect(
        find.descendant(of: sheet, matching: find.text('−1,234.56789012')),
        findsOneWidget);
  });

  testWidgets('a Stagenet row opens the sheet with no explorer button',
      (tester) async {
    final sheet = await _openSheet(tester, _wallet(SoqNetwork.stagenet));
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('STAGENET')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('tSOQ')),
        findsOneWidget);
    expect(find.text('VIEW ON EXPLORER'), findsNothing);
    expect(find.text('COPY HASH'), findsOneWidget);
    expect(find.text('+1235 tSOQ'), findsOneWidget,
        reason: 'the row names the same ticker as its sheet');
  });

  test('the amount is to the satoshi below 2^26 SOQ and to the cent from it',
      () {
    expect(fmtDetailAmount(67108863.99999999), '67,108,863.99999999');
    expect(fmtDetailAmount(kSatoshiExactLimit), '67,108,864.00');
    // 6,710,951,716,303,400 shors as the history sync builds it: a double
    // cannot hold .16303400 at this size, so the sheet does not claim it.
    expect(fmtDetailAmount(6710951716303400 / 100000000.0), '67,109,517.16');
    expect(fmtDetailAmount(19999999999.12345678), '19,999,999,999.12');
  });

  testWidgets('in the app the sheet covers the tab bar: a tap on the Wallet '
      'tab lands on the sheet and stays on Activity', (tester) async {
    router.go('/activity');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        walletProvider.overrideWith(
            () => MockWalletNotifier(_wallet(SoqNetwork.mainnet))),
      ],
      child: MaterialApp.router(
          theme: AppTheme.darkTheme, routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Received'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActivityDetailSheet), findsOneWidget);
    // Outside the shell's column the sheet takes the column's width limit
    // (the test surface is 800 wide; the sheet's own default limit is 640).
    expect(tester.getSize(find.byType(ActivityDetailSheet)).width,
        lessThanOrEqualTo(kShellMaxWidth));

    // The Wallet tab is under the sheet: the tap lands on the sheet and does
    // not leave Activity. On the shell's navigator the tab stays tappable.
    await tester.tapAt(tester.getCenter(find.text('Wallet')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActivityDetailSheet), findsOneWidget);
    expect(find.byType(ActivityPilotScreen), findsOneWidget);

    // A tap on the barrier above the sheet closes it, still on Activity.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ActivityDetailSheet), findsNothing);
    expect(find.byType(ActivityPilotScreen), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('COPY HASH copies the whole hash and says so on the button',
      (tester) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _openSheet(tester, _wallet(SoqNetwork.mainnet));
    await tester.tap(find.text('COPY HASH'));
    await tester.pump();
    expect(copied, _txid);
    expect(find.text('COPIED'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('COPY HASH'), findsOneWidget);
  });
}
