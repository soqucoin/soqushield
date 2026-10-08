import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/shell.dart';
import 'screens/splash_pilot_screen.dart';
import 'screens/auth/lock_pilot_screen.dart';
import 'screens/auth/welcome_pilot_screen.dart';
import 'screens/auth/create_account_pilot_screen.dart';
import 'screens/auth/seed_backup_screen.dart';
import 'screens/auth/seed_restore_screen.dart';
import 'screens/auth/risk_disclosure_screen.dart';
import 'screens/home/home_pilot_screen.dart';
import 'screens/activity/activity_pilot_screen.dart';
import 'screens/network/network_screen.dart';
import 'screens/settings/settings_pilot_screen.dart';
import 'screens/receive/receive_pilot_screen.dart';
import 'screens/send/send_pilot_screen.dart';
import 'screens/guide/guide_screen.dart';
import 'screens/guide/guide_article_screen.dart';
import 'theme/colors.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// The lite wallet's routes: onboarding and lock outside the shell, the seed
/// screens full-screen, the wallet shell (Wallet, Send, Activity, Network
/// under one tab bar), and the pushed screens (Receive, Settings, the Field
/// Manual).
final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    // ── Onboarding and lock (outside the shell) ──
    GoRoute(
      path: '/splash',
      builder: (context, state) => _mobileWrap(const SplashPilotScreen()),
    ),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => _mobileWrap(const WelcomePilotScreen()),
    ),
    GoRoute(
      path: '/lock',
      builder: (context, state) => _mobileWrap(const LockPilotScreen()),
    ),
    GoRoute(
      path: '/create-account',
      builder: (context, state) =>
          _mobileWrap(const CreateAccountPilotScreen()),
    ),

    // ── Seed management (outside the shell, full-screen) ──
    GoRoute(
      path: '/seed-backup',
      builder: (context, state) => _mobileWrap(const SeedBackupScreen()),
    ),
    GoRoute(
      path: '/seed-restore',
      builder: (context, state) => _mobileWrap(const SeedRestoreScreen()),
    ),
    GoRoute(
      path: '/risk-disclosure',
      builder: (context, state) => _mobileWrap(const RiskDisclosureScreen()),
    ),

    // ── The wallet shell: Wallet | Activity | Network | More ──
    // Send sits in the shell so the tab bar persists under it.
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomePilotScreen()),
        ),
        GoRoute(
          path: '/send',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SendPilotScreen()),
        ),
        GoRoute(
          path: '/activity',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ActivityPilotScreen()),
        ),
        GoRoute(
          path: '/network',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: NetworkPilotScreen()),
        ),
      ],
    ),

    // ── Pushed routes ──
    GoRoute(
      path: '/receive',
      builder: (context, state) => const ReceivePilotScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => _mobileWrap(const SettingsPilotScreen()),
    ),

    // Field Manual — the in-app user guide (drawer Help entry).
    GoRoute(
      path: '/guide',
      builder: (context, state) => _mobileWrap(const GuideScreen()),
    ),
    GoRoute(
      path: '/guide/:id',
      builder: (context, state) => _mobileWrap(
          GuideArticleScreen(articleId: state.pathParameters['id'] ?? '')),
    ),
  ],
);

/// Wrap screens in mobile constraint to match AppShell on web.
Widget _mobileWrap(Widget child) {
  return ColoredBox(
    color: SoquColors.void_,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: child,
      ),
    ),
  );
}
