// Activity detail — one transaction from the Activity feed: its direction,
// the amount to the satoshi (to the cent from 67,108,864 SOQ, fmt.dart
// fmtDetailAmount), the date, the network and the full hash, with a copy
// action and, where a public explorer reads the network, a link to the
// transaction's page there.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/txid.dart';
import '../../models/wallet_keys.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/fmt.dart';
import '../../theme/instrument.dart';
import '../shell.dart';

final _date = DateFormat('MMM d, y');

/// The explorer page for [txid], or null when no public explorer reads
/// [network] or the hash is not 64 hex characters. The hash comes from a
/// remote service (the history service, or the node's reply to a broadcast),
/// so it is checked before it becomes part of a link.
Uri? explorerTxUrl(String txid, SoqNetwork network) {
  final base = network.explorerUrl;
  if (base == null || !isTxid(txid)) return null;
  return Uri.parse('$base/tx/${txid.toLowerCase()}');
}

/// Opens the detail sheet for [tx] over the whole screen. Activity sits in the
/// shell's navigator, under the tab bar and the shell's SnackBars; the root
/// navigator puts the sheet over both.
Future<void> showActivityDetail(
        BuildContext context, WalletTransaction tx, SoqNetwork network) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      constraints: const BoxConstraints(maxWidth: kShellMaxWidth),
      backgroundColor: Instrument.void2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: Instrument.lineHi, width: 0.6),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityDetailSheet(tx: tx, network: network),
    );

class ActivityDetailSheet extends StatefulWidget {
  final WalletTransaction tx;
  final SoqNetwork network;
  const ActivityDetailSheet(
      {super.key, required this.tx, required this.network});

  /// The transaction's explorer page, or null where there is none.
  Uri? get explorerUrl => explorerTxUrl(tx.txid, network);

  @override
  State<ActivityDetailSheet> createState() => _ActivityDetailSheetState();
}

class _ActivityDetailSheetState extends State<ActivityDetailSheet> {
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  // The confirmation shows on the button itself: a SnackBar would sit under
  // this sheet, which is on the root navigator above the shell.
  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.tx.txid));
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final inbound = tx.type != TxType.sent;
    final heading = switch (tx.type) {
      TxType.sent => 'SENT',
      TxType.received => 'RECEIVED',
      TxType.faucet => 'FAUCET',
    };
    final url = widget.explorerUrl;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading, style: Instrument.eyebrow()),
            const SizedBox(height: 12),
            // The row rounds; the sheet shows the amount to the satoshi below
            // kSatoshiExactLimit and to the cent above it, and a long one
            // scales down to fit rather than clipping.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('${inbound ? '+' : '−'}${fmtDetailAmount(tx.amount)}',
                      style: const TextStyle(
                          color: Instrument.readout,
                          fontSize: 30,
                          fontFamily: kMono,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -0.5)),
                  const SizedBox(width: 8),
                  Text(widget.network.ticker,
                      style: const TextStyle(
                          color: Instrument.signal,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.0)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const InstrumentDivider(),
            _field('DATE', _date.format(tx.timestamp).toUpperCase()),
            _field('NETWORK', widget.network.networkLabel),
            const InstrumentDivider(),
            const SizedBox(height: 18),
            Text('TRANSACTION HASH', style: Instrument.eyebrow(size: 10)),
            const SizedBox(height: 8),
            Text(tx.txid,
                style: const TextStyle(
                    color: Instrument.readout,
                    fontSize: 12,
                    fontFamily: kMono,
                    height: 1.5)),
            const SizedBox(height: 22),
            InstrumentButton(
              label: _copied ? 'Copied' : 'Copy hash',
              icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
              primary: false,
              onTap: _copy,
            ),
            if (url != null) ...[
              const SizedBox(height: 10),
              InstrumentButton(
                label: 'View on explorer',
                icon: Icons.open_in_new_rounded,
                primary: true,
                onTap: () =>
                    launchUrl(url, mode: LaunchMode.externalApplication),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(label, style: Instrument.eyebrow(size: 10)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      color: Instrument.readout,
                      fontSize: 12.5,
                      fontFamily: kMono)),
            ),
          ],
        ),
      );
}
