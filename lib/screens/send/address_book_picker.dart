// The send screen's address book: a sheet listing the saved addresses on the
// wallet's network, one tap to put one in the recipient field. The book
// itself is managed on its own screen, a chip away.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/wallet_keys.dart';
import '../../providers/address_book_provider.dart';
import '../../theme/instrument.dart';
import '../address_book/address_book_screen.dart' show shortAddress;
import '../shell.dart';

/// The picker, on the root navigator so it covers the shell's tab bar.
/// Completes with the chosen address, or null.
Future<String?> showAddressBookPicker(
        BuildContext context, SoqNetwork network) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: kShellMaxWidth),
      backgroundColor: Instrument.void0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: Instrument.lineHi, width: 0.6),
      ),
      builder: (_) => AddressBookPicker(network: network),
    );

class AddressBookPicker extends ConsumerWidget {
  final SoqNetwork network;
  const AddressBookPicker({super.key, required this.network});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(addressBookProvider);
    final entries = book.on(network);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.55;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                    child: Text('ADDRESS BOOK',
                        style: Instrument.eyebrow(size: 11))),
                InstrumentActionChip(
                  key: const Key('picker-manage'),
                  label: 'Manage',
                  icon: Icons.tune_outlined,
                  onTap: () {
                    // The router, read before this sheet's context is gone.
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push('/address-book');
                  },
                ),
                IconButton(
                  key: const Key('picker-close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded,
                      color: Instrument.label, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (!book.loaded)
            _line('Reading the address book.')
          else if (entries.isEmpty)
            _line('No saved addresses on ${network.displayName}. Save one '
                'from the address book, or from the SENT screen after a send.')
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
                physics: const BouncingScrollPhysics(),
                children: [
                  for (final e in entries)
                    GestureDetector(
                      key: ValueKey('pick ${e.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(e.address),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: Instrument.line.withValues(alpha: 0.3),
                                  width: 0.6)),
                        ),
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
                    ),
                ],
              ),
            ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Instrument.faint, fontSize: 12, height: 1.5)),
      );
}
