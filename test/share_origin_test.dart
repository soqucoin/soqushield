// The share sheet's anchor. The app ships to iPads (device family 1,2), and
// there the sheet is a popover: the plugin refuses to open one without the
// rectangle of the control that raised it, so every share call passes it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/receive/receive_pilot_screen.dart';
import 'package:soqushield/theme/instrument.dart';

import 'lite_test_support.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _mainnetAddress =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

WalletState _wallet() => WalletState(
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _mainnetAddress,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: SoqNetwork.mainnet,
      backupConfirmed: true,
      isInitialized: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the share sheet anchor', () {
    testWidgets('shareOriginOf is the control\'s rectangle on the screen',
        (tester) async {
      late BuildContext control;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          Positioned(
            left: 40,
            top: 100,
            width: 120,
            height: 36,
            child: Builder(builder: (c) {
              control = c;
              return const SizedBox.expand();
            }),
          ),
        ]),
      ));
      expect(shareOriginOf(control), const Rect.fromLTWH(40, 100, 120, 36));
    });

    testWidgets('the Receive chip raises the sheet anchored to itself, on '
        'an iPad surface', (tester) async {
      tester.view.physicalSize = const Size(1024, 1366) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_shareChannel, (call) async {
        calls.add(call);
        return 'dev.fluttercommunity.plus/share/success';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_shareChannel, null));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sessionProvider.overrideWith(MockSessionNotifier.new),
          walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        ],
        child: const MaterialApp(home: ReceivePilotScreen()),
      ));
      await tester.pump();

      final chip = find.widgetWithText(InstrumentActionChip, 'SHARE ADDRESS');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'share');
      final args = calls.single.arguments as Map;
      expect(args['text'], _mainnetAddress);
      final rect = tester.getRect(chip);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(args['originX'], rect.left);
      expect(args['originY'], rect.top);
      expect(args['originWidth'], rect.width);
      expect(args['originHeight'], rect.height);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('the backup export anchors its sheet to the row that opened it', () {
      final settings =
          File('lib/screens/settings/settings_pilot_screen.dart').readAsStringSync();
      expect(settings, contains('_showExportDialog(shareOriginOf(row))'));
      expect(settings, contains('sharePositionOrigin: shareOrigin'));
    });
  });
}
