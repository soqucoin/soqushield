// PILOT — the address book, on the instrument language.
//
// One row per saved address: its name and the first and last of the address,
// grouped by network with the wallet's own network first. A row opens the
// full address with a copy action; the icons on it rename and remove. The
// book lives on this device only.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/address_book_entry.dart';
import '../../models/wallet_keys.dart';
import '../../providers/address_book_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/instrument.dart';
import 'address_entry_dialog.dart';

class AddressBookScreen extends ConsumerStatefulWidget {
  const AddressBookScreen({super.key});

  @override
  ConsumerState<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends ConsumerState<AddressBookScreen> {
  @override
  Widget build(BuildContext context) {
    final book = ref.watch(addressBookProvider);
    final current = ref.watch(walletProvider.select((w) => w.network));
    // The wallet's network first: those are the addresses a send can reach.
    final networks = [
      current,
      ...SoqNetwork.values.where((n) => n != current),
    ];

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
                  if (!book.loaded)
                    _note('Reading the address book.')
                  else if (book.entries.isEmpty)
                    _note('No saved addresses yet. Save one below, or from '
                        'the SENT screen after a send.')
                  else
                    for (final network in networks)
                      if (book.on(network).isNotEmpty) ...[
                        _section('ON ${network.networkLabel}'),
                        for (final e in book.on(network)) _row(e),
                      ],
                  _section('ADD'),
                  _navTile(
                    Icons.add_circle_outline_rounded,
                    'Save an address',
                    'A name and a Soqucoin address',
                    _add,
                  ),
                  _note(
                    'The book is kept on this device only. It is not part of '
                    'the recovery phrase or the encrypted backup, and a wipe '
                    'removes it. A name is a label you chose: check the first '
                    'and last characters of the address before you send, '
                    'whatever it is called.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════ rows ════

  Widget _row(AddressBookEntry e) => _rowFrame(
        key: ValueKey('entry ${e.id}'),
        onTap: () => _show(e),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Instrument.readout, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(shortAddress(e.address),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Instrument.faint,
                          fontSize: 11,
                          fontFamily: kMono)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _rowAction(
                key: ValueKey('rename ${e.id}'),
                icon: Icons.edit_outlined,
                tooltip: 'Rename ${e.name}',
                onPressed: () => _rename(e)),
            _rowAction(
                key: ValueKey('remove ${e.id}'),
                icon: Icons.delete_outline_rounded,
                tooltip: 'Remove ${e.name}',
                onPressed: () => _remove(e)),
          ],
        ),
      );

  /// A real button: a screen reader names it after the entry, and a
  /// keyboard can reach and press it.
  Widget _rowAction({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) =>
      IconButton(
        key: key,
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        color: Instrument.faint,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        constraints: const BoxConstraints(),
      );

  /// The whole address, for reading off or copying. A row shows the first
  /// and last of it; this is where it is checked in full.
  Future<void> _show(AddressBookEntry e) => showDialog<void>(
        context: context,
        builder: (ctx) => InstrumentPanel(
          title: e.name,
          actions: [
            InstrumentDialogAction(
                label: 'CLOSE', onPressed: () => Navigator.pop(ctx)),
            InstrumentDialogAction(
              label: 'COPY',
              primary: true,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: e.address));
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                _snack('Address copied');
              },
            ),
          ],
          children: [
            Text(e.address,
                key: const Key('entry-full-address'),
                style: const TextStyle(
                    color: Instrument.readout,
                    fontSize: 12,
                    fontFamily: kMono,
                    height: 1.5)),
            const SizedBox(height: 10),
            Text('ON ${e.network.networkLabel}',
                style: Instrument.eyebrow(size: 9)),
          ],
        ),
      );

  Future<void> _add() async {
    final entry = await showAddressEntryDialog(context);
    if (entry == null || !mounted) return;
    _snack('${entry.name} saved');
  }

  Future<void> _rename(AddressBookEntry e) async {
    final entry = await showAddressEntryDialog(context, rename: e);
    if (entry == null || !mounted) return;
    _snack('Renamed to ${entry.name}');
  }

  Future<void> _remove(AddressBookEntry e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => InstrumentPanel(
        title: 'Remove ${e.name}?',
        actions: [
          InstrumentDialogAction(
              label: 'CANCEL', onPressed: () => Navigator.pop(ctx)),
          InstrumentDialogAction(
              label: 'REMOVE',
              primary: true,
              onPressed: () => Navigator.pop(ctx, true)),
        ],
        children: [
          const Text(
              'The address leaves the book on this device. Nothing already '
              'sent is affected.',
              style: TextStyle(
                  color: Instrument.label, fontSize: 13, height: 1.45)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(addressBookProvider.notifier).remove(e.id);
      if (mounted) _snack('${e.name} removed');
    } catch (err) {
      debugPrint('AddressBook: remove failed: $err');
      if (mounted) _snack('The address book could not be written');
    }
  }

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
            Text('ADDRESS BOOK', style: Instrument.eyebrow(size: 11)),
          ],
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

  /// A row a keyboard reaches and activates, as it does the icons on it,
  /// and a screen reader reads as a button. No ink: the press tone is the
  /// raised panel, as on the buttons.
  Widget _rowFrame({required Widget child, VoidCallback? onTap, Key? key}) =>
      InkWell(
        key: key,
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Instrument.void2,
        focusColor: Instrument.void2,
        hoverColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: Instrument.line.withValues(alpha: 0.3),
                    width: 0.6)),
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
/// by. The whole string is behind the row; a row is for telling one saved
/// address from another.
String shortAddress(String address) => address.length <= 20
    ? address
    : '${address.substring(0, 10)}…${address.substring(address.length - 6)}';
