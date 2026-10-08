import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/wallet_provider.dart';
import '../theme/instrument.dart';
import '../app_version.dart';

/// Slide-out "More" panel: the account line, Help and Settings.
///
/// Wallet and Activity are the bottom tabs; this panel holds only what is
/// not a tab, with no duplicates.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider);

    return Drawer(
      backgroundColor: Instrument.void0,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        // Crisp trailing hairline so the panel edge is visible against the scrim.
        decoration: const BoxDecoration(
          border: Border(
            right: BorderSide(color: Instrument.line, width: 0.6),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Account ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
                child: Text('ACCOUNT', style: Instrument.eyebrow(size: 10)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Instrument.line, width: 0.6),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/soqucoin_logo.png',
                          width: 32, height: 32, fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('SoquShield',
                            style: TextStyle(
                              color: Instrument.readout,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (wallet.address.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: wallet.address));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Copied',
                                      style: TextStyle(fontSize: 12)),
                                    backgroundColor: Instrument.void2,
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              child: Text(
                                '${wallet.address.substring(0, 8)}...${wallet.address.substring(wallet.address.length - 4)}',
                                style: const TextStyle(
                                  color: Instrument.label,
                                  fontSize: 11.5,
                                  fontFamily: kMono,
                                ),
                              ),
                            )
                          else
                            const Text('No wallet',
                              style: TextStyle(
                                color: Instrument.label,
                                fontSize: 11.5,
                                fontFamily: kMono,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const InstrumentDivider(),

              // Help = the in-app Field Manual; Discord lives inside it as the
              // "still stuck" escalation path, not the front door.
              _DrawerItem(
                icon: Icons.menu_book_outlined,
                label: 'Help',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/guide');
                },
              ),
              _DrawerItem(
                icon: Icons.tune_outlined,
                label: 'Settings',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/settings');
                },
              ),

              const Spacer(),

              // Version — barely visible
              const Padding(
                padding: EdgeInsets.only(left: 22, bottom: 16, top: 4),
                child: Text(kAppVersion,
                  style: TextStyle(
                    color: Instrument.faint,
                    fontSize: 10,
                    fontFamily: kMono,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Drawer item — single responsibility, clean ──
class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem> {
  bool _down = false;
  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: _down ? Instrument.void2 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: Row(
          children: [
            Icon(widget.icon, color: Instrument.label, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Text(widget.label,
                style: const TextStyle(
                  color: Instrument.readout,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Instrument.faint, size: 18),
          ],
        ),
      ),
    );
  }
}
