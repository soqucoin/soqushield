import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/instrument.dart';
import '../providers/wallet_provider.dart';
import '../widgets/app_drawer.dart';

/// Bottom navigation shell: Wallet | Activity | Network | More (drawer).
///
/// Send sits in the shell too (reached from the Wallet screen) so the bar
/// persists under it; it highlights the Wallet tab.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  static int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/activity')) return 1;
    if (location.startsWith('/network')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _selectedIndex(context);

    return ColoredBox(
      color: Instrument.void0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Scaffold(
            key: scaffoldKey,
            drawer: const AppDrawer(),
            drawerEdgeDragWidth: 40,
            body: Stack(
              children: [
                child,
                // ── Network badge — the same STAGENET / MAINNET indicator on
                // every screen in the shell ──
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final network = ref.watch(walletProvider).network;
                      const badgeColor = Instrument.signal;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          network.displayName.toUpperCase(),
                          style: const TextStyle(
                            color: badgeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                color: Instrument.void0,
                border: Border(
                  top: BorderSide(color: Instrument.line, width: 0.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      _NavTab(
                        icon: Icons.account_balance_wallet_outlined,
                        activeIcon: Icons.account_balance_wallet,
                        label: 'Wallet',
                        selected: currentIndex == 0,
                        onTap: () => context.go('/'),
                      ),
                      _NavTab(
                        icon: Icons.receipt_long_outlined,
                        activeIcon: Icons.receipt_long,
                        label: 'Activity',
                        selected: currentIndex == 1,
                        onTap: () => context.go('/activity'),
                      ),
                      _NavTab(
                        icon: Icons.sensors_outlined,
                        activeIcon: Icons.sensors,
                        label: 'Network',
                        selected: currentIndex == 2,
                        onTap: () => context.go('/network'),
                      ),
                      _NavTab(
                        icon: Icons.menu,
                        activeIcon: Icons.menu,
                        label: 'More',
                        selected: false,
                        onTap: () =>
                            scaffoldKey.currentState?.openDrawer(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom nav tab — instrument language: LIVE accent when active, muted
/// taupe at rest, on the shared warm canvas.
class _NavTab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Instrument.signal;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator line
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: selected ? 20 : 0,
              height: 2,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: selected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.zero,
              ),
            ),
            Icon(
              selected ? activeIcon : icon,
              color: selected ? activeColor : Instrument.label,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? activeColor : Instrument.label,
                fontSize: 10,
                fontFamily: kLabel,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                letterSpacing: selected ? 1 : 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
