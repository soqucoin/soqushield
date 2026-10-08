import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';
import 'router.dart';
import 'providers/auth_provider.dart';
import 'providers/launch_state_provider.dart';
import 'providers/session_provider.dart';

/// The largest system text scale the pinned layouts take.
const double kMaxTextScale = 1.3;

void main() {
  // A3-01: Global error boundary — catches ALL uncaught exceptions.
  //
  // Without this, any unhandled error in a widget build() method shows
  // Flutter's red error screen to users, or worse, silently crashes.
  //
  // Three layers:
  //   1. FlutterError.onError — catches widget build/layout errors
  //   2. ErrorWidget.builder — replaces red screen with graceful fallback
  //   3. runZonedGuarded — catches uncaught async exceptions

  // Layer 3: Catch uncaught async exceptions (Futures without try-catch)
  // IMPORTANT: ensureInitialized() and runApp() MUST be in the same zone
  // to avoid Flutter's "Zone mismatch" assertion error.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // SB-11: silence ALL debugPrint output in release builds. The app has
      // ~285 debugPrint calls (RPC URLs, txids, balances, key-cache lifecycle)
      // that would otherwise leak to logcat/Console in production. Overriding
      // the global hook here is a single, robust gate — full logs remain in
      // debug/profile. (No raw print() calls exist to gate separately.)
      if (kReleaseMode) {
        debugPrint = (String? message, {int? wrapWidth}) {};
      }

      // Layer 1: Catch widget framework errors (build, layout, paint)
      FlutterError.onError = (FlutterErrorDetails details) {
        // In debug mode, print the full error for development
        if (kDebugMode) {
          FlutterError.dumpErrorToConsole(details);
        }
        // In release mode, log to debugPrint (captured by platform logcat/console)
        debugPrint('[SoquShield] FlutterError: ${details.exceptionAsString()}');
        debugPrint('[SoquShield] Stack: ${details.stack}');
      };

      // Layer 2: Replace the red error screen with a graceful fallback
      ErrorWidget.builder = (FlutterErrorDetails details) {
        return Material(
          color: SoquColors.void_,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: SoquColors.guardian.withValues(alpha: 0.5),
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: SoquColors.ice,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your funds are safe. Try navigating back.',
                    style: TextStyle(
                      color: SoquColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      };

      // The launch flag is read from plain preferences before the first
      // frame, so an install that has seen Mainnet live never opens on the
      // pre-launch line. A failed load leaves the flag to load on its own.
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('[SoquShield] preferences did not load before the first frame: $e');
      }

      runApp(ProviderScope(
        overrides: [preloadedPreferencesProvider.overrideWithValue(prefs)],
        child: const SoquShieldApp(),
      ));
    },
    (error, stackTrace) {
      debugPrint('[SoquShield] Uncaught async error: $error');
      debugPrint('[SoquShield] Stack: $stackTrace');
    },
  );
}


class SoquShieldApp extends ConsumerStatefulWidget {
  const SoquShieldApp({super.key});

  @override
  ConsumerState<SoquShieldApp> createState() => _SoquShieldAppState();
}

class _SoquShieldAppState extends ConsumerState<SoquShieldApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A lock is a state; the lock screen is routed here, so a lock from the
    // background rule or the inactivity timeout reaches the user wherever
    // the app is. Only a lock of an unlocked wallet navigates: at launch the
    // splash routes the first state itself.
    ref.listenManual<AsyncValue<AuthStatus>>(authProvider, (previous, next) {
      if (next.asData?.value == AuthStatus.locked &&
          previous?.asData?.value == AuthStatus.authenticated) {
        router.go('/lock');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(sessionProvider.notifier);
    switch (state) {
      // Only a pause is a departure. `inactive` also fires while the app is
      // still on screen behind a system overlay (a biometric prompt, the
      // notification shade, the app switcher) and must not lock.
      case AppLifecycleState.paused:
        session.onAppBackground();
      case AppLifecycleState.resumed:
        session.onAppForeground();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize session provider
    ref.watch(sessionProvider);

    return MaterialApp.router(
      title: 'SoquShield',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
      // Every pointer down anywhere in the app is activity for the
      // inactivity timer. The instrument panels are pinned layouts (a
      // 54-point button, a 24-cell phrase grid, a fixed hero): the system
      // text size is honoured up to 130 percent, and the rows scale their
      // text to fit; past that a larger setting would push the words of the
      // phrase off their cells.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) =>
            ref.read(sessionProvider.notifier).recordActivity(),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: kMaxTextScale,
          child: child!,
        ),
      ),
    );
  }
}
