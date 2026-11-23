// The send screen's scanner: the icon beside the address field opens it and
// the address it reads lands in the field; a scanner that reads nothing
// leaves the field alone; the sheet keeps looking past a refused code and
// closes on the first accepted address; the camera is declared on both
// platforms alongside the dependency; and the Field Manual names the icon.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/guide/guide_content.dart';
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/screens/send/scan_address_sheet.dart';
import 'package:soqushield/screens/send/send_pilot_screen.dart';
import 'package:soqushield/services/address_scan.dart';

import 'lite_test_support.dart';

const _mainnet =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';
const _stagenet =
    'ssq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qvft6ee';

WalletState _wallet() => WalletState(
      balance: 5,
      blockHeight: 100,
      keys: WalletKeys(
        publicKey: Uint8List(WalletKeys.pubKeySize),
        address: _mainnet,
        derivationPath: "m/44'/21329'/0'/0/0",
        accountIndex: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
      network: SoqNetwork.mainnet,
      backupConfirmed: true,
      isInitialized: true,
      isLoading: false,
    );

Widget _scoped(Widget child, {List<dynamic> extra = const []}) =>
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(FakeAuthService()),
        sessionProvider.overrideWith(MockSessionNotifier.new),
        quietDisplayPrefs,
        quietPrice,
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        ...extra,
      ],
      child: MaterialApp(home: child),
    );

/// Replace the tree so every provider is disposed, then drain the timers the
/// send screen arms.
Future<void> _tearDownTree(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump(const Duration(minutes: 1));
}

String _recipient(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text;

String _read(String path) => File(path).readAsStringSync();

/// The line under the sheet's picture: the hint, or a refused code's reason.
String _line(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('scan-line'))).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('the send screen', () {
    testWidgets('opens the scanner for the wallet\'s network from the icon '
        'in the address field, and the address it reads lands there',
        (tester) async {
      final asked = <SoqNetwork?>[];
      await tester.pumpWidget(_scoped(const SendPilotScreen(), extra: [
        scanAddressProvider.overrideWithValue((context, network) async {
          asked.add(network);
          return _mainnet;
        }),
      ]));
      await tester.pump();
      expect(find.byKey(const Key('send-scan')), findsOneWidget);
      expect(_recipient(tester), isEmpty);
      await tester.tap(find.byKey(const Key('send-scan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked, [SoqNetwork.mainnet]);
      expect(_recipient(tester), _mainnet);
      // Two fields still: the amount and the address.
      expect(find.byType(TextField), findsNWidgets(2));
      await _tearDownTree(tester);
    });

    testWidgets('a scanner that reads nothing leaves the field as it was',
        (tester) async {
      await tester.pumpWidget(_scoped(const SendPilotScreen(), extra: [
        scanAddressProvider.overrideWithValue((context, network) async => null),
      ]));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'sq1typed');
      await tester.tap(find.byKey(const Key('send-scan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_recipient(tester), 'sq1typed');
      await _tearDownTree(tester);
    });
  });

  group('the scan sheet', () {
    testWidgets('keeps looking past a refused code, with its reason shown, '
        'and closes on the first accepted address', (tester) async {
      String? result;
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened++;
                result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ScanAddressSheet(
                    network: SoqNetwork.mainnet,
                    camera: (_, onRaw) => Column(children: [
                      TextButton(
                          key: const Key('code-stagenet'),
                          onPressed: () => onRaw(_stagenet),
                          child: const Text('stagenet')),
                      TextButton(
                          key: const Key('code-link'),
                          onPressed: () => onRaw('https://example.org/pay'),
                          child: const Text('link')),
                      TextButton(
                          key: const Key('code-mainnet'),
                          onPressed: () => onRaw('soqucoin:$_mainnet?amount=9'),
                          child: const Text('mainnet')),
                    ]),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('SCAN ADDRESS'), findsOneWidget);
      expect(find.text(ScanAddressSheet.hint), findsOneWidget);

      await tester.tap(find.byKey(const Key('code-stagenet')));
      await tester.pump();
      expect(find.byType(ScanAddressSheet), findsOneWidget,
          reason: 'a refused code does not close the sheet');
      expect(_line(tester), contains('stagenet'));
      expect(result, isNull);

      await tester.tap(find.byKey(const Key('code-link')));
      await tester.pump();
      expect(_line(tester), AddressScan.notAnAddress);
      expect(find.byType(ScanAddressSheet), findsOneWidget);

      await tester.tap(find.byKey(const Key('code-mainnet')));
      await tester.pumpAndSettle();
      expect(find.byType(ScanAddressSheet), findsNothing);
      expect(result, _mainnet, reason: 'the address, without the amount');
    });

    testWidgets('a code read while the sheet is on its way out pops nothing '
        'under it', (tester) async {
      String? result = 'unset';
      void Function(String raw)? emit;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ScanAddressSheet(
                    network: SoqNetwork.mainnet,
                    camera: (_, onRaw) {
                      emit = onRaw;
                      return const SizedBox.expand();
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The close control, then a detection before the next frame: the
      // sheet is already on its way out.
      await tester.tap(find.byKey(const Key('scan-close')));
      emit!(_mainnet);
      await tester.pumpAndSettle();
      expect(find.byType(ScanAddressSheet), findsNothing);
      expect(find.text('open'), findsOneWidget,
          reason: 'the page under the sheet is still there');
      expect(result, isNull, reason: 'the dismissal answered, not the code');
    });

    testWidgets('closes empty from its close control', (tester) async {
      String? result = 'unset';
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ScanAddressSheet(
                    network: SoqNetwork.mainnet,
                    camera: (_, _) => const SizedBox.expand(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan-close')));
      await tester.pumpAndSettle();
      expect(find.byType(ScanAddressSheet), findsNothing);
      expect(result, isNull);
    });
  });

  group('the scan sheet on a device', () {
    Future<void> openSheet(WidgetTester tester,
        {MobileScannerController? controller}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => ScanAddressSheet(
                  network: SoqNetwork.mainnet,
                  controller: controller,
                  camera: (_, _) => const SizedBox.expand(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('stops the camera when the app goes inactive and starts it '
        'on return', (tester) async {
      final camera = _RecordingCamera(permitted: true);
      await openSheet(tester, controller: camera);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(camera.calls, ['stop', 'start']);

      await tester.tap(find.byKey(const Key('scan-close')));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(camera.calls, ['stop', 'start'],
          reason: 'a closed sheet no longer drives the camera');
    });

    testWidgets('without the camera permission a resume starts nothing',
        (tester) async {
      final camera = _RecordingCamera(permitted: false);
      await openSheet(tester, controller: camera);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(camera.calls, isEmpty);
    });

    testWidgets('fits a short phone in landscape, scrolling to its lower '
        'lines', (tester) async {
      tester.view.physicalSize = const Size(667, 375);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(left: 44, right: 44, bottom: 21);
      addTearDown(tester.view.reset);
      await openSheet(tester);
      expect(tester.takeException(), isNull,
          reason: 'the sheet scrolls instead of overflowing');
      await tester.ensureVisible(find.byKey(const Key('scan-line')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('scan-line')).hitTestable(), findsOneWidget);
    });
  });

  group('the camera is declared with the dependency', () {
    test('pubspec declares the scanner', () {
      expect(
          RegExp(r'^\s+mobile_scanner:', multiLine: true)
              .hasMatch(_read('pubspec.yaml')),
          isTrue);
    });

    test('Info.plist carries the camera usage description', () {
      final plist = _read('ios/Runner/Info.plist');
      expect(plist, contains('<key>NSCameraUsageDescription</key>'));
      expect(
          RegExp(r'<key>NSCameraUsageDescription</key>\s*<string>[^<]*QR code[^<]*</string>')
              .hasMatch(plist),
          isTrue,
          reason: 'the description says what the camera is for');
    });

    test('the Android manifest asks for the camera and does not require one',
        () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest,
          contains('<uses-permission android:name="android.permission.CAMERA" />'));
      expect(
          manifest,
          contains('<uses-feature android:name="android.hardware.camera" '
              'android:required="false" />'));
      // The camera permission implies autofocus too; Play filters on both.
      expect(
          manifest,
          contains('<uses-feature '
              'android:name="android.hardware.camera.autofocus" '
              'android:required="false" />'));
    });
  });

  group('the Field Manual', () {
    test('names the scan icon in the send steps', () {
      final send = guideArticleById('send')!;
      expect(
          send.sections.any((s) => s.steps.any((t) => t.contains('scan icon'))),
          isTrue);
    });
  });
}

/// A controller that records what the sheet asks of it and never touches a
/// camera.
class _RecordingCamera extends MobileScannerController {
  final calls = <String>[];

  _RecordingCamera({required bool permitted}) : super(autoStart: false) {
    value = const MobileScannerState.uninitialized()
        .copyWith(isInitialized: permitted);
  }

  @override
  Future<void> start(
      {CameraFacing? cameraDirection, CameraLensType? cameraLensType}) async {
    calls.add('start');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}
