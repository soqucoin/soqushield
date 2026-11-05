// PILOT — the wallets on this device, on the instrument language.
//
// One row per wallet: its name, the address it receives on, and which one
// is open. Opening another is the only action here that crosses the device
// credential, and the row says so before it is tapped.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/wallet_record.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/instrument.dart';

/// Every wallet on the device.
///
/// ⛔ Depends on the wallet STATE, not just the notifier. The registry is
/// written during boot — the pre-registry wallet is adopted into it there —
/// and the notifier's identity never changes, so a list read once at the
/// first build resolved to empty and stayed empty. Watching the address and
/// the loading flag re-reads it the moment boot settles, and again after a
/// switch.
final walletListProvider =
    FutureProvider.autoDispose<List<WalletRecord>>((ref) {
  ref.watch(walletProvider.select((w) => (w.address, w.isLoading)));
  return ref.watch(walletProvider.notifier).listWallets();
});

class WalletsPilotScreen extends ConsumerStatefulWidget {
  const WalletsPilotScreen({super.key});

  @override
  ConsumerState<WalletsPilotScreen> createState() => _WalletsPilotScreenState();
}

class _WalletsPilotScreenState extends ConsumerState<WalletsPilotScreen> {
  /// The row a credential prompt is open for, so it cannot be tapped twice.
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever the open wallet changes. The OPEN mark follows the
    // wallet's id, not its address: the address moves with the network,
    // and the row's copy of it is only as fresh as the registry.
    ref.watch(walletProvider.select((w) => (w.address, w.network)));
    final openId = ref.read(walletProvider.notifier).openWalletId;
    final wallets = ref.watch(walletListProvider);

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: wallets.when(
                loading: () => _centred('Reading the wallets on this device.'),
                error: (e, _) => _centred('The wallet list could not be read.'),
                data: (list) => ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 36),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _section('ON THIS DEVICE'),
                    for (final w in list)
                      _walletRow(w, open: w.id == openId),
                    _section('ADD'),
                    _navTile(
                      Icons.add_circle_outline_rounded,
                      'Create a wallet',
                      'A new seed, generated on this device',
                      _createWallet,
                    ),
                    _navTile(
                      Icons.download_outlined,
                      'Import a wallet',
                      'From a recovery phrase you already have',
                      _importWallet,
                    ),
                    _note(
                      'Each wallet here keeps its own seed. One set of words '
                      'reaches one wallet, so a phrase you write down for one '
                      'tells you nothing about the others. Back up each one '
                      'separately.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════ rows ════

  Widget _walletRow(WalletRecord w, {required bool open}) {
    final busy = _busyId == w.id;
    return _rowFrame(
      key: ValueKey('wallet ${w.id}'),
      // While any switch is waiting on the credential, no row starts
      // another: one switch at a time, and the first one's prompt decides.
      onTap: _busyId != null ? null : () => _onRowTap(w, open: open),
      child: Row(
        children: [
          // A copper dot marks the wallet that is open; the others read as
          // equipment, not as an error.
          _dot(open ? Instrument.signal : Instrument.line),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Instrument.readout, fontSize: 14),
                      ),
                    ),
                    if (open) ...[
                      const SizedBox(width: 8),
                      Text('OPEN', style: Instrument.eyebrow(size: 8.5)),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _shortAddress(w.address),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Instrument.faint,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.4, color: Instrument.signal),
            )
          else
            // A real button: a screen reader names it after the wallet it
            // renames, and a keyboard can reach and press it.
            IconButton(
              key: ValueKey('rename ${w.id}'),
              onPressed: () => _renameWallet(w),
              tooltip: 'Rename ${w.name}',
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: Instrument.faint,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  /// Tapping the open wallet does nothing. Tapping another asks for the
  /// device credential first — the row says so, so the prompt is expected.
  Future<void> _onRowTap(WalletRecord w, {required bool open}) async {
    if (open) return;
    final confirmed = await _confirm(
      title: 'Open ${w.name}?',
      body: 'This device will ask you to confirm it is you. '
          'The wallet that is open now stays on this device.',
      action: 'OPEN',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = w.id);
    final ok = await ref.read(walletProvider.notifier).openWallet(w.id);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (ok) {
      HapticFeedback.mediumImpact();
      ref.invalidate(walletListProvider);
      _snack('${w.name} is open');
    } else {
      // openWallet puts its own reason on the wallet state when there is
      // one; a refused credential has none, and needs no telling off.
      final reason = ref.read(walletProvider).error;
      if (reason != null) _snack(reason);
    }
  }

  Future<void> _renameWallet(WalletRecord w) async {
    final name = await _promptForName(
      title: 'Rename wallet',
      initial: w.name,
      action: 'SAVE',
    );
    if (name == null || !mounted) return;
    final record = await ref.read(walletProvider.notifier).renameWallet(w.id, name);
    if (!mounted) return;
    if (record != null) {
      ref.invalidate(walletListProvider);
      _snack('Renamed to ${record.name}');
    } else {
      _snack(ref.read(walletProvider).error ?? 'That name could not be used');
    }
  }

  Future<void> _createWallet() async {
    final name = await _promptForName(
      title: 'Create a wallet',
      initial: '',
      action: 'CREATE',
      hint: 'Savings',
    );
    if (name == null || !mounted) return;

    final record =
        await ref.read(walletProvider.notifier).createAdditionalWallet(name: name);
    if (!mounted) return;
    if (record != null) {
      ref.invalidate(walletListProvider);
      _snack('${record.name} added. Write down its recovery phrase.');
    } else {
      _snack(ref.read(walletProvider).error ?? 'The wallet could not be added');
    }
  }

  Future<void> _importWallet() async {
    final result = await _promptForImport();
    if (result == null || !mounted) return;

    final record = await ref.read(walletProvider.notifier).importAdditionalWallet(
          name: result.$1,
          mnemonic: result.$2,
        );
    if (!mounted) return;
    if (record != null) {
      ref.invalidate(walletListProvider);
      _snack('${record.name} imported');
    } else {
      _snack(ref.read(walletProvider).error ?? 'That wallet could not be imported');
    }
  }

  // ════ dialogs ════

  Future<String?> _promptForName({
    required String title,
    required String initial,
    required String action,
    String? hint,
  }) =>
      showDialog<String>(
        context: context,
        builder: (ctx) => _NameDialog(
            title: title, initial: initial, action: action, hint: hint),
      );

  Future<(String, String)?> _promptForImport() =>
      showDialog<(String, String)>(
        context: context,
        builder: (ctx) => const _ImportDialog(),
      );

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => _Panel(
          title: title,
          actions: [
            _DialogAction(label: 'CANCEL', onPressed: () => Navigator.pop(ctx)),
            _DialogAction(
                label: action,
                primary: true,
                onPressed: () => Navigator.pop(ctx, true)),
          ],
          children: [
            Text(body,
                style: const TextStyle(
                    color: Instrument.label, fontSize: 13, height: 1.45)),
          ],
        ),
      );

  // ════ frame ════

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      backgroundColor: Instrument.void2,
      behavior: SnackBarBehavior.floating,
    ));
  }

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
            Text('WALLETS', style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  Widget _centred(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Instrument.faint, fontSize: 12)),
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 24, 0, 6),
        child: Text(title, style: Instrument.eyebrow(size: 10)),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
        child: Text(text,
            style: TextStyle(
                color: Instrument.faint, fontSize: 11, height: 1.5)),
      );

  Widget _dot(Color color) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _rowFrame({required Widget child, VoidCallback? onTap, Key? key}) =>
      GestureDetector(
        key: key,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: Instrument.line.withValues(alpha: 0.3), width: 0.6)),
          ),
          child: child,
        ),
      );

  Widget _navTile(
          IconData icon, String title, String? sub, VoidCallback onTap) =>
      _rowFrame(
        onTap: onTap,
        key: ValueKey('nav $title'),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Instrument.label),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Instrument.readout, fontSize: 14)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub,
                        style:
                            TextStyle(color: Instrument.faint, fontSize: 11)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: Instrument.faint),
          ],
        ),
      );
}

/// The first and last of an address, which is what a holder recognises it
/// by. The whole string is on the Receive screen; a wallet row is for
/// telling one wallet from another, not for reading an address off.
String _shortAddress(String address) =>
    address.length <= 20 ? address : '${address.substring(0, 10)}…${address.substring(address.length - 6)}';

/// A dialog in the instrument language: square corners, raised panel.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.actions, required this.children});
  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Instrument.void2,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title, style: Instrument.eyebrow(size: 10)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
        actions: actions,
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.secret = false,
  });
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;

  /// The field takes a recovery phrase: no correction, no suggestions, and
  /// no keyboard may learn the words for its personal dictionary. A
  /// correction can also turn a valid phrase into an invalid one.
  final bool secret;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        maxLength: maxLength,
        maxLines: maxLines,
        autocorrect: !secret,
        enableSuggestions: !secret,
        enableIMEPersonalizedLearning: !secret,
        style: const TextStyle(color: Instrument.readout, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          hintStyle: TextStyle(color: Instrument.faint, fontSize: 13),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Instrument.line),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Instrument.signal),
          ),
        ),
      );
}


/// ⛔ The dialog owns its controller and disposes it in its own dispose().
/// Disposing one at the call site, right after `showDialog` returns, is a
/// use-after-dispose: the route is still animating out and the field it
/// belongs to is still being built.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.action,
    this.hint,
  });
  final String title;
  final String initial;
  final String action;
  final String? hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Panel(
        title: widget.title,
        actions: [
          _DialogAction(label: 'CANCEL', onPressed: () => Navigator.pop(context)),
          _DialogAction(
            label: widget.action,
            primary: true,
            onPressed: () => Navigator.pop(context, _controller.text),
          ),
        ],
        children: [
          _Field(
            controller: _controller,
            hint: widget.hint ?? 'Wallet name',
            maxLength: WalletRecord.maxNameLength,
            autofocus: true,
          ),
        ],
      );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _name = TextEditingController();
  final _words = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _words.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Import a wallet',
        actions: [
          _DialogAction(label: 'CANCEL', onPressed: () => Navigator.pop(context)),
          _DialogAction(
            label: 'IMPORT',
            primary: true,
            onPressed: () => Navigator.pop(context, (_name.text, _words.text)),
          ),
        ],
        children: [
          _Field(
            controller: _name,
            hint: 'Wallet name',
            maxLength: WalletRecord.maxNameLength,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          _Field(
              controller: _words,
              hint: 'Your recovery phrase',
              maxLines: 3,
              secret: true),
          const SizedBox(height: 10),
          Text('The words are read on this device and never leave it.',
              style: TextStyle(color: Instrument.faint, fontSize: 11)),
        ],
      );
}

/// A dialog button. Keyed rather than found by its words: the confirm action
/// for a switch reads OPEN, and so does the badge on the row of the wallet
/// that is already open.
class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => TextButton(
        key: ValueKey('dialog ${primary ? 'confirm' : 'cancel'}'),
        onPressed: onPressed,
        child: Text(label,
            style: Instrument.eyebrow(size: 10).copyWith(
                color: primary ? Instrument.signal : Instrument.faint)),
      );
}
