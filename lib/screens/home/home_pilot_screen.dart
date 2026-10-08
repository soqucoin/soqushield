// PILOT — Wallet (Home) on the "Instrument-grade. Quantum-austere." language.
//
// The machine is hidden, the hero is a living figure, and the layout is
// pinned (hero fixed, the feed scrolls in an Expanded — adding rows never
// reflows the hero).
//
// Figure: THE CUSTODY LINE — the answer to Home's glance-question: "is my
// quantum-safe key custodied on this device, and am I connected to the live
// chain?" A 2px run from the key-node (ML-DSA-44, on this device) through the
// signature gate to the chain-node (live block height + peers). LIVE = a
// copper run breathing at rest; SYNCING/OFFLINE = a dashed slate run. On
// settle/refresh a billet travels the line (in = chain→key, out = key→chain).
// Each new block sends a silent billet out; when it lands, brackets frame the
// height it carried and fade. Built to TxAnatomy's construction rules: solid
// uniform strokes, typographic stat blocks, a diamond gate, billet motion.
// Real data only — no decoration.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/figures.dart';
import '../../theme/fmt.dart';
import '../../theme/motion.dart';
import '../../models/wallet_keys.dart';
import '../../providers/launch_state_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/weather_provider.dart';
import '../../services/weather_service.dart';

class HomePilotScreen extends ConsumerStatefulWidget {
  const HomePilotScreen({super.key});
  @override
  ConsumerState<HomePilotScreen> createState() => _HomePilotScreenState();
}

class _HomePilotScreenState extends ConsumerState<HomePilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  bool _masked = false;

  /// The lock-on after a heartbeat: when the billet a new block sent reaches
  /// the chain node, brackets frame the height it carried, then fade.
  late final AnimationController _lockOn = AnimationController(
      vsync: this, duration: MotionTiming.converge + MotionTiming.fade);
  late final Listenable _heroListenable;
  bool _heartbeat = false;

  @override
  void initState() {
    super.initState();
    initFigure();
    _heroListenable = Listenable.merge([breath, pulse, _lockOn]);
    pulse.addStatusListener(_onPulseStatus);
    // The line "comes online" once when the wallet appears — a silent billet
    // out to the chain. It frames nothing: no block landed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fireFigure(1, haptic: false);
    });
  }

  @override
  void dispose() {
    _lockOn.dispose();
    disposeFigure();
    super.dispose();
  }

  /// A new block: the outward billet, silent, once per height increase. The
  /// first answer after loading or an outage is not a block.
  void _onChainStats(
      AsyncValue<NetworkStats>? previous, AsyncValue<NetworkStats> next) {
    final before = previous?.asData?.value.blocks ?? 0;
    final after = next.asData?.value.blocks ?? 0;
    if (after > before && before > 0) {
      _heartbeat = !reducedMotion;
      fireFigure(1, haptic: false);
    }
  }

  void _onPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final pending = _heartbeat;
    _heartbeat = false;
    // Only the heartbeat's own outward billet frames the height: a refresh
    // restarts the shared pulse inward, and that bead lands at the key.
    if (pending && figureDir > 0) _lockOn.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion) {
      // Reduced motion switched on mid-effect: the frame's end state is no
      // frame, and a pending heartbeat has nothing to land.
      _heartbeat = false;
      _lockOn.stop();
      _lockOn.value = 0;
    }
  }

  void _toggleMask() {
    // Masking only affects the HOLDINGS readout — the figure shows no
    // balance (key custody + chain state aren't private), so no fireFigure.
    HapticFeedback.selectionClick();
    setState(() => _masked = !_masked);
  }

  Future<void> _refresh() async {
    fireFigure(-1); // value settling in
    await ref.read(walletProvider.notifier).refreshBalance();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    ref.listen(networkStatsProvider, _onChainStats);
    final statsAsync = ref.watch(networkStatsProvider);

    // Never bounce while loading from storage.
    if (wallet.isLoading) return _loading();
    if (!wallet.hasWallet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/welcome');
      });
      return _loading();
    }

    // A poll that could not reach the node yields data with reachable false,
    // never an error, so OFFLINE is read from the flag.
    final (statusText, statusColor) = statsAsync.when(
      data: (s) => s.reachable
          ? ('SOQUCOIN · ML-DSA-44 · LIVE', Instrument.signal)
          : ('SOQUCOIN · ML-DSA-44 · OFFLINE', Instrument.faint),
      loading: () => ('SOQUCOIN · ML-DSA-44 · SYNCING', Instrument.label),
      error: (_, _) => ('SOQUCOIN · ML-DSA-44 · OFFLINE', Instrument.faint),
    );

    // The custody line's chain-side strings — same state source as the status
    // bar (networkStatsProvider), pre-formatted so the painter stays
    // presentational.
    final (chainValue, chainSub, chainLive) = statsAsync.when(
      data: (s) => s.reachable
          ? ('BLOCK ${fmtInt(s.blocks)}', 'LIVE · ${fmtInt(s.peers)} PEERS', true)
          : ('BLOCK —', 'OFFLINE', false),
      loading: () => ('BLOCK —', 'SYNCING', false),
      error: (_, _) => ('BLOCK —', 'OFFLINE', false),
    );

    // Mainnet before launch: the endpoints do not answer yet, so the status
    // reads OFFLINE. Say why, in one line under it. Once this install has
    // seen Mainnet answer, an OFFLINE is an outage and the line says that.
    // On Stagenet an OFFLINE is a real outage and stays bare.
    final reachable = statsAsync.when(
      data: (s) => s.reachable,
      loading: () => true,
      error: (_, _) => false,
    );
    final seenLive = ref.watch(mainnetSeenLiveProvider);
    final mainnetDown = wallet.network == SoqNetwork.mainnet && !reachable;
    final mainnetWaiting = mainnetDown && !seenLive;
    final mainnetReconnecting = mainnetDown && seenLive;

    final total = _masked
        ? '••••••'
        : wallet.displayBalance.toStringAsFixed(2);

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            InstrumentStatusBar(text: statusText, dotColor: statusColor),
            // A fixed slot under the status line, so the hero never moves
            // between states; the waiting line sits in it on Mainnet, and
            // the slot grows only for a wrapped line at a large text size.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: mainnetWaiting
                  ? _quietLine(
                      'Mainnet opens at launch. Your address is ready to receive.')
                  : mainnetReconnecting
                      ? _quietLine('Reconnecting to the network.')
                      : const SizedBox.shrink(),
            ),
            // ── HERO: the custody line — your key, the gate, the live chain ──
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _heroListenable,
                builder: (_, _) => SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: CustodyLinePainter(
                      breath: breath.value,
                      pulse: pulseValue,
                      dir: figureDir,
                      live: chainLive,
                      chainValue: chainValue,
                      chainSub: chainSub,
                      lockOn: _lockOn.isAnimating ? _lockOn.value : -1.0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // ── HOLDINGS readout — tap to mask ──
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMask,
              child: InstrumentReadout(
                label: 'HOLDINGS · ${wallet.network.ticker}',
                value: total,
                unit: wallet.network.ticker,
              ),
            ),
            if (wallet.hasPendingTx && !_masked) ...[
              const SizedBox(height: 10),
              _pendingLine(wallet),
            ],
            const SizedBox(height: 14),
            const InstrumentTrustBadge(
                icon: Icons.shield_outlined, text: 'QUANTUM-SECURED'),
            const SizedBox(height: 24),
            _primaryActions(),
            const SizedBox(height: 18),
            // ── FLEXIBLE FEED: asset, address, nudge, scrolls in place ──
            Expanded(child: _feed(wallet)),
          ],
        ),
      ),
    );
  }

  Widget _loading() => const Scaffold(
        backgroundColor: Instrument.void0,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Instrument.signalDim),
          ),
        ),
      );

  // The one line that explains a Mainnet OFFLINE; the Send screen and the
  // Field Manual say the same. Aligned with the status text (dot + gap).
  Widget _quietLine(String text) => Padding(
        padding: const EdgeInsets.only(left: 35, right: 22, top: 4),
        child: Text(
          text,
          maxLines: 2,
          style: const TextStyle(
              color: Instrument.faint, fontSize: 10.5, height: 1.2),
        ),
      );

  Widget _pendingLine(WalletState wallet) {
    final sign = wallet.pendingBalance > 0 ? '+' : '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(
              strokeWidth: 1.3, color: Instrument.signal.withValues(alpha: 0.7)),
        ),
        const SizedBox(width: 8),
        Text('$sign${wallet.pendingBalance.toStringAsFixed(2)} SETTLING',
            style: TextStyle(
                color: Instrument.signal.withValues(alpha: 0.85),
                fontSize: 10.5,
                fontFamily: kMono,
                letterSpacing: 1.8)),
      ],
    );
  }

  // ── two primary verbs ──
  Widget _primaryActions() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Expanded(
              child: InstrumentButton(
                label: 'Send',
                icon: Icons.north_east_rounded,
                primary: true,
                onTap: () => context.go('/send'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InstrumentButton(
                label: 'Receive',
                icon: Icons.south_west_rounded,
                primary: false,
                onTap: () => context.push('/receive'),
              ),
            ),
          ],
        ),
      );

  // ── the scrolling feed: the asset, the address, the backup nudge ──
  Widget _feed(WalletState wallet) {
    String n(double v, int dp) => _masked ? '••••' : v.toStringAsFixed(dp);

    return RefreshIndicator(
      onRefresh: _refresh,
      color: Instrument.signal,
      backgroundColor: Instrument.void2,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        children: [
          const InstrumentDivider(),
          const SizedBox(height: 12),
          Text('ASSETS', style: Instrument.eyebrow(size: 10)),
          const SizedBox(height: 8),
          _AssetRow(
            mark: AssetMark.node,
            markColor: Instrument.soq,
            name: wallet.network.ticker,
            balance: n(wallet.displayBalance, 2),
            onTap: () => context.go('/send'),
          ),
          const SizedBox(height: 18),
          if (wallet.address.isNotEmpty) _addressRow(wallet.address),
          if (wallet.hasWallet && !wallet.backupConfirmed) ...[
            const SizedBox(height: 12),
            _backupNudge(),
          ],
          const SizedBox(height: 18),
          const InstrumentDivider(),
          const SizedBox(height: 12),
          Text('NETWORK', style: Instrument.eyebrow(size: 10)),
          const SizedBox(height: 4),
          _networkRow(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The weather in one line: the height and the network hashrate from the
  /// app's chain poll, opening the Network screen.
  Widget _networkRow() {
    // Three states, as the status line: loading, live, not answering.
    final (text, live) = ref.watch(chainWeatherProvider).when(
          data: (c) => c.reachable
              ? ('BLOCK ${fmtInt(c.height)} · ${fmtHashrate(c.hashrate)}', true)
              : ('OFFLINE', false),
          loading: () => ('SYNCING', false),
          error: (_, _) => ('OFFLINE', false),
        );
    return GestureDetector(
      onTap: () => context.go('/network'),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(Icons.sensors,
                size: 14, color: live ? Instrument.signal : Instrument.faint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: live ? Instrument.readout : Instrument.faint,
                      fontSize: 12.5,
                      fontFamily: kMono,
                      letterSpacing: 0.3)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: Instrument.faint),
          ],
        ),
      ),
    );
  }

  Widget _addressRow(String address) {
    final short =
        '${address.substring(0, 10)}…${address.substring(address.length - 6)}';
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: address));
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address copied',
                style: TextStyle(fontSize: 12)),
            backgroundColor: Instrument.void2,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Row(
        children: [
          Icon(Icons.vpn_key_outlined, size: 13, color: Instrument.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(short,
                style: TextStyle(
                    color: Instrument.label,
                    fontSize: 12.5,
                    fontFamily: kMono,
                    letterSpacing: 0.3)),
          ),
          Icon(Icons.copy_outlined, size: 13, color: Instrument.faint),
        ],
      ),
    );
  }

  Widget _backupNudge() => GestureDetector(
        onTap: () => context.push('/seed-backup'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            color: Instrument.signal.withValues(alpha: 0.06),
            border: Border.all(
                color: Instrument.signal.withValues(alpha: 0.28), width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.priority_high_rounded,
                  size: 15, color: Instrument.signal),
              const SizedBox(width: 10),
              Text('BACK UP YOUR RECOVERY PHRASE',
                  style: Instrument.eyebrow(size: 11)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: Instrument.signal),
            ],
          ),
        ),
      );
}

// ── austere asset row ──
class _AssetRow extends StatelessWidget {
  final AssetMark mark;
  final Color markColor;
  final String name;
  final String balance;
  final VoidCallback? onTap;
  const _AssetRow({
    required this.mark,
    required this.markColor,
    required this.name,
    required this.balance,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Center(child: AssetGlyph(mark: mark, color: markColor)),
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: const TextStyle(
                      color: Instrument.readout,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(balance,
                  style: const TextStyle(
                      color: Instrument.readout,
                      fontSize: 14,
                      fontFamily: kMono)),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: Instrument.faint),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// THE CUSTODY LINE — Home's hero, built to TxAnatomy's construction rules
// (figures.dart): solid uniform strokes, typographic stat blocks, a diamond
// gate ON the run, billet motion. It answers one question at a glance:
//
//   [YOUR KEY]────────◆────────[SOQ L1]
//    ML-DSA-44      2,420 B    BLOCK n
//    on this device SIGNATURE  live · peers
//
//   • LIVE: the run is copper at full weight, breathing slowly at rest — you
//     are connected, value can pour. SYNCING/OFFLINE: a dashed slate run.
//   • the key-node and chain-node are SOQ violet (the key's metal).
//   • motion = one billet travelling the run (in = chain→key on settle,
//     out = key→chain), leadEdge crest + copper halo.
//
// Presentational only: the screen computes every string (real data — block
// height + peers from networkStatsProvider). No balance is shown, so the
// figure needs no mask-awareness.
// ─────────────────────────────────────────────────────────────────────────────
class CustodyLinePainter extends CustomPainter {
  final double breath;
  final double pulse;
  final int dir; // +1 out (key→chain), -1 in (chain→key)
  final bool live;
  final String chainValue; // 'BLOCK 12,345' or 'BLOCK —'
  final String chainSub; // 'LIVE · 8 PEERS' / 'SYNCING' / 'OFFLINE'
  final double lockOn; // 0..1 after a new block's billet lands, else < 0

  CustodyLinePainter({
    required this.breath,
    required this.pulse,
    required this.dir,
    required this.live,
    required this.chainValue,
    required this.chainSub,
    required this.lockOn,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cy = size.height * 0.48;
    final breathA = 0.5 + 0.5 * math.sin(breath * 2 * math.pi);

    // ── text helper: one style vocabulary, anchored, never floating ──
    TextPainter tp(String s, double fs, Color c,
        {String font = kMono, FontWeight fw = FontWeight.w400, double ls = 0}) {
      final t = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                color: c,
                fontSize: fs,
                fontFamily: font,
                fontWeight: fw,
                letterSpacing: ls)),
        textDirection: TextDirection.ltr,
      )..layout();
      return t;
    }

    // ── LEFT stat block: the key, custodied on this device ──
    final x0 = w * 0.055;
    final keyEyebrow =
        tp('YOUR KEY', 8.5, Instrument.label, font: kLabel, ls: 8.5 * 0.16);
    final keyValue =
        tp('ML-DSA-44', 12.5, Instrument.readout, fw: FontWeight.w600);
    final keySub = tp('ON THIS DEVICE · SELF-CUSTODY', 8, Instrument.label,
        font: kLabel, ls: 8 * 0.12);
    keyEyebrow.paint(canvas, Offset(x0, cy - 27));
    keyValue.paint(canvas, Offset(x0, cy - 8));
    keySub.paint(canvas, Offset(x0, cy + 12));

    // ── RIGHT stat block: the live chain, right-aligned ──
    final xr = w - x0;
    final chEyebrow =
        tp('SOQ L1', 8.5, Instrument.label, font: kLabel, ls: 8.5 * 0.16);
    final chValue =
        tp(chainValue, 12.5, Instrument.readout, fw: FontWeight.w600);
    final chSub =
        tp(chainSub, 8, Instrument.label, font: kLabel, ls: 8 * 0.12);
    chEyebrow.paint(canvas, Offset(xr - chEyebrow.width, cy - 27));
    chValue.paint(canvas, Offset(xr - chValue.width, cy - 8));
    chSub.paint(canvas, Offset(xr - chSub.width, cy + 12));

    // ── THE LINE: key-node → chain-node, spanning between the blocks ──
    final leftEdge = x0 +
        math.max(keyEyebrow.width, math.max(keyValue.width, keySub.width));
    final rightEdge =
        xr - math.max(chEyebrow.width, math.max(chValue.width, chSub.width));
    final lineX0 = leftEdge + 14;
    final lineX1 = rightEdge - 14;

    final run = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt;
    if (live) {
      // Connected: the run is copper, full weight, with a slow idle breath.
      run.color = Instrument.signal.withValues(alpha: 0.85 + 0.15 * breathA);
      canvas.drawLine(Offset(lineX0, cy), Offset(lineX1, cy), run);
    } else {
      // Not connected: a dashed slate run — the pour can't happen.
      run.color = Instrument.lineHi;
      double x = lineX0;
      while (x < lineX1) {
        canvas.drawLine(
            Offset(x, cy), Offset(math.min(x + 5.0, lineX1), cy), run);
        x += 10.0;
      }
    }

    // ── the signature gate — a diamond ON the run (every spend passes it) ──
    final gateX = (lineX0 + lineX1) / 2;
    Path dia(double cx, double r) => Path()
      ..moveTo(cx, cy - r)
      ..lineTo(cx + r, cy)
      ..lineTo(cx, cy + r)
      ..lineTo(cx - r, cy)
      ..close();
    const gr = 7.0;
    canvas.drawPath(
        dia(gateX, gr), Paint()..color = Instrument.void0); // punch out the run
    canvas.drawPath(
        dia(gateX, gr),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = (live ? Instrument.signal : Instrument.faint)
              .withValues(alpha: 0.75 + 0.25 * breathA));
    final sig = tp('2,420 B SIGNATURE', 7.5, Instrument.label,
        font: kLabel, ls: 7.5 * 0.10);
    sig.paint(canvas, Offset(gateX - sig.width / 2, cy + gr + 6));

    // ── the nodes — SOQ violet: a key-diamond and a chain-dot ──
    final node = Paint()..color = Instrument.soq;
    canvas.drawPath(dia(lineX0, 3.4), node);
    canvas.drawCircle(Offset(lineX1, cy), 3.0, node);

    // ── the billet: one bead travels the run on a settle event ──
    if (pulse >= 0 && pulse <= 1) {
      final fade =
          pulse < 0.85 ? 1.0 : (1 - (pulse - 0.85) / 0.15).clamp(0.0, 1.0);
      final bx = dir > 0
          ? lineX0 + pulse * (lineX1 - lineX0)
          : lineX1 - pulse * (lineX1 - lineX0);
      // The gate flashes as the bead crosses it.
      final atGate = math.exp(-(bx - gateX).abs() / 16);
      paintGlowDot(canvas, Offset(gateX, cy), 11, 0.85 * atGate * fade);
      // The node the bead left flares: violet at the key, copper at the chain.
      final left = decay(pulse * 1.2, 0.35);
      if (dir > 0) {
        paintGlowDot(canvas, Offset(lineX0, cy), 8, 0.8 * left,
            core: Instrument.soq, halo: Instrument.soq);
      } else {
        paintGlowDot(canvas, Offset(lineX1, cy), 9, 0.8 * left);
      }
      final bp = Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      bp.color = Instrument.leadEdge.withValues(alpha: 0.9 * fade);
      canvas.drawCircle(Offset(bx, cy), 2.6, bp);
      bp.color = Instrument.signal.withValues(alpha: 0.5 * fade);
      canvas.drawCircle(Offset(bx, cy), 4.6, bp);
    }

    // ── the lock-on: a new block's billet has landed. The chain node flares
    // and brackets frame the height it carried, then fade; framing only ──
    if (lockOn >= 0 && lockOn <= 1) {
      final t = lockOn *
          (MotionTiming.converge + MotionTiming.fade).inMilliseconds /
          1000;
      final blockW =
          math.max(chEyebrow.width, math.max(chValue.width, chSub.width));
      final block =
          Rect.fromLTRB(xr - blockW, cy - 27, xr, cy + 12 + chSub.height);
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      // The start offset keeps the brackets inside the hero's canvas on the
      // narrowest surface (the block ends 5.5% of the width from the edge).
      paintLockOn(canvas, block, t, from: 16, to: 4, length: 7);
      paintGlowDot(canvas, Offset(lineX1, cy), 10, 0.9 * decay(t, 0.35));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustodyLinePainter old) =>
      old.breath != breath ||
      old.pulse != pulse ||
      old.dir != dir ||
      old.live != live ||
      old.chainValue != chainValue ||
      old.chainSub != chainSub ||
      old.lockOn != lockOn;
}
