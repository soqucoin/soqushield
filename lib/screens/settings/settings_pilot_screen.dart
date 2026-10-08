// PILOT — Settings on the instrument language.
//
// Clean austere sections: Security · Backup & Keys · Network · About · Danger.
// Every action handler is preserved from the full app: biometric toggle,
// network switch, timeout, export-backup dialog, wipe-wallet.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/instrument.dart';
import '../../theme/motion.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/wallet_keys.dart' show SoqNetwork;
import '../../services/backup_service.dart';
import '../../services/secure_storage_service.dart';
import '../../services/rpc_service.dart';
import '../../app_version.dart';

class SettingsPilotScreen extends ConsumerStatefulWidget {
  const SettingsPilotScreen({super.key});
  @override
  ConsumerState<SettingsPilotScreen> createState() =>
      _SettingsPilotScreenState();
}

class _SettingsPilotScreenState extends ConsumerState<SettingsPilotScreen> {
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final service = ref.read(authServiceProvider);
    final available = await service.isBiometricAvailable();
    final enabled = await service.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 36),
                physics: const BouncingScrollPhysics(),
                children: [
                  // ── SECURITY ──
                  _section('SECURITY'),
                  if (_biometricAvailable)
                    _toggleTile(Icons.fingerprint_rounded, 'Biometric lock',
                        'Unlock with Face ID / Touch ID', _biometricEnabled,
                        _toggleBiometric),
                  _toggleTile(Icons.lock_clock_outlined, 'Lock on background',
                      'Require unlock when reopening', session.lockOnBackground,
                      (v) => ref
                          .read(sessionProvider.notifier)
                          .setLockOnBackground(v)),
                  _timeoutTile(session),

                  // ── BACKUP & KEYS ──
                  _section('BACKUP & KEYS'),
                  _navTile(Icons.vpn_key_outlined, 'Recovery phrase',
                      'Show your 24-word phrase',
                      () => context.push('/seed-backup')),
                  // The share sheet that follows anchors to this row on an
                  // iPad, so the row's own context is read at the tap.
                  Builder(
                    builder: (row) => _navTile(
                        Icons.file_download_outlined,
                        'Encrypted backup',
                        'Export a password-protected file',
                        () => _showExportDialog(shareOriginOf(row))),
                  ),

                  // ── NETWORK ──
                  _section('NETWORK'),
                  _networkTile(wallet),
                  _noteTile(
                      'A mainnet address begins sq1. A stagenet address '
                      'begins ssq1 and cannot receive anything on mainnet. '
                      'Your address here begins ${wallet.network.hrp}1. '
                      'Balances and sending on Mainnet open at mainnet launch.'),
                  _infoTile(Icons.dns_outlined, 'Endpoint',
                      RpcService.hostFor(wallet.network)),
                  _infoTile(Icons.height_rounded, 'Block height',
                      wallet.blockHeight > 0
                          ? _fmt(wallet.blockHeight)
                          : 'Waiting for the network'),

                  // ── ABOUT ──
                  _section('ABOUT'),
                  _infoTile(Icons.shield_outlined, 'Version', kAppVersion),
                  _infoTile(Icons.lock_outline, 'Security',
                      'ML-DSA-44 · post-quantum'),
                  _copyTile(Icons.account_balance_wallet_outlined,
                      'SOQ address', wallet.address, 'SOQ address copied'),

                  // ── DANGER ──
                  _section('DANGER ZONE'),
                  _dangerTile(Icons.delete_forever_outlined, 'Wipe wallet',
                      'Delete all data from this device · irreversible',
                      _showWipeDialog),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════ handlers — preserved from the full app ════

  Future<void> _toggleBiometric(bool enabled) async {
    final service = ref.read(authServiceProvider);
    if (enabled) {
      final success = await ref
          .read(sessionProvider.notifier)
          .whileSystemUi(service.authenticateWithBiometrics);
      if (!success) return;
    }
    await service.setBiometricEnabled(enabled);
    setState(() => _biometricEnabled = enabled);
    HapticFeedback.mediumImpact();
  }

  Future<void> _doExport(BuildContext ctx, String password, String confirm,
      Rect? shareOrigin) async {
    if (password.length < 8) {
      _showSnack('Password must be at least 8 characters');
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match');
      return;
    }
    setState(() => _exporting = true);
    try {
      final backup = BackupService(SecureStorageService());
      final bytes = await backup.exportBackup(password);
      if (bytes == null) {
        _showSnack('No wallet to export');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file =
          File('${tempDir.path}/soqushield_backup_$timestamp.soqbackup');
      await file.writeAsBytes(bytes);
      if (ctx.mounted) Navigator.pop(ctx);
      // The share sheet pauses the app on Android; it is the app's own UI
      // and must not lock the wallet when it closes.
      await ref.read(sessionProvider.notifier).whileSystemUi(() =>
          Share.shareXFiles([XFile(file.path)],
              text: 'SoquShield Encrypted Wallet Backup',
              sharePositionOrigin: shareOrigin));
      if (!mounted) return;
      _showSnack('Backup file shared');
      HapticFeedback.mediumImpact();
    } catch (e) {
      try {
        final backup = BackupService(SecureStorageService());
        final bytes = await backup.exportBackup(password);
        if (bytes != null) {
          await Clipboard.setData(
              ClipboardData(text: 'soqbackup:${base64Encode(bytes)}'));
          if (ctx.mounted) Navigator.pop(ctx);
          _showSnack('Backup copied to clipboard (share unavailable)');
        }
      } catch (_) {
        _showSnack('Export failed: $e');
      }
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _showExportDialog(Rect? shareOrigin) {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, _) => AlertDialog(
          backgroundColor: Instrument.void2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Instrument.line.withValues(alpha: 0.6))),
          title: const Text('Encrypted backup',
              style: TextStyle(
                  color: Instrument.readout,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Choose a strong password to encrypt your backup. You\'ll need it to restore.',
                  style: TextStyle(
                      color: Instrument.faint, fontSize: 12, height: 1.5)),
              const SizedBox(height: 16),
              _pwField(passwordCtrl, 'Password (8+ chars)'),
              const SizedBox(height: 8),
              _pwField(confirmCtrl, 'Confirm password'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero)),
              child: const Text('CANCEL',
                  style: TextStyle(
                      color: Instrument.label,
                      fontSize: 11,
                      fontFamily: kMono,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 11 * 0.1)),
            ),
            TextButton(
              onPressed: _exporting
                  ? null
                  : () => _doExport(
                      ctx, passwordCtrl.text, confirmCtrl.text, shareOrigin),
              style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero)),
              child: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Instrument.signal))
                  : const Text('EXPORT',
                      style: TextStyle(
                          color: Instrument.signal,
                          fontSize: 11,
                          fontFamily: kMono,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 11 * 0.1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pwField(TextEditingController controller, String hint) => TextField(
        controller: controller,
        obscureText: true,
        cursorColor: Instrument.signal,
        style: const TextStyle(color: Instrument.readout, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Instrument.faint, fontSize: 13),
          filled: true,
          fillColor: Instrument.void0,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide:
                  BorderSide(color: Instrument.line.withValues(alpha: 0.5))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide:
                  BorderSide(color: Instrument.line.withValues(alpha: 0.5))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: Instrument.signal)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  void _showWipeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Instrument.void2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: const BorderSide(color: Color(0xFFD96A6A))),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD96A6A), size: 20),
            SizedBox(width: 8),
            Text('Wipe wallet',
                style: TextStyle(
                    color: Color(0xFFD96A6A),
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        content: Text(
            'This permanently deletes your wallet from this device.\n\n'
            'If you have not backed up your 24-word recovery phrase, your funds '
            'will be PERMANENTLY LOST. This cannot be undone.',
            style: TextStyle(
                color: Instrument.label, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero)),
            child: const Text('CANCEL',
                style: TextStyle(
                    color: Instrument.label,
                    fontSize: 11,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 11 * 0.1)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(walletProvider.notifier).wipeWallet();
              final authService = ref.read(authServiceProvider);
              await authService.clearAccount();
              await ref.read(authProvider.notifier).refresh();
              if (mounted) context.go('/welcome');
            },
            // Destructive keeps the threat color; square + mono caps.
            style: TextButton.styleFrom(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero)),
            child: const Text('WIPE WALLET',
                style: TextStyle(
                    color: Color(0xFFD96A6A),
                    fontSize: 11,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 11 * 0.1)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: const TextStyle(color: Instrument.readout, fontSize: 13)),
      backgroundColor: Instrument.void2,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _fmt(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  // ════ austere tiles ════

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 22, 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Instrument.label, size: 20),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            const SizedBox(width: 2),
            Text('SETTINGS', style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 24, 0, 6),
        child: Text(title, style: Instrument.eyebrow(size: 10)),
      );

  /// A row. With [pulse], a ring rises from [pulseFrom] each time [pulse]
  /// changes (a setting that changed), clipped to the row.
  Widget _rowFrame(
      {required Widget child,
      VoidCallback? onTap,
      Object? pulse,
      Offset Function(Size size)? pulseFrom,
      Key? key}) {
    final box = Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: Instrument.line.withValues(alpha: 0.3), width: 0.6)),
      ),
      child: child,
    );
    return GestureDetector(
      key: key,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: pulse == null
          ? box
          : RingPulse(trigger: pulse, originFor: pulseFrom, child: box),
    );
  }

  Widget _navTile(IconData icon, String title, String? sub, VoidCallback onTap) =>
      _rowFrame(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(child: _titleSub(title, sub)),
            Icon(Icons.chevron_right_rounded, size: 18, color: Instrument.faint),
          ],
        ),
      );

  // The ring fires on the value itself, so a refused change (a biometric
  // prompt declined) and a rebuild ring nothing; it rises from the knob's
  // new side. The key keeps each ring with its own setting when a row
  // above it appears (the biometric row, after its availability loads).
  Widget _toggleTile(IconData icon, String title, String? sub, bool value,
          ValueChanged<bool> onChanged) =>
      _rowFrame(
        key: ValueKey('toggle $title'),
        onTap: () => onChanged(!value),
        pulse: value,
        pulseFrom: (s) => Offset(s.width - 20 + (value ? 9 : -9), s.height / 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(child: _titleSub(title, sub)),
            _switch(value),
          ],
        ),
      );

  // The value keeps the right edge and shortens with an ellipsis when the
  // title and the value cannot both fit (a narrow phone, a large text size).
  Widget _infoTile(IconData icon, String title, String value) => _rowFrame(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Flexible(child: _titleSub(title, null)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: Instrument.faint, fontSize: 12, fontFamily: kMono)),
            ),
          ],
        ),
      );

  // A wrapped sentence under a control: the reason the control matters now.
  Widget _noteTile(String text) => _rowFrame(
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: Instrument.faint, fontSize: 12, height: 1.4)),
            ),
          ],
        ),
      );

  Widget _copyTile(IconData icon, String title, String value, String toast,
          {String empty = 'No wallet'}) =>
      _rowFrame(
        onTap: value.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: value));
                HapticFeedback.selectionClick();
                _showSnack(toast);
              },
        child: Row(
          children: [
            Icon(icon, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(child: _titleSub(title, null)),
            Text(
                value.isEmpty
                    ? empty
                    : '${value.substring(0, value.length < 10 ? value.length : 8)}…${value.length > 6 ? value.substring(value.length - 6) : ''}',
                style: TextStyle(
                    color: Instrument.faint, fontSize: 12, fontFamily: kMono)),
          ],
        ),
      );

  Widget _dangerTile(
          IconData icon, String title, String sub, VoidCallback onTap) =>
      _rowFrame(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFFD96A6A)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Color(0xFFD96A6A),
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(color: Instrument.faint, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _titleSub(String title, String? sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Instrument.readout, fontSize: 14)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: Instrument.faint, fontSize: 11)),
          ],
        ],
      );

  Widget _switch(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: on ? Instrument.signal.withValues(alpha: 0.4) : Instrument.line,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? Instrument.signal : Instrument.label),
          ),
        ),
      );

  Widget _timeoutTile(SessionConfig session) => _rowFrame(
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(child: _titleSub('Auto-lock', null)),
            DropdownButton<int>(
              value: session.timeoutMinutes,
              dropdownColor: Instrument.void2,
              underline: const SizedBox.shrink(),
              isDense: true,
              icon: const Icon(Icons.expand_more_rounded,
                  size: 16, color: Instrument.faint),
              style: const TextStyle(
                  color: Instrument.label, fontSize: 12, fontFamily: kMono),
              items: [
                for (final t in SessionConfig.timeoutOptions)
                  DropdownMenuItem(
                      value: t, child: Text(SessionConfig.timeoutLabel(t))),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(sessionProvider.notifier).setTimeoutMinutes(v);
                }
              },
            ),
          ],
        ),
      );

  Widget _networkTile(WalletState wallet) => _rowFrame(
        child: Row(
          children: [
            Icon(Icons.lan_outlined, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(child: _titleSub('Network', null)),
            DropdownButton<SoqNetwork>(
              value: wallet.network,
              dropdownColor: Instrument.void2,
              underline: const SizedBox.shrink(),
              isDense: true,
              icon: const Icon(Icons.expand_more_rounded,
                  size: 16, color: Instrument.faint),
              style: const TextStyle(
                  color: Instrument.label, fontSize: 12, fontFamily: kMono),
              items: const [
                DropdownMenuItem(
                    value: SoqNetwork.mainnet, child: Text('Mainnet')),
                DropdownMenuItem(
                    value: SoqNetwork.stagenet, child: Text('Stagenet')),
              ],
              onChanged: (n) {
                if (n == null) return;
                ref.read(walletProvider.notifier).setNetwork(n);
              },
            ),
          ],
        ),
      );
}
