// PILOT — Activity on the "Instrument-grade. Quantum-austere." language.
//
// No hero figure — Activity IS the telemetry feed (the pilot's row,
// full-screen). SOQ history, newest first, each a precise telemetry line.
// Sync logic preserved (FN-18: a sync failure is shown distinctly from an
// empty wallet).
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../providers/wallet_provider.dart';

class ActivityPilotScreen extends ConsumerStatefulWidget {
  const ActivityPilotScreen({super.key});
  @override
  ConsumerState<ActivityPilotScreen> createState() =>
      _ActivityPilotScreenState();
}

class _ActivityPilotScreenState extends ConsumerState<ActivityPilotScreen> {
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // syncActivity() throws on backend/connectivity failure (FN-18).
      await ref.read(walletProvider.notifier).syncActivity();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            "Couldn't sync your activity. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(walletProvider).recentTransactions;
    final timeline = txs.map(_Entry.fromTx).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Day grouping: fold the (already newest-first) timeline into sections
    // under an eyebrow date header — TODAY / YESTERDAY / 'JUL 3' (year only
    // when not current). Items list interleaves String headers and _Entry rows.
    final items = <Object>[];
    String? lastDay;
    for (final e in timeline) {
      final day = _dayLabel(e.timestamp);
      if (day != lastDay) {
        items.add(day);
        lastDay = day;
      }
      items.add(e);
    }

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            const InstrumentDivider(inset: 22),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Instrument.signal,
                backgroundColor: Instrument.void2,
                child: timeline.isEmpty
                    ? _emptyish()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                        physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics()),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (_, i) {
                          final it = items[i];
                          return it is String
                              ? _dayHeader(it, first: i == 0)
                              : _row(it as _Entry);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Section header for a day bucket — calendar-day (not rolling-24h) local
  /// dates: TODAY, YESTERDAY, then 'JUL 3' (year appended only if not current).
  static String _dayLabel(DateTime ts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(ts.year, ts.month, ts.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    final base = '${months[ts.month - 1]} ${ts.day}';
    return ts.year == now.year ? base : '$base ${ts.year}';
  }

  Widget _dayHeader(String label, {required bool first}) => Padding(
        padding: EdgeInsets.only(top: first ? 4 : 18, bottom: 8),
        child: Text(label, style: Instrument.eyebrow(size: 10)),
      );

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
            Text('ACTIVITY', style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  // Empty / loading / error all share a scrollable centre so pull-to-refresh works.
  Widget _emptyish() => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Instrument.signalDim),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              _error != null
                                  ? Icons.cloud_off_rounded
                                  : Icons.receipt_long_outlined,
                              size: 28,
                              color: Instrument.faint),
                          const SizedBox(height: 16),
                          Text(
                              _error != null
                                  ? 'COULD NOT SYNC'
                                  : 'NO ACTIVITY YET',
                              style: Instrument.eyebrow(size: 11)),
                          const SizedBox(height: 10),
                          Text(
                              _error ??
                                  'Your history appears here once you send or receive.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Instrument.faint,
                                  fontSize: 12,
                                  height: 1.5)),
                          if (_error != null) ...[
                            const SizedBox(height: 18),
                            // Foundry .btn-sm secondary.
                            TextButton(
                              onPressed: _refresh,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                  side: BorderSide(
                                      color: Instrument.lineHi, width: 1),
                                ),
                              ),
                              child: const Text('RETRY',
                                  style: TextStyle(
                                      color: Instrument.readout,
                                      fontSize: 11,
                                      fontFamily: kMono,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 11 * 0.1)),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      );

  Widget _row(_Entry e) {
    final inbound = e.inbound;

    // Every row copies its hash (the long-standing telemetry-row gesture).
    void onTap() {
      Clipboard.setData(ClipboardData(text: e.txid));
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Hash copied', style: TextStyle(fontSize: 12)),
        backgroundColor: Instrument.void2,
        behavior: SnackBarBehavior.floating,
      ));
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Center(
                child: instrumentDot((inbound ? Instrument.signal : Instrument.label)
                    .withValues(alpha: 0.8)),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label,
                    style: const TextStyle(
                        color: Instrument.readout, fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(e.timeAgo,
                    style: const TextStyle(
                        color: Instrument.faint,
                        fontSize: 10.5,
                        fontFamily: kMono,
                        letterSpacing: 0.6)),
              ],
            ),
            const Spacer(),
            Text(e.amountLabel,
                style: TextStyle(
                    color: inbound ? Instrument.readout : Instrument.label,
                    fontSize: 13.5,
                    fontFamily: kMono)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 14, color: Instrument.faint),
          ],
        ),
      ),
    );
  }
}

/// One SOQ history row, with display already resolved.
class _Entry {
  final DateTime timestamp;
  final String label;
  final bool inbound;
  final String amountLabel;
  final String txid;
  const _Entry({
    required this.timestamp,
    required this.label,
    required this.inbound,
    required this.amountLabel,
    required this.txid,
  });

  factory _Entry.fromTx(WalletTransaction tx) {
    final inbound = tx.type != TxType.sent;
    final label = switch (tx.type) {
      TxType.sent => 'Sent',
      TxType.received => 'Received',
      TxType.faucet => 'Faucet', // stagenet rows stored by earlier builds
    };
    final sign = inbound ? '+' : '−';
    final amt = tx.amount.toStringAsFixed(tx.amount >= 1000 ? 0 : 2);
    return _Entry(
      timestamp: tx.timestamp,
      label: label,
      inbound: inbound,
      amountLabel: '$sign$amt SOQ',
      txid: tx.txid,
    );
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inMinutes < 60) return '${diff.inMinutes} MIN AGO';
    if (diff.inHours < 24) return '${diff.inHours} HR AGO';
    if (diff.inDays < 7) {
      return '${diff.inDays} DAY${diff.inDays > 1 ? 'S' : ''} AGO';
    }
    return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
  }
}
