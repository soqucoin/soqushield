// The lock path, three facts the running app relied on and did not have:
// a lock is routed to the lock screen wherever the app is; a pause is a
// departure while an inactive state (a system overlay over the visible app)
// is not; and the app's own system UI (a biometric prompt, the share sheet),
// which pauses the activity on Android, locks nothing when it closes.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:soqushield/main.dart' show SoquShieldApp;
import 'package:soqushield/models/wallet_keys.dart';
import 'package:soqushield/providers/auth_provider.dart';
import 'package:soqushield/providers/network_provider.dart';
import 'package:soqushield/providers/session_provider.dart';
import 'package:soqushield/providers/wallet_provider.dart';
import 'package:soqushield/providers/weather_provider.dart';
import 'package:soqushield/router.dart';
import 'package:soqushield/screens/auth/lock_pilot_screen.dart';
import 'package:soqushield/screens/home/home_pilot_screen.dart';
import 'package:soqushield/services/weather_service.dart';

import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import 'package:soqushield/services/auth_service.dart';

import 'lite_test_support.dart';

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

/// An unlocked wallet whose locks are counted.
class _RecordingAuth extends MockAuthNotifier {
  int locks = 0;
  _RecordingAuth() : super(AuthStatus.authenticated);
  @override
  Future<void> lock() async {
    locks++;
    state = const AsyncData(AuthStatus.locked);
  }
}

/// A wallet whose key-cache clears are counted.
class _CountingWallet extends MockWalletNotifier {
  int clears = 0;
  _CountingWallet() : super(_wallet());
  @override
  void clearKeyCache() => clears++;
}

/// The platform plugin refusing to run the check with [code].
class _RefusingLocalAuth extends LocalAuthentication {
  _RefusingLocalAuth(this.code);
  final String code;
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const <Object>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async =>
      throw PlatformException(code: code);
}

/// A device credential that reports a fixed [outcome] — used to drive the
/// lock screen's "the OS could not run the check" branch.
class _OutcomeAuthService extends FakeAuthService {
  _OutcomeAuthService(this.result);
  final AuthOutcome result;
  @override
  Future<AuthOutcome> authenticate() async {
    prompts++;
    return result;
  }
}

/// A device credential that is asked for and never answers, so the lock
/// screen stays where a test can see it.
class _PendingAuthService extends FakeAuthService {
  /// One completer per request, so a test can answer a request late. The
  /// screen asks through [authenticate], so that is what records here.
  final List<Completer<AuthOutcome>> pending = [];

  @override
  Future<AuthOutcome> authenticate() {
    prompts++;
    final c = Completer<AuthOutcome>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<bool> authenticateWithBiometrics() async =>
      (await authenticate()) == AuthOutcome.success;
}

Future<void> _microtasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  group('the background rule', () {
    late ProviderContainer container;
    late _RecordingAuth auth;
    late _CountingWallet wallet;
    late SessionNotifier session;

    setUp(() async {
      auth = _RecordingAuth();
      wallet = _CountingWallet();
      container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        walletProvider.overrideWith(() => wallet),
      ]);
      session = container.read(sessionProvider.notifier);
      await _microtasks(); // the stored config loads
      await session.setTimeoutMinutes(0); // no inactivity timer in these cases
    });

    tearDown(() => container.dispose());

    test('a pause and a resume lock the wallet', () {
      session.onAppBackground();
      session.onAppForeground();
      expect(auth.locks, 1);
    });

    test('a resume that follows no pause locks nothing', () {
      // The first resume at launch, or the one after an inactive state.
      session.onAppForeground();
      expect(auth.locks, 0);
    });

    test('the cycle behind the app\'s own system UI locks nothing, and the '
        'next real departure still does', () async {
      final prompt = Completer<bool>();
      final run = session.whileSystemUi(() => prompt.future);
      session.onAppBackground();
      session.onAppForeground();
      prompt.complete(true);
      await run;
      expect(auth.locks, 0);
      session.onAppBackground();
      session.onAppForeground();
      expect(auth.locks, 1);
    });

    test('the resume may land after the UI has returned its result', () async {
      // Android delivers the share chooser's result before the activity
      // resumes.
      final prompt = Completer<bool>();
      final run = session.whileSystemUi(() => prompt.future);
      session.onAppBackground();
      prompt.complete(true);
      await run;
      session.onAppForeground();
      expect(auth.locks, 0);
    });

    test('a pause behind the app\'s own UI that outlasts the grace locks on '
        'the resume', () async {
      var now = DateTime(2026, 10, 6, 12);
      session.clock = () => now;
      final prompt = Completer<bool>();
      final run = session.whileSystemUi(() => prompt.future);
      session.onAppBackground();
      prompt.complete(true);
      await run;
      now = now.add(SessionNotifier.systemUiGrace + const Duration(seconds: 1));
      session.onAppForeground();
      expect(auth.locks, 1);
    });

    test('a send in progress is not interrupted by a lock', () {
      session.pauseForTransaction();
      session.onAppBackground();
      session.onAppForeground();
      expect(auth.locks, 0);
      session.resumeAfterTransaction();
      session.onAppBackground();
      session.onAppForeground();
      expect(auth.locks, 1);
    });

    test('a departure during a send that outlasts the grace locks when the '
        'send ends; a short one continues', () {
      var now = DateTime(2026, 10, 6, 12);
      session.clock = () => now;
      session.pauseForTransaction();
      session.onAppBackground();
      now = now.add(const Duration(seconds: 20));
      session.onAppForeground();
      session.resumeAfterTransaction();
      expect(auth.locks, 0, reason: 'a short absence under a send continues');
      session.pauseForTransaction();
      session.onAppBackground();
      now = now.add(SessionNotifier.systemUiGrace + const Duration(seconds: 1));
      session.onAppForeground();
      expect(auth.locks, 0, reason: 'never under the send itself');
      session.resumeAfterTransaction();
      expect(auth.locks, 1, reason: 'the lock lands when the send ends');
    });

    test('a pause during a send keeps the key the signer is using; the '
        'send\'s end clears it', () {
      session.onAppBackground();
      session.onAppForeground();
      expect(wallet.clears, 1, reason: 'a plain departure clears the key');
      session.pauseForTransaction();
      session.onAppBackground();
      expect(wallet.clears, 1, reason: 'not under the signer');
      session.onAppForeground();
      session.resumeAfterTransaction();
      expect(wallet.clears, 2, reason: 'cleared once the send is over');
    });

    test('with lock on background off, a departure locks nothing', () async {
      await session.setLockOnBackground(false);
      session.onAppBackground();
      session.onAppForeground();
      expect(auth.locks, 0);
    });
  });

  testWidgets('an inactive state over the visible app does not lock; a pause '
      'does, and the lock screen is shown', (t) async {
    final credential = _PendingAuthService();
    router.go('/splash'); // the router is global; start where a launch does
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(credential),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 1234, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 10, 6)))),
      ],
      child: const SoquShieldApp(),
    ));
    await t.pump(const Duration(seconds: 3)); // past the splash
    await t.pump();
    expect(find.byType(HomePilotScreen), findsOneWidget);

    // A system overlay over the visible app: a biometric prompt, the
    // notification shade, the app switcher.
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(find.byType(HomePilotScreen), findsOneWidget);
    expect(credential.prompts, 0, reason: 'no credential asked for');

    // A departure.
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump();
    expect(find.byType(LockPilotScreen), findsOneWidget,
        reason: 'the lock is routed to the lock screen');
    // The prompt waits for an active app plus a short settle (build 30).
    await t.pump(const Duration(milliseconds: 500));
    expect(credential.prompts, 1,
        reason: 'the lock screen asks within half a second');

    // Drop the tree so the lock screen's pending prompt and the inactivity
    // timer do not outlive the test.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 6));
  });

  testWidgets('a wallet still writing down its phrase is not timed; a '
      'backed-up one is', (t) async {
    // Timers run under the test binding's fake clock, so a container is enough.
    for (final backedUp in [false, true]) {
      final auth = _RecordingAuth();
      final container = ProviderContainer(overrides: [
        authProvider.overrideWith(() => auth),
        walletProvider.overrideWith(() => MockWalletNotifier(WalletState(
              keys: _wallet().keys,
              network: SoqNetwork.mainnet,
              backupConfirmed: backedUp,
              isInitialized: true,
            ))),
      ]);
      final session = container.read(sessionProvider.notifier);
      await t.pump(); // the stored config loads
      session.recordActivity(); // the reveal tap, or any touch
      await t.pump(const Duration(minutes: 5, seconds: 1));
      expect(auth.locks, backedUp ? 1 : 0,
          reason: backedUp
              ? 'a backed-up wallet locks after five idle minutes'
              : 'a phrase being written down is never interrupted by the timer');
      container.dispose();
    }
  });

  testWidgets('a touch restarts the inactivity timer; five idle minutes lock',
      (t) async {
    final credential = _PendingAuthService();
    router.go('/splash');
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(credential),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 1234, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 10, 6)))),
      ],
      child: const SoquShieldApp(),
    ));
    await t.pump(const Duration(seconds: 3)); // past the splash
    await t.pump();
    expect(find.byType(HomePilotScreen), findsOneWidget);

    // Four idle minutes, then a touch, then another minute: no lock.
    await t.pump(const Duration(minutes: 4));
    await t.tap(find.text('Activity'));
    await t.pump();
    await t.pump(const Duration(minutes: 1, seconds: 1));
    expect(find.byType(LockPilotScreen), findsNothing,
        reason: 'the touch restarted the timer');
    expect(credential.prompts, 0);

    // Five idle minutes from the touch: the lock.
    await t.pump(const Duration(minutes: 4));
    await t.pump();
    expect(find.byType(LockPilotScreen), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));
    expect(credential.prompts, 1);

    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 6));
  });

  testWidgets('a tap to unlock drops the pending prompt: its late answer is '
      'ignored and the fresh prompt unlocks', (t) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    final credential = _PendingAuthService();
    router.go('/splash');
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.authenticated)),
        authServiceProvider.overrideWithValue(credential),
        walletProvider.overrideWith(() => MockWalletNotifier(_wallet())),
        networkStatsProvider.overrideWith((ref) => const AsyncData(
            NetworkStats(blocks: 1234, peers: 8, reachable: true))),
        chainWeatherProvider.overrideWith((ref) =>
            Stream.value(ChainWeather.unreachable(DateTime(2026, 10, 6)))),
      ],
      child: const SoquShieldApp(),
    ));
    await t.pump(const Duration(seconds: 3)); // past the splash
    await t.pump();
    expect(find.byType(HomePilotScreen), findsOneWidget);

    // A departure and a return: the lock screen asks once settled.
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // ignore: invalid_use_of_protected_member
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(LockPilotScreen), findsOneWidget);
    expect(credential.prompts, 1);

    // Four seconds without an answer: the tap appears, and a tap asks again.
    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.byKey(const Key('lock-retry')), findsOneWidget);
    await t.tap(find.byKey(const Key('lock-retry')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(credential.prompts, 2, reason: 'a fresh request');

    // The dropped request answers late with a failure: ignored.
    credential.pending[0].complete(AuthOutcome.failed);
    await t.pump();
    await t.pump();
    expect(find.text('AUTHENTICATION FAILED'), findsNothing);
    expect(find.byType(LockPilotScreen), findsOneWidget);

    // The fresh request succeeds: the wallet unlocks and the route leaves.
    credential.pending[1].complete(AuthOutcome.success);
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.byType(LockPilotScreen), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });

  group('the OS declining to run the check is not a failed attempt', () {
    late SessionNotifier session;
    late ProviderContainer container;

    Future<void> pumpLock(WidgetTester t, AuthOutcome outcome) async {
      container = ProviderContainer(overrides: [
        authProvider
            .overrideWith(() => MockAuthNotifier(AuthStatus.locked)),
        authServiceProvider
            .overrideWithValue(_OutcomeAuthService(outcome)),
        // The REAL session notifier, because the count is what is under test.
        // Its inactivity timer only arms for a backed-up wallet, so this one
        // is not — otherwise it outlives the test as a pending timer.
        walletProvider.overrideWith(() => MockWalletNotifier(
            _wallet().copyWith(backupConfirmed: false))),
      ]);
      addTearDown(container.dispose);
      session = container.read(sessionProvider.notifier);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LockPilotScreen()),
      ));
      await t.pump();
      // The automatic prompt waits for a settled resumed lifecycle and then
      // 350ms before it asks; pump past that or the screen never prompts.
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      // Replace the tree so the screen's own controllers are disposed before
      // the pending-timer check runs.
      addTearDown(() async {
        await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await t.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('a biometric lockout burns no attempt and offers guidance',
        (t) async {
      await pumpLock(t, AuthOutcome.unavailable);

      expect(container.read(sessionProvider).failedAttempts, 0,
          reason: 'the platform already makes the owner wait; a second, '
              'longer app-side backoff on top cannot be cleared by '
              'presenting the right finger');
      expect(session.isInLockout, isFalse);
      // A credential is enrolled; the guidance is to wait and ask again,
      // never to go and set up a screen lock.
      expect(find.text('CHECK PAUSED'), findsOneWidget);
      expect(find.text('NO SCREEN LOCK SET'), findsNothing);
      expect(find.text('AUTHENTICATION FAILED'), findsNothing);
    });

    testWidgets('no credential to check shows the enrollment guidance',
        (t) async {
      await pumpLock(t, AuthOutcome.noCredential);

      expect(container.read(sessionProvider).failedAttempts, 0);
      expect(find.text('NO SCREEN LOCK SET'), findsOneWidget);
      expect(find.text('CHECK PAUSED'), findsNothing);
    });

    testWidgets('a wrong finger still counts, as it must', (t) async {
      await pumpLock(t, AuthOutcome.failed);

      expect(container.read(sessionProvider).failedAttempts, 1,
          reason: 'the brute-force backoff still has to exist');
      expect(find.text('AUTHENTICATION FAILED'), findsOneWidget);
    });
  });

  group('a platform refusal is classified by what it means', () {
    Future<AuthOutcome> refusedWith(String code) =>
        AuthService(localAuth: _RefusingLocalAuth(code)).authenticate();

    test('a pending request or no activity is a check that cannot run now',
        () async {
      // The Android plugin throws these when it cannot start the prompt: a
      // tap to unlock raised while the dropped request is still pending, or
      // no foreground activity. No credential was checked.
      for (final code in [
        'auth_in_progress',
        'no_activity',
        'no_fragment_activity',
        'LockedOut',
        'PermanentlyLockedOut',
      ]) {
        expect(await refusedWith(code), AuthOutcome.unavailable,
            reason: code);
      }
    });

    test('no screen lock or nothing enrolled is a missing credential',
        () async {
      for (final code in ['NotAvailable', 'NotEnrolled', 'PasscodeNotSet']) {
        expect(await refusedWith(code), AuthOutcome.noCredential,
            reason: code);
      }
    });

    test('an unknown error still counts as a failed attempt', () async {
      expect(await refusedWith('SomethingElse'), AuthOutcome.failed);
    });
  });
}
