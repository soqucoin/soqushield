/// SoquShield real-flow drive — Tier 2 (the REAL app, real providers, real
/// keychain and FFI, live endpoints), on a simulator or emulator.
///
/// Walks the lite wallet as a holder would: create, back up the phrase, the
/// disclosure, the wallet home on Mainnet, Receive, Settings, a switch to
/// Stagenet, Activity, Help, a wipe, and a restore from the canonical 24 words
/// that must give the known-answer mainnet address. Each step prints
/// `MARK <name>` and pauses so a host loop can take a screenshot.
///
/// Needs a screen lock on the device (the app requires one to create a
/// wallet): `adb shell locksettings set-pin 1234` on an emulator, Face ID
/// enrolled on an iOS simulator. No biometric prompt is crossed in this drive.
///
/// ⛔ START FROM A DEVICE WITH NO WALLET. The drive opens on the create path,
/// and the iOS keychain OUTLIVES an app uninstall — a simulator that has run
/// this before boots straight into the wallet it already has, and the drive
/// fails on the welcome screen it never sees. Erase it first:
///
///   `xcrun simctl shutdown ID && xcrun simctl erase ID && xcrun simctl boot ID`
///   `xcrun simctl spawn ID notifyutil -s com.apple.BiometricKit.enrollmentChanged 1`
///
/// (the second line re-enrols Face ID, which the erase takes with it).
///
/// Run: flutter test integration_test/real_flow_test.dart -d `<device>`
/// Android captures need `--dart-define=SOQUSHIELD_CAPTURE=true` as well: a
/// debug build then lifts FLAG_SECURE for the run, a release build refuses.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:soqushield/main.dart' show SoquShieldApp;
import 'package:soqushield/screens/receive/receive_pilot_screen.dart';

const _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon art';
const _katMainnet =
    'sq1p3j6nd46xrh8vl8ac86x8sm4dlynv95ckpyn5y4d46kte8js05k2qarf5vn';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFor(WidgetTester t, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pump until [finder] matches, up to [limit]; fails with the finder's name.
  Future<void> until(WidgetTester t, Finder finder,
      {Duration limit = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(limit);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    expect(finder, findsWidgets, reason: 'timed out waiting for $finder');
  }

  // Four seconds on every mark: the host's capture (about a second on the
  // simulator) plus the log's latency must fit inside the pause, or the loop
  // falls behind and captures the next step.
  Future<void> mark(WidgetTester t, String name,
      [Duration pause = const Duration(seconds: 4)]) async {
    await t.pump(const Duration(milliseconds: 200));
    // ignore: avoid_print
    print('MARK $name');
    await pumpFor(t, pause);
  }

  Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
    final f = find.text(text);
    await until(t, f);
    await t.tap(last ? f.last : f.first);
    await t.pump(const Duration(milliseconds: 300));
  }

  /// Drop focus and let the software keyboard go.
  ///
  /// ⛔ Call this after the last [WidgetTester.enterText] on a screen, before
  /// tapping anything below the field. The keyboard is a real view on a real
  /// device: it covers the lower half of the screen, and a tap aimed at a
  /// button under it lands on the keyboard instead. The form scrolls, so a
  /// holder simply scrolls the button up — the drive has to say so.
  Future<void> dismissKeyboard(WidgetTester t) async {
    FocusManager.instance.primaryFocus?.unfocus();
    // The keyboard animates out over about 250ms, and the scroll view
    // reflows behind it. Pump past both before anything is tapped.
    await pumpFor(t, const Duration(milliseconds: 700));
  }

  Future<void> openDrawerItem(WidgetTester t, String label) async {
    await tapText(t, 'More');
    await pumpFor(t, const Duration(milliseconds: 600));
    await tapText(t, label);
    await pumpFor(t, const Duration(milliseconds: 800));
  }

  Future<void> back(WidgetTester t) async {
    // The instrument screens use the rounded arrow; the Field Manual the plain one.
    final f = find.byWidgetPredicate((w) =>
        w is Icon && (w.icon == Icons.arrow_back_rounded || w.icon == Icons.arrow_back));
    await until(t, f);
    await t.tap(f.first);
    await pumpFor(t, const Duration(milliseconds: 800));
  }

  testWidgets('the lite wallet, end to end on a device', (t) async {
    // Android: the app's FLAG_SECURE blacks out every capture. Started with
    // --dart-define=SOQUSHIELD_CAPTURE=true, the drive asks the activity to
    // lift it; only a debuggable build does, a release build answers false.
    if (!kIsWeb &&
        Platform.isAndroid &&
        const bool.fromEnvironment('SOQUSHIELD_CAPTURE')) {
      final lifted = await const MethodChannel('org.soqu.soqushield/capture')
          .invokeMethod<bool>('allowCapture');
      // ignore: avoid_print
      print('CAPTURE ${lifted == true ? 'allowed' : 'refused'}');
    }

    // ⛔ A tap that misses is FATAL here. Flutter only warns when the offset
    // it derives does not hit the widget, so the drive used to sail past a
    // missed tap and then wait out every later `until` on a screen it never
    // left — minutes of silence ending in an error naming the wrong step.
    // Failing at the tap names the step that actually went wrong.
    WidgetController.hitTestWarningShouldBeFatal = true;

    // The app's root widget, not main(): main() wraps runApp in its own zone
    // and error boundary, which the test binding refuses.
    await t.pumpWidget(const ProviderScope(child: SoquShieldApp()));
    await until(t, find.text('CREATE A WALLET'), limit: const Duration(seconds: 30));
    await mark(t, 'welcome');

    // ── create ──
    await tapText(t, 'CREATE A WALLET');
    await until(t, find.text('ACTIVATE'));
    await t.enterText(find.byType(TextField).first, 'Review');
    await mark(t, 'create');
    // ACTIVATE sits below the field, under the open keyboard.
    await dismissKeyboard(t);
    await tapText(t, 'ACTIVATE');

    // ── seed backup (keygen runs first) ──
    await until(t, find.text('Tap to reveal recovery phrase'), limit: const Duration(seconds: 60));
    await mark(t, 'seed-hidden');
    await tapText(t, 'Tap to reveal recovery phrase');
    await until(t, find.text('COPY ALL'));
    await mark(t, 'seed-revealed');
    await tapText(t, 'I have written down my recovery phrase and stored it securely');
    await tapText(t, 'CONTINUE');

    // ── disclosure ──
    await until(t, find.text('Important Information'));
    await mark(t, 'disclosure');
    await tapText(t, 'I UNDERSTAND — CONTINUE');

    // ── home on Mainnet: the badge, the address, OFFLINE ──
    await until(t, find.text('SEND'));
    await until(t, find.text('MAINNET'));
    // Mainnet answers since 2026-10-13, so a connected device reads LIVE
    // and a device without the network reads OFFLINE; the drive accepts
    // either and asserts the waiting lines only when offline.
    // The header reads SYNCING while the first poll runs; wait for one of
    // the two settled states. Each screen carries its own header, so the
    // branch is decided on the screen whose lines are asserted.
    final settled = find.byWidgetPredicate((w) =>
        w is Text &&
        (w.data == 'SOQUCOIN · ML-DSA-44 · LIVE' ||
            w.data == 'SOQUCOIN · ML-DSA-44 · OFFLINE'));
    await until(t, settled, limit: const Duration(seconds: 40));
    expect(find.textContaining('sq1'), findsWidgets);
    await mark(t, 'home-mainnet');

    // ── network on Mainnet: the cards closed with their lines, the pool
    // card waiting when offline; the emission card opened ──
    await tapText(t, 'Network');
    await until(t, find.text('100,000 SOQ A BLOCK AT GENESIS'));
    await until(t, settled, limit: const Duration(seconds: 40));
    final offline = find.text('SOQUCOIN · ML-DSA-44 · OFFLINE').evaluate().isNotEmpty;
    if (offline) {
      await until(t, find.textContaining('Connecting to Mainnet'), limit: const Duration(seconds: 40));
      await until(t, find.text('WAITING FOR THE NETWORK'));
    }
    await t.tap(find.byKey(const ValueKey('card emission')));
    await until(t, find.text('BLOCK REWARD · GENESIS'));
    await mark(t, 'network-mainnet');
    await tapText(t, 'Wallet');
    await until(t, find.text('SEND'));

    // ── receive ──
    await tapText(t, 'RECEIVE');
    await until(t, find.text('COPY ADDRESS'));
    final qr = t.widget<ReceiveQr>(find.byType(ReceiveQr));
    expect(qr.data.startsWith('sq1'), isTrue, reason: 'the QR is the bare mainnet address');
    expect(find.text(qr.data), findsOneWidget, reason: 'the address row shows the same string');
    await mark(t, 'receive-mainnet');
    await back(t);

    // ── send: the input screen only (no coins, no credential crossed) ──
    await tapText(t, 'SEND');
    await until(t, find.text('SEND SOQ'));
    await mark(t, 'send-mainnet');
    await back(t);

    // ── settings: switch to Stagenet ──
    await until(t, find.text('SEND'));
    await openDrawerItem(t, 'Settings');
    await until(t, find.text('SETTINGS'));
    await mark(t, 'settings-mainnet');
    await t.tap(find.text('Mainnet').first);
    await pumpFor(t, const Duration(milliseconds: 600));
    await tapText(t, 'Stagenet', last: true);
    await until(t, find.textContaining('begins ssq1'), limit: const Duration(seconds: 30));
    await mark(t, 'settings-stagenet');
    await back(t);

    // ── home on Stagenet: LIVE with a height ──
    await until(t, find.text('STAGENET'));
    await until(t, find.text('SOQUCOIN · ML-DSA-44 · LIVE'), limit: const Duration(seconds: 60));
    await mark(t, 'home-stagenet');

    // ── network on Stagenet: the block clock live, the weather in words,
    // the pool's status on its closed card, then the pool card opened ──
    // (the clock's own labels are painted, not widgets; the status line, the
    // card labels and the pool's state are texts)
    await tapText(t, 'Network');
    await until(t, find.text('CHAIN · STAGENET'));
    await until(t, find.text('SOQUCOIN · ML-DSA-44 · LIVE'), limit: const Duration(seconds: 60));
    await until(t, find.text('OPERATIONAL'), limit: const Duration(seconds: 60));
    await until(t, find.textContaining('SOQUPOOL is operational'));
    await t.tap(find.byKey(const ValueKey('card pool')));
    await until(t, find.text('POOL HASHRATE'));
    await mark(t, 'network-stagenet');
    await tapText(t, 'Wallet');
    await until(t, find.text('SEND'));

    // ── send on Stagenet: the input screen with a live fee estimate ──
    await tapText(t, 'SEND');
    await until(t, find.text('SEND TSOQ')); // the stagenet ticker
    await mark(t, 'send-stagenet');
    await back(t);
    await until(t, find.text('SEND'));

    // ── receive on Stagenet ──
    await tapText(t, 'RECEIVE');
    await until(t, find.text('COPY ADDRESS'));
    expect(t.widget<ReceiveQr>(find.byType(ReceiveQr)).data.startsWith('ssq1'), isTrue);
    await mark(t, 'receive-stagenet');
    await back(t);

    // ── activity ──
    await tapText(t, 'Activity');
    await until(t, find.text('ACTIVITY'));
    await mark(t, 'activity');
    await tapText(t, 'Wallet');

    // ── help ──
    await openDrawerItem(t, 'Help');
    await until(t, find.text('FIELD MANUAL'));
    await mark(t, 'guide');
    await tapText(t, 'Mainnet and Stagenet');
    await until(t, find.text('Which network you are on, and what opens when.'));
    await mark(t, 'guide-article');
    await back(t);
    await back(t);

    // ── wipe ──
    await until(t, find.text('SEND'));
    await openDrawerItem(t, 'Settings');
    await until(t, find.text('SETTINGS'));
    // The settings list builds lazily: scroll until the row exists.
    await t.scrollUntilVisible(find.text('Wipe wallet'), 300,
        scrollable: find.byType(Scrollable).first);
    await pumpFor(t, const Duration(milliseconds: 500));
    await tapText(t, 'Wipe wallet');
    await until(t, find.text('WIPE WALLET'));
    await mark(t, 'wipe-dialog');
    await tapText(t, 'WIPE WALLET');
    await until(t, find.text('CREATE A WALLET'), limit: const Duration(seconds: 30));
    await mark(t, 'welcome-after-wipe');

    // ── restore the canonical words: the known-answer mainnet address ──
    await tapText(t, 'I ALREADY HAVE A WALLET');
    await until(t, find.text('Restore Wallet'));
    final words = _mnemonic.split(' ');
    for (var i = 0; i < 24; i++) {
      // The grid builds lazily on smaller screens: bring the cell into view,
      // then type into the field beside its number.
      final label = find.text('${i + 1}');
      await t.scrollUntilVisible(label, 150, scrollable: find.byType(Scrollable).first);
      final field = find.descendant(
          of: find.ancestor(of: label, matching: find.byType(Row)),
          matching: find.byType(TextField));
      await t.enterText(field.first, words[i]);
    }
    await mark(t, 'restore-filled');
    await tapText(t, 'RESTORE WALLET'); // the button; the title is title-case
    await until(t, find.text('Important Information'), limit: const Duration(seconds: 60));
    await tapText(t, 'I UNDERSTAND — CONTINUE');
    await until(t, find.text('SEND'));
    await until(t, find.text('MAINNET'));
    await tapText(t, 'RECEIVE');
    await until(t, find.text('COPY ADDRESS'));
    expect(t.widget<ReceiveQr>(find.byType(ReceiveQr)).data, _katMainnet,
        reason: 'the canonical 24 words give the known-answer mainnet address');
    await mark(t, 'restored-kat');
    // ignore: avoid_print
    print('MARK done');
  });
}
