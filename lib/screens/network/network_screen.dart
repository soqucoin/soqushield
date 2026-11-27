// PILOT — Network on the instrument language: the weather of the chain you
// are on and of the pools that mine it, read live from public endpoints.
//
// Figure: THE BLOCK CLOCK (theme/block_clock_figure.dart). Below it the
// chain's figures, the emission schedule at this height, and the pools that
// found the last 1,440 blocks on Mainnet, each with its share. Every number
// is the node's or the public explorer's own; the emission constants cite
// the node's source (services/emission.dart). Nothing here holds an account
// or a key: a pool pays its members to their own addresses later, and this
// screen only reads what the chain shows.
//
// On Mainnet, until this install has seen the node answer, the status reads
// OFFLINE with the connecting line, the clock is dashed, the schedule reads
// from genesis, and the pools section waits. After the first answer an
// unreachable Mainnet is an outage.
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
import '../../theme/network_motion.dart';

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

  /// The rows the scanner can pick up and the pick they listen to.
  final ScanRegistry _registry = ScanRegistry();

  /// Bumped once per reveal: the figures' first arrival, a pull to refresh.
  final ValueNotifier<int> _revealTrigger = ValueNotifier<int>(0);
  bool _revealed = false;

  /// One reveal of the figures, on their first arrival and on a refresh.
  void _reveal() {
    _revealed = true;
    _revealTrigger.value++;
  }

  /// The pools dot's flare as an update lands; the figures last shown.
  late final AnimationController _poolFlare =
      AnimationController(vsync: this, duration: MotionTiming.poolFlare);
  String? _poolKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-flare: the dot rests at once.
    if (reducedMotion && _poolFlare.isAnimating) {
      _poolFlare.stop();
      _poolFlare.value = 0;
    }
  }
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
      if (!mounted) return;
      fireFigure(1, haptic: false);
      // Figures already there on entry arrive for the eye now.
      if (!_revealed &&
          (ref.read(chainWeatherProvider).asData?.value.reachable ?? false)) {
        _reveal();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _revealTrigger.dispose();
    _poolFlare.dispose();
    _registry.dispose();
    disposeFigure();
    super.dispose();
  }

  Future<void> _refresh() async {
    // The pools poll restarts; the chain poll ticks on its own period.
    ref.invalidate(poolsWeatherProvider);
    try {
      await ref.read(poolsWeatherProvider.future);
    } catch (_) {}
    if (mounted) _reveal();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final chainAsync = ref.watch(chainWeatherProvider);
    final poolsAsync = ref.watch(poolsWeatherProvider);
    final seenLive = ref.watch(mainnetSeenLiveProvider);

    // A new block runs the billet round the clock.
    ref.listen(chainWeatherProvider, (previous, next) {
      final before = previous?.asData?.value.height ?? 0;
      final after = next.asData?.value.height ?? 0;
      if (after > before && before > 0) fireFigure(1, haptic: false);
      // The figures' first arrival: the reveal, once.
      if (!_revealed && (next.asData?.value.reachable ?? false)) _reveal();
    });
    // An event in the pools' figures: the dot flares once. The key holds
    // the pools and the shares the card renders (poolsFigureKey); the first
    // answer of a visit is an arrival.
    ref.listen(poolsWeatherProvider, (previous, next) {
      final pools = next.asData?.value;
      if (pools == null || !pools.reachable) return;
      final key = poolsFigureKey(pools);
      final before = _poolKey;
      _poolKey = key;
      if (before == null || before == key) return;
      if (!reducedMotion) _poolFlare.forward(from: 0);
    });

    final chainOrNull = chainAsync.asData?.value;
    final loading = chainOrNull == null && chainAsync.isLoading;
    final live = chainOrNull != null && chainOrNull.reachable;
    // Read only under `live`, which implies the value is there.
    final chain = chainOrNull ?? ChainWeather.unreachable(DateTime.now());
    final mainnet = wallet.network == SoqNetwork.mainnet;
    // Mainnet never answered on this install yet: connecting.
    final waiting = mainnet && !live && !loading && !seenLive;
    // Mainnet answered before and does not now: an outage.
    final reconnecting = mainnet && !live && !loading && seenLive;
    final now = DateTime.now();
    final since = live ? chain.sinceTip(now) : Duration.zero;
    // A clock needs a tip time and a figure no older than the poll period: a
    // watcher returning after a long pause reads the last figure until the
    // next tick, and that figure must not count as a stalled chain.
    final clocked = live &&
        chain.tipTime != null &&
        now.difference(chain.fetchedAt) < pollPeriod * 1.5;
    // A figure fresh enough to lend its hashrate to the pools' shares: the
    // clock's own age limit, so a figure kept over a long pause does not.
    final fresh = live && now.difference(chain.fetchedAt) < pollPeriod * 1.5;

    final (statusText, statusColor) = loading
        ? ('SOQUCOIN · ML-DSA-44 · SYNCING', Instrument.label)
        : live
            ? ('SOQUCOIN · ML-DSA-44 · LIVE', Instrument.signal)
            : ('SOQUCOIN · ML-DSA-44 · OFFLINE', Instrument.faint);

    // The pools report on the chain they mine: Mainnet once Mainnet is
    // live, Stagenet until an install has seen Mainnet live.
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
                  ? _line('Connecting to Mainnet. The network and pool '
                      'figures appear here once it answers.')
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
                  builder: (_, _) {
                    // The fraction is read per frame, so the head sits at
                    // the true elapsed fraction between the timer's ticks.
                    final frameSince = clocked
                        ? chain.sinceTip(DateTime.now())
                        : Duration.zero;
                    return SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: BlockClockPainter(
                        breath: breath.value,
                        pulse: pulseValue,
                        live: live,
                        fraction: clocked
                            ? frameSince.inMilliseconds /
                                Emission.targetSpacing.inMilliseconds
                            : 0,
                        motion: clocked && !reducedMotion,
                        targetSeconds:
                            Emission.targetSpacing.inSeconds.toDouble(),
                        centreValue: clocked ? fmtClock(frameSince) : '—',
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
                  );
                  },
                ),
              ),
            ),
            // The weather in words: one sentence under the clock.
            _weather(live, loading, clocked, since,
                showPool ? poolsAsync : null),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: Instrument.signal,
                backgroundColor: Instrument.void2,
                // The scanline over the figures: the reveal as they arrive,
                // the finger that reads them. The list scrolls as before.
                child: ScanScope(
                  registry: _registry,
                  child: ScanOverlay(
                    registry: _registry,
                    revealTrigger: _revealTrigger,
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
                      // The hashrate the shares are read against is
                      // Mainnet's, read within the poll period: on Stagenet
                      // (an install that has not seen Mainnet live) and on a
                      // figure kept over a pause the rows show the shares
                      // alone.
                      _poolsCard(poolsAsync, mainnet && fresh ? chain : null)
                    else if (mainnet && !live)
                      _Card(
                        id: 'pools',
                        label: 'POOLS',
                        headline: 'WAITING FOR THE NETWORK',
                        open: _open.contains('pools'),
                        onToggle: () => _toggle('pools'),
                        children: [
                          _note('The pools report on the chain they mine. '
                              'Who found its last ${fmtInt(kPoolsWindow)} '
                              'blocks appears here once Mainnet answers.'),
                        ],
                      ),
                  ],
                ),
                  ),
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
  /// its target spacing, and who found the last blocks when the pools are
  /// shown. Each sentence states only what was read; with nothing read,
  /// nothing (the cards carry the syncing and did-not-answer states
  /// themselves).
  Widget _weather(bool live, bool loading, bool clocked, Duration since,
      AsyncValue<PoolsWeather>? poolsAsync) {
    final parts = <String>[];
    if (live && clocked) {
      final f = since.inMilliseconds / Emission.targetSpacing.inMilliseconds;
      parts.add(f <= 1.0
          ? 'Blocks are arriving on time.'
          : f <= 2.0
              ? 'The next block is a little late.'
              : 'The next block is running late.');
    }
    final pools = poolsAsync?.asData?.value;
    if (pools != null && pools.reachable && pools.pools.isNotEmpty) {
      final top = pools.pools.first;
      final count = pools.groupCount;
      final blocks = fmtInt(pools.blocks);
      parts.add(count == 1
          ? '${top.label} found all of the last $blocks blocks.'
          : '$count pools found the last $blocks blocks; ${top.label} '
              'found ${fmtShare(pools.shareOf(top))}.');
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
  /// change. With no height on Mainnet (not yet answered on this install),
  /// the schedule reads from genesis; on an unreachable Stagenet it reads
  /// dashes.
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

  /// The pools' card: how many are mining beside the label, the two
  /// biggest shares on one line, and inside, the listed pools with their
  /// shares and the hashrate each share stands for. [chain] is the fresh
  /// Mainnet figure the hashrate is taken from, or null without one.
  Widget _poolsCard(AsyncValue<PoolsWeather> poolsAsync, ChainWeather? chain) {
    final pools = poolsAsync.asData?.value;
    if (pools == null || !pools.reachable) {
      final text = pools == null && poolsAsync.isLoading
          ? 'Reading the explorer.'
          : 'The explorer did not answer.';
      return _Card(
        id: 'pools',
        label: 'POOLS',
        headline: text.toUpperCase().replaceAll('.', ''),
        open: _open.contains('pools'),
        onToggle: () => _toggle('pools'),
        children: [_note(text)],
      );
    }
    final list = pools.pools;
    final count = pools.groupCount;
    final headline = list.isEmpty
        ? 'NO BLOCKS GROUPED'
        : [
            for (final p in list.take(2))
              '${p.label.toUpperCase()} ${fmtShare(pools.shareOf(p))}',
            if (count > 2) '${fmtInt(count - 2)} MORE',
          ].join(' · ');
    return _Card(
      id: 'pools',
      label: 'POOLS',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        PoolDot(up: list.isNotEmpty, breath: breath, flare: _poolFlare),
        const SizedBox(width: 7),
        Text('${fmtInt(count)} MINING', style: Instrument.eyebrow(size: 9.5)),
      ]),
      headline: headline,
      sub: 'BLOCKS ${fmtInt(pools.startHeight)} TO ${fmtInt(pools.endHeight)} · '
          'MAINNET',
      open: _open.contains('pools'),
      onToggle: () => _toggle('pools'),
      children: _poolRows(pools, chain),
    );
  }

  List<Widget> _poolRows(PoolsWeather pools, ChainWeather? chain) {
    // The network hashrate the shares are read against: the node's own
    // estimate, when the chain is read and the figure is a figure.
    final network = chain != null && chain.reachable && chain.hashrate > 0
        ? chain.hashrate
        : null;
    return [
      for (final (i, p) in pools.pools.indexed)
        _PoolRow(
          index: i,
          label: p.label.toUpperCase(),
          share: fmtShare(pools.shareOf(p)),
          blocks: '${fmtInt(p.blocks)} ${p.blocks == 1 ? 'BLOCK' : 'BLOCKS'}',
          hashrate: network == null
              ? null
              : '~${fmtHashrate(network * pools.shareOf(p))}',
        ),
      if (pools.unlisted > 0)
        _note('The ${fmtInt(pools.pools.length)} biggest pools are listed; '
            '${fmtInt(pools.unlisted)} more found a block, counted in the '
            'shares.'),
      _note('The explorer groups these blocks by the address each one pays '
          'its reward to, a pool\'s own, and names the pools it knows. A '
          'pool\'s hashrate is its share of the blocks times the network\'s '
          'hashrate: an estimate. Pool members are never visible; this '
          'screen reads only what the chain shows.'),
    ];
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: Instrument.faint, fontSize: 11, height: 1.5)),
      );
}

/// The pools' figures whose change is an event, as the card renders them:
/// the pools in order and each one's share as shown, to the percent. The
/// block counts and the window's heights move at every poll by nature (a
/// block lands every minute) and are not events; a raw change that renders
/// the same is no change. The poll's read time is not a figure.
String poolsFigureKey(PoolsWeather pools) => [
      for (final p in pools.pools) '${p.label} ${fmtShare(pools.shareOf(p))}',
    ].join('\n');

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
            child: ScanRowBox(
              id: 'card $id',
              section: id,
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
                          child: ScanLit(
                              id: 'card $id',
                              text: headline,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontFamily: kMono,
                                  fontWeight: FontWeight.w500),
                              color: Instrument.readout,
                              litColor: Instrument.leadEdge),
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
      ? _CardScope(
          id: id,
          child: Semantics(
            explicitChildNodes: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        )
      : const SizedBox(width: double.infinity, height: 0);
}

/// The card a figure sits in, for the scanner's rows and crossings.
class _CardScope extends InheritedWidget {
  final String id;
  const _CardScope({required this.id, required super.child});
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardScope>()?.id;
  @override
  bool updateShouldNotify(_CardScope old) => old.id != id;
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
  Widget build(BuildContext context) {
    // A row the scanner can pick up: the label brightens and the value
    // crests while the finger is on it.
    final section = _CardScope.of(context) ?? '';
    final id = '$section/$label';
    final eyebrow = Instrument.eyebrow(size: 9);
    return ScanRowBox(
      id: id,
      section: section,
      child: MergeSemantics(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScanLit(
              id: id,
              text: label,
              style: eyebrow,
              color: eyebrow.color ?? Instrument.label,
              litColor: Instrument.readout),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ScanLit(
                id: id,
                text: value,
                style: const TextStyle(
                    fontSize: 15,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w500),
                color: Instrument.readout,
                litColor: Instrument.leadEdge),
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
      )));
  }
}

/// One pool: its label and the hashrate its share stands for on the left,
/// its share and its block count on the right.
class _PoolRow extends StatelessWidget {
  final int index;
  final String label;
  final String share;
  final String blocks;
  final String? hashrate;
  const _PoolRow({
    required this.index,
    required this.label,
    required this.share,
    required this.blocks,
    this.hashrate,
  });
  @override
  Widget build(BuildContext context) {
    // Keyed by position: two groups may render the same label, and a key
    // must not repeat.
    final section = _CardScope.of(context) ?? '';
    final id = '$section/pool $index';
    const faint = TextStyle(
        color: Instrument.faint,
        fontSize: 9.5,
        fontFamily: kMono,
        letterSpacing: 0.4);
    return ScanRowBox(
      id: id,
      section: section,
      child: MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: SizedBox(
                  width: 14,
                  child: Center(
                      child: instrumentDot(
                          Instrument.signal.withValues(alpha: 0.8), size: 4))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScanLit(
                      id: id,
                      text: label,
                      style: const TextStyle(fontSize: 13.5, fontFamily: kMono),
                      color: Instrument.readout,
                      litColor: Instrument.leadEdge),
                  if (hashrate != null) ...[
                    const SizedBox(height: 3),
                    Text(hashrate!, style: faint),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ScanLit(
                    id: id,
                    text: share,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontFamily: kMono,
                        fontWeight: FontWeight.w500),
                    color: Instrument.readout,
                    litColor: Instrument.leadEdge),
                const SizedBox(height: 3),
                Text(blocks, style: faint),
              ],
            ),
          ],
        ),
      )));
  }
}
