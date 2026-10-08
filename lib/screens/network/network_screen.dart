// PILOT — Network on the instrument language: the weather of the chain you
// are on and of the pool, read live from public endpoints.
//
// Figure: THE BLOCK CLOCK (theme/block_clock_figure.dart). Below it the
// chain's figures, the emission schedule at this height, the pool's public
// figures and the pool's latest blocks. Every number is the node's or the
// pool's own; the emission constants cite the node's source
// (services/emission.dart). Nothing here holds an account or a key: the pool
// pays its members to their own addresses, and this screen only reads what
// the pool publishes.
//
// On Mainnet before launch the node does not answer: the status reads
// OFFLINE with the waiting line, the clock is dashed, the schedule reads from
// genesis, and the pool section waits (the pool reports on the chain it
// mines, which is not yet this one).
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/wallet_keys.dart';
import '../../providers/launch_state_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/weather_provider.dart';
import '../../services/emission.dart';
import '../../services/weather_service.dart';
import '../../theme/block_clock_figure.dart';
import '../../theme/fmt.dart';
import '../../theme/instrument.dart';
import '../../theme/motion.dart';

class NetworkPilotScreen extends ConsumerStatefulWidget {
  const NetworkPilotScreen({super.key});
  @override
  ConsumerState<NetworkPilotScreen> createState() => _NetworkPilotScreenState();
}

class _NetworkPilotScreenState extends ConsumerState<NetworkPilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  /// The clock face advances every second between polls.
  Timer? _tick;

  /// The cards a tap has opened on this visit; closed again on a second tap.
  final Set<String> _open = {};
  void _toggle(String id) => setState(() {
        if (!_open.remove(id)) _open.add(id);
      });

  @override
  void initState() {
    super.initState();
    initFigure();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fireFigure(1, haptic: false);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    disposeFigure();
    super.dispose();
  }

  Future<void> _refresh() async {
    // The pool poll restarts; the chain poll ticks on its own period.
    ref.invalidate(poolWeatherProvider);
    try {
      await ref.read(poolWeatherProvider.future);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final chainAsync = ref.watch(chainWeatherProvider);
    final poolAsync = ref.watch(poolWeatherProvider);
    final seenLive = ref.watch(mainnetSeenLiveProvider);

    // A new block runs the billet round the clock.
    ref.listen(chainWeatherProvider, (previous, next) {
      final before = previous?.asData?.value.height ?? 0;
      final after = next.asData?.value.height ?? 0;
      if (after > before && before > 0) fireFigure(1, haptic: false);
    });

    final chainOrNull = chainAsync.asData?.value;
    final loading = chainOrNull == null && chainAsync.isLoading;
    final live = chainOrNull != null && chainOrNull.reachable;
    // Read only under `live`, which implies the value is there.
    final chain = chainOrNull ?? ChainWeather.unreachable(DateTime.now());
    final mainnet = wallet.network == SoqNetwork.mainnet;
    // Mainnet before launch: the endpoints do not answer yet.
    final waiting = mainnet && !live && !loading && !seenLive;
    // Mainnet after launch, not answering: an outage.
    final reconnecting = mainnet && !live && !loading && seenLive;
    final now = DateTime.now();
    final since = live ? chain.sinceTip(now) : Duration.zero;
    // A clock needs a tip time and a figure no older than the poll period: a
    // watcher returning after a long pause reads the last figure until the
    // next tick, and that figure must not count as a stalled chain.
    final clocked = live &&
        chain.tipTime != null &&
        now.difference(chain.fetchedAt) < pollPeriod * 1.5;

    final (statusText, statusColor) = loading
        ? ('SOQUCOIN · ML-DSA-44 · SYNCING', Instrument.label)
        : live
            ? ('SOQUCOIN · ML-DSA-44 · LIVE', Instrument.signal)
            : ('SOQUCOIN · ML-DSA-44 · OFFLINE', Instrument.faint);

    // The pool reports on the chain it mines: Mainnet once Mainnet is live,
    // Stagenet until an install has seen Mainnet live.
    final showPool = live && (mainnet || !seenLive);

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            InstrumentStatusBar(text: statusText, dotColor: statusColor),
            // A fixed slot keeps the hero in place; it grows only for a
            // wrapped line at a large system text size.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: waiting
                  ? _line('Mainnet opens at launch. The network and pool '
                      'figures appear here then.')
                  : reconnecting
                      ? _line('Reconnecting to the network.')
                      : const SizedBox.shrink(),
            ),
            // The clock is painted, so its figures are spoken from one label
            // (to the minute, so a focused reading holds still); the same
            // figures stand as text, at the system size, in the grid below.
            Semantics(
              container: true,
              excludeSemantics: true,
              label: _clockLabel(live, loading, clocked, since, chain),
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: figureListenable,
                  builder: (_, _) => SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: BlockClockPainter(
                        breath: breath.value,
                        pulse: pulseValue,
                        live: live,
                        fraction: clocked
                            ? since.inMilliseconds /
                                Emission.targetSpacing.inMilliseconds
                            : 0,
                        centreValue: clocked ? fmtClock(since) : '—',
                        centreSub: live
                            ? 'SINCE LAST BLOCK'
                            : loading
                                ? 'SYNCING'
                                : 'OFFLINE',
                        leftValue: live ? 'BLOCK ${fmtInt(chain.height)}' : 'BLOCK —',
                        leftSub: 'HEIGHT',
                        rightValue: live ? fmtHashrate(chain.hashrate) : '—',
                        rightSub: 'NETWORK HASHRATE',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The weather in words: one sentence under the clock.
            _weather(live, loading, clocked, since,
                showPool ? poolAsync : null),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Instrument.signal,
                backgroundColor: Instrument.void2,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  children: [
                    const InstrumentDivider(),
                    // Three cards, each a one-line summary; a tap opens the
                    // full figures. Where the chain is, when it last moved,
                    // how hard it works, how connected the node is.
                    _Card(
                      id: 'chain',
                      label:
                          'CHAIN · ${wallet.network.displayName.toUpperCase()}',
                      headline: live
                          ? (chain.tipTime != null
                              ? 'LAST BLOCK ${fmtUtcTime(chain.tipTime!)}'
                              : 'LAST BLOCK —')
                          : loading
                              ? 'SYNCING'
                              : 'OFFLINE',
                      sub: live
                          ? 'DIFFICULTY ${fmtDifficulty(chain.difficulty)} · '
                              'MEMPOOL ${fmtInt(chain.mempoolTx)} TX · '
                              '${fmtInt(chain.peers)} PEERS'
                          : null,
                      open: _open.contains('chain'),
                      onToggle: () => _toggle('chain'),
                      children: [
                        _StatGrid(children: [
                          _Stat('HEIGHT', live ? fmtInt(chain.height) : '—'),
                          _Stat(
                              'LAST BLOCK',
                              live && chain.tipTime != null
                                  ? fmtUtcTime(chain.tipTime!)
                                  : '—',
                              sub:
                                  'TARGET SPACING ${Emission.targetSpacing.inSeconds} S'),
                          _Stat('HASHRATE',
                              live ? fmtHashrate(chain.hashrate) : '—'),
                          _Stat('DIFFICULTY',
                              live ? fmtDifficulty(chain.difficulty) : '—'),
                          _Stat('MEMPOOL',
                              live ? '${fmtInt(chain.mempoolTx)} TX' : '—'),
                          _Stat('PEERS', live ? fmtInt(chain.peers) : '—'),
                        ]),
                      ],
                    ),
                    const InstrumentDivider(),
                    _Card(
                      id: 'emission',
                      label: 'EMISSION',
                      headline: _emissionHeadline(live ? chain.height : null,
                          fromGenesis: mainnet && !live),
                      sub: _emissionSub(live ? chain.height : null,
                          fromGenesis: mainnet && !live),
                      open: _open.contains('emission'),
                      onToggle: () => _toggle('emission'),
                      children: _emission(live ? chain.height : null,
                          fromGenesis: mainnet && !live),
                    ),
                    const InstrumentDivider(),
                    if (showPool)
                      _poolCard(poolAsync, now)
                    else if (mainnet && !live)
                      _Card(
                        id: 'pool',
                        label: 'SOQUPOOL',
                        headline: 'OPENS AT MAINNET LAUNCH',
                        open: _open.contains('pool'),
                        onToggle: () => _toggle('pool'),
                        children: [
                          _note('The pool reports on the chain it mines. Its '
                              'figures appear here when Mainnet opens.'),
                        ],
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

  /// What a screen reader says for the painted clock.
  static String _clockLabel(bool live, bool loading, bool clocked,
      Duration since, ChainWeather chain) {
    if (!live) return 'Block clock ${loading ? 'syncing' : 'offline'}.';
    final sinceText =
        clocked ? '${fmtSpokenSince(since)} since the last block' : 'No clock';
    return '${sinceText[0].toUpperCase()}${sinceText.substring(1)}. '
        'Block ${fmtInt(chain.height)}. '
        'Network hashrate ${fmtHashrate(chain.hashrate)}.';
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.only(left: 35, right: 22, top: 4),
        child: Text(text,
            maxLines: 2,
            style: const TextStyle(
                color: Instrument.faint, fontSize: 10.5, height: 1.2)),
      );

  /// The weather in words, under the clock: how the chain is doing against
  /// its target spacing, and how the pool is doing when the pool is shown.
  /// Each sentence states only what was read; with nothing read, nothing
  /// (the cards carry the syncing and did-not-answer states themselves).
  Widget _weather(bool live, bool loading, bool clocked, Duration since,
      AsyncValue<PoolWeather>? poolAsync) {
    final parts = <String>[];
    if (live && clocked) {
      final f = since.inMilliseconds / Emission.targetSpacing.inMilliseconds;
      parts.add(f <= 1.0
          ? 'Blocks are arriving on time.'
          : f <= 2.0
              ? 'The next block is a little late.'
              : 'The next block is running late.');
    }
    final pool = poolAsync?.asData?.value;
    if (pool != null && pool.reachable) {
      if (pool.overall == 'operational') {
        final miners = pool.activeMiners;
        parts.add(miners == null
            ? 'SOQUPOOL is operational.'
            : 'SOQUPOOL is operational with ${fmtInt(miners)} '
                '${miners == 1 ? 'miner' : 'miners'}.');
      } else {
        parts.add('SOQUPOOL reports ${pool.overall ?? 'no status'}.');
      }
    }
    if (parts.isEmpty) return const SizedBox(height: 2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
      child: Text(parts.join(' '),
          key: const ValueKey('weather line'),
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Instrument.label, fontSize: 12, height: 1.4)),
    );
  }

  /// The emission card's one line: the reward this block pays.
  String _emissionHeadline(int? height, {required bool fromGenesis}) {
    final h = height ?? (fromGenesis ? 0 : null);
    if (h == null) return '—';
    final reward = Emission.subsidyAt(h);
    return '${fmtInt(reward)} SOQ A BLOCK${height == null ? ' AT GENESIS' : ''}';
  }

  /// Under it: the next change and how far off it is.
  String? _emissionSub(int? height, {required bool fromGenesis}) {
    final h = height ?? (fromGenesis ? 0 : null);
    if (h == null) return null;
    final next = Emission.nextChangeAfter(h);
    if (next == null) return 'PERPETUAL TAIL · NO FURTHER CHANGE';
    final after = Emission.subsidyAt(next);
    return 'NEXT ${fmtInt(after)} SOQ IN ${fmtInt(next - h)} BLOCKS · '
        '${fmtEta(Emission.timeBetween(h, next))}';
  }

  /// The schedule at [height]: the reward this block pays and the next
  /// change. With no height on Mainnet before launch, the schedule reads
  /// from genesis; on an unreachable Stagenet it reads dashes.
  List<Widget> _emission(int? height, {required bool fromGenesis}) {
    final h = height ?? (fromGenesis ? 0 : null);
    if (h == null) {
      return const [
        _StatGrid(children: [
          _Stat('BLOCK REWARD', '—'),
          _Stat('NEXT CHANGE', '—'),
        ]),
      ];
    }
    final reward = Emission.subsidyAt(h);
    final next = Emission.nextChangeAfter(h);
    final rewardLabel = height == null ? 'BLOCK REWARD · GENESIS' : 'BLOCK REWARD';
    if (next == null) {
      return [
        _StatGrid(children: [
          _Stat(rewardLabel, '${fmtInt(reward)} SOQ', sub: 'PERPETUAL TAIL'),
          const _Stat('NEXT CHANGE', 'NONE'),
        ]),
      ];
    }
    final toGo = next - h;
    final after = Emission.subsidyAt(next);
    return [
      _StatGrid(children: [
        _Stat(rewardLabel, '${fmtInt(reward)} SOQ',
            sub: 'UNTIL BLOCK ${fmtInt(next)}'),
        _Stat('NEXT CHANGE', '${fmtInt(after)} SOQ',
            sub: '${fmtInt(toGo)} BLOCKS · '
                '${fmtEta(Emission.timeBetween(h, next))}'),
      ]),
    ];
  }

  /// The pool's card: the status beside the label, one line of the figures
  /// a miner asks for first, the full grid and the latest blocks inside.
  Widget _poolCard(AsyncValue<PoolWeather> poolAsync, DateTime now) {
    final pool = poolAsync.asData?.value;
    if (pool == null || !pool.reachable) {
      final text = pool == null && poolAsync.isLoading
          ? 'Reading the pool.'
          : 'The pool did not answer.';
      return _Card(
        id: 'pool',
        label: 'SOQUPOOL',
        headline: text.toUpperCase().replaceAll('.', ''),
        open: _open.contains('pool'),
        onToggle: () => _toggle('pool'),
        children: [_note(text)],
      );
    }
    String pct(double? v) => v != null && v.isFinite ? '${v.round()}%' : '—';
    String count(int? v) => v == null ? '—' : fmtInt(v);
    final eta = pool.nextPayoutEta;
    final etaShort = eta == null
        ? '—'
        : eta.contains(' (')
            ? eta.substring(0, eta.indexOf(' ('))
            : eta;
    final fee = pool.feeRate == null
        ? '—'
        : '${(pool.feeRate! * 100).toStringAsFixed(2)}%';
    final up = pool.overall == 'operational';
    final headline = [
      pool.activeMiners == null
          ? null
          : '${count(pool.activeMiners)} ${pool.activeMiners == 1 ? 'MINER' : 'MINERS'}',
      pool.blocksPerHour == null ? null : '${fmtInt(pool.blocksPerHour!)} BLOCKS / HR',
      pool.poolHashrate == null ? null : fmtHashrate(pool.poolHashrate!),
    ].whereType<String>().join(' · ');
    final sub = [
      pool.luck24h == null ? null : 'LUCK 24 H ${pct(pool.luck24h)}',
      pool.feeRate == null ? null : 'FEE $fee',
      eta == null ? null : 'NEXT PAYOUT $etaShort',
    ].whereType<String>().join(' · ');
    return _Card(
      id: 'pool',
      label: 'SOQUPOOL',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        instrumentDot(up ? Instrument.signal : Instrument.faint, size: 5),
        const SizedBox(width: 7),
        Text((pool.overall ?? '—').toUpperCase(),
            style: Instrument.eyebrow(size: 9.5)),
      ]),
      headline: headline.isEmpty ? '—' : headline,
      sub: sub.isEmpty ? null : sub,
      open: _open.contains('pool'),
      onToggle: () => _toggle('pool'),
      children: _poolFigures(pool, now, pct, count, etaShort, fee),
    );
  }

  List<Widget> _poolFigures(PoolWeather pool, DateTime now,
      String Function(double?) pct, String Function(int?) count,
      String etaShort, String fee) {
    return [
      _StatGrid(children: [
        _Stat('POOL HASHRATE',
            pool.poolHashrate == null ? '—' : fmtHashrate(pool.poolHashrate!)),
        _Stat('MINERS', count(pool.activeMiners),
            sub: pool.workers == null ? null : '${fmtInt(pool.workers!)} WORKERS'),
        _Stat('BLOCKS · 24 H', count(pool.blocks24h),
            sub: pool.blocksPerHour == null ? null : '${fmtInt(pool.blocksPerHour!)} / HR'),
        _Stat('LUCK · 24 H', pct(pool.luck24h),
            sub: pool.luck7d == null ? null : '7 D ${pct(pool.luck7d)}'),
        _Stat('ROUND EFFORT', pct(pool.roundEffortPct)),
        _Stat('NEXT PAYOUT', etaShort),
        _Stat('FEE', fee, sub: pool.scheme?.toUpperCase()),
        // Each region by name, the ones that are down marked, so a 2 OF 3
        // UP says which one is not.
        _Stat(
            'REGIONS',
            pool.regions.isEmpty
                ? '—'
                : '${pool.regions.where((r) => r.up).length} OF ${pool.regions.length} UP',
            sub: pool.regions.isEmpty
                ? null
                : pool.regions
                    .map((r) => r.up
                        ? r.region.toUpperCase()
                        : '${r.region.toUpperCase()} DOWN')
                    .join(' · ')),
      ]),
      _note('The pool pays its members to their own addresses. This screen '
          'reads only what the pool publishes.'),
      if (pool.latestBlocks.isNotEmpty) ...[
        const SizedBox(height: 6),
        const InstrumentDivider(),
        const _Section('LATEST BLOCKS'),
        for (final b in pool.latestBlocks.take(6))
          _BlockRow(height: b.height, ago: fmtAgo(now.difference(b.time))),
      ],
    ];
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Instrument.faint, fontSize: 11, height: 1.5)),
      );
}

/// A sub-heading inside a card (the latest blocks under the pool's figures).
class _Section extends StatelessWidget {
  final String label;
  const _Section(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(label, style: Instrument.eyebrow(size: 10)),
      );
}

/// One card of the weather: the eyebrow label with an optional status beside
/// it, a one-line summary and an optional second line, always visible; the
/// full figures under them on a tap, closed again on the next. The chevron
/// turns with the state; under reduced motion the card opens at once.
class _Card extends StatelessWidget {
  final String id;
  final String label;
  final String headline;
  final String? sub;
  final Widget? trailing;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> children;
  const _Card({
    required this.id,
    required this.label,
    required this.headline,
    this.sub,
    this.trailing,
    required this.open,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final duration = reducedMotionOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // One node for a screen reader: the label, the lines and the state,
        // with the tap as its action; the texts under it are not read twice.
        Semantics(
          container: true,
          button: true,
          expanded: open,
          label: '$label. $headline.${sub == null ? '' : ' $sub.'} '
              '${open ? 'Open' : 'Closed'}.',
          onTap: onToggle,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('card $id'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(label, style: Instrument.eyebrow(size: 10)),
                          if (trailing != null) ...[
                            const SizedBox(width: 10),
                            // The status scales down beside a long label
                            // at a large text size rather than overflow.
                            Flexible(
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: trailing!),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 7),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(headline,
                              style: const TextStyle(
                                  color: Instrument.readout,
                                  fontSize: 13.5,
                                  fontFamily: kMono,
                                  fontWeight: FontWeight.w500)),
                        ),
                        if (sub != null) ...[
                          const SizedBox(height: 4),
                          Text(sub!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Instrument.faint,
                                  fontSize: 9.5,
                                  fontFamily: kMono,
                                  letterSpacing: 0.4)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.expand_more_rounded,
                          size: 18, color: Instrument.label),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The open body's figures are their own nodes for a screen reader,
        // after the header (each stat and each block row merges into one).
        // Under reduced motion the body is laid out at once, with no size
        // animation at all (a zero-duration one re-dirties its own layout).
        if (reducedMotionOf(context))
          _body()
        else
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _body(),
          ),
      ],
    );
  }

  Widget _body() => open
      ? Semantics(
          explicitChildNodes: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        )
      : const SizedBox(width: double.infinity, height: 0);
}

/// Two stat blocks a row: an eyebrow, a mono value, an optional sub line.
class _StatGrid extends StatelessWidget {
  final List<_Stat> children;
  const _StatGrid({required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          const gap = 12.0;
          final w = (c.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: 14,
            children: [
              for (final s in children) SizedBox(width: w, child: s),
            ],
          );
        },
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  const _Stat(this.label, this.value, {this.sub});
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Instrument.eyebrow(size: 9)),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: Instrument.readout,
                    fontSize: 15,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w500)),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Instrument.faint,
                    fontSize: 9.5,
                    fontFamily: kMono,
                    letterSpacing: 0.4)),
          ],
        ],
      ));
}

class _BlockRow extends StatelessWidget {
  final int height;
  final String ago;
  const _BlockRow({required this.height, required this.ago});
  @override
  Widget build(BuildContext context) => MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
                width: 14,
                child: Center(
                    child: instrumentDot(
                        Instrument.signal.withValues(alpha: 0.8), size: 4))),
            const SizedBox(width: 10),
            Text(fmtInt(height),
                style: const TextStyle(
                    color: Instrument.readout, fontSize: 13.5, fontFamily: kMono)),
            const Spacer(),
            Text(ago,
                style: const TextStyle(
                    color: Instrument.faint,
                    fontSize: 10.5,
                    fontFamily: kMono,
                    letterSpacing: 0.6)),
          ],
        ),
      ));
}
