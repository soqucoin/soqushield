// PILOT — Receive on the "Instrument-grade. Quantum-austere." language.
//
// Wave 1. No decorative figure: the QR IS this screen's functional instrument.
// It carries the bare address and nothing else, so a scanner, the console and
// the Copy button all read the same string.
//
// Motion: on entry, corner brackets lock onto the QR panel and settle to a
// dim frame around it (framing, not verification; nothing is ever painted
// over the modules). On a copy, a ring rises under the finger on the control
// that copied and a copper wipe crosses the address: confirmation of the real
// action, never otherwise.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/instrument.dart';
import '../../theme/motion.dart';
import '../../providers/session_provider.dart';
import '../../providers/wallet_provider.dart';

class ReceivePilotScreen extends ConsumerStatefulWidget {
  const ReceivePilotScreen({super.key});
  @override
  ConsumerState<ReceivePilotScreen> createState() =>
      _ReceivePilotScreenState();
}

class _ReceivePilotScreenState extends ConsumerState<ReceivePilotScreen>
    with SingleTickerProviderStateMixin {
  /// The brackets locking onto the QR panel on entry: converge, flare, settle.
  late final AnimationController _lockOn = AnimationController(
      vsync: this, duration: MotionTiming.converge + MotionTiming.fade);
  bool _entered = false;

  // One count per control that can copy, so the ring rises under the finger
  // that copied; the wipe across the address follows either.
  int _buttonCopies = 0;
  int _rowCopies = 0;
  Offset? _buttonTouch;
  Offset? _rowTouch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotionOf(context)) {
      // On entry, or switched on mid-converge: the frame, in place.
      _lockOn.stop();
      _lockOn.value = 1;
    } else if (!_entered) {
      _lockOn.forward(from: 0);
    }
    _entered = true;
  }

  @override
  void dispose() {
    _lockOn.dispose();
    super.dispose();
  }

  void _copy(String address, {required bool fromButton}) {
    Clipboard.setData(ClipboardData(text: address));
    HapticFeedback.selectionClick();
    setState(() {
      if (fromButton) {
        _buttonCopies++;
      } else {
        _rowCopies++;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Address copied', style: TextStyle(fontSize: 12)),
      backgroundColor: Instrument.void2,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);
    final address = wallet.address;

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 36),
                    // ── the QR — the address, a clean instrument panel; the
                    // brackets lock on around it, never over it ──
                    if (address.isNotEmpty)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ReceiveQr(data: address, size: 220),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                    painter: QrLockOnPainter(_lockOn)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    const InstrumentTrustBadge(
                        icon: Icons.verified_outlined,
                        text: 'ML-DSA-44 · QUANTUM-SAFE'),
                    const SizedBox(height: 22),
                    if (address.isNotEmpty) _addressRow(address),
                    const SizedBox(height: 22),
                    Listener(
                      onPointerDown: (e) => _buttonTouch = e.localPosition,
                      child: RingPulse(
                        trigger: _buttonCopies,
                        origin: _buttonTouch,
                        child: InstrumentButton(
                          label: 'Copy address',
                          icon: Icons.copy_outlined,
                          primary: true,
                          onTap: () => _copy(address, fromButton: true),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // The system share sheet, for sending the address to a
                    // contact or another app. It is the app's own system UI:
                    // on Android it pauses the activity, and must not lock.
                    // On an iPad it is a popover anchored to this chip.
                    Builder(
                      builder: (chip) => InstrumentActionChip(
                        label: 'Share address',
                        icon: Icons.ios_share_rounded,
                        onTap: () {
                          final origin = shareOriginOf(chip);
                          ref.read(sessionProvider.notifier).whileSystemUi(
                              () => Share.share(address,
                                  sharePositionOrigin: origin));
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your ${wallet.network.displayName} address begins '
                      '${wallet.network.addressPrefix}. Anyone can send '
                      '${wallet.network.ticker} to it; only this wallet\'s '
                      'recovery phrase can spend from it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Instrument.faint,
                          fontSize: 11,
                          height: 1.5),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 22, 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Instrument.label, size: 20),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            const SizedBox(width: 2),
            Text('RECEIVE', style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  Widget _addressRow(String address) => Listener(
        onPointerDown: (e) => _rowTouch = e.localPosition,
        child: GestureDetector(
          onTap: () => _copy(address, fromButton: false),
          child: RingPulse(
            trigger: _rowCopies,
            origin: _rowTouch,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Instrument.void2,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                    color: Instrument.line.withValues(alpha: 0.6), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    // The wipe follows the ring, from either control.
                    child: TintWipe(
                      trigger: _buttonCopies + _rowCopies,
                      delay: MotionTiming.ring,
                      child: Text(address,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Instrument.label,
                              fontSize: 11,
                              fontFamily: kMono,
                              letterSpacing: 0.4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.copy_outlined,
                      size: 13, color: Instrument.faint),
                ],
              ),
            ),
          ),
        ),
      );
}

/// The receive QR: light modules on a cold panel, a hairline bezel. [data] is
/// the bare address, exactly what the Copy button copies.
class ReceiveQr extends StatelessWidget {
  final String data;
  final double size;
  const ReceiveQr({super.key, required this.data, required this.size});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Instrument.void2,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: Instrument.signal.withValues(alpha: 0.28), width: 1),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: size,
          backgroundColor: Colors.transparent,
          eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square, color: Instrument.readout),
          dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Instrument.readout),
        ),
      );
}

/// The lock-on over the QR panel: brackets converge from outside the panel,
/// flare at the corners as they land and settle to a dim frame around it.
/// Everything is drawn outside the panel, so a camera reads the code at any
/// moment. [progress] runs 0 to 1 over the converge and the settle; at 1 the
/// frame is the rest state.
class QrLockOnPainter extends CustomPainter {
  final Animation<double> progress;
  QrLockOnPainter(this.progress) : super(repaint: progress);

  static const double restAlpha = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    final total =
        (MotionTiming.converge + MotionTiming.fade).inMilliseconds / 1000;
    paintLockOn(canvas, Offset.zero & size, progress.value * total,
        from: 36, to: 8, length: 14, restAlpha: restAlpha);
  }

  @override
  bool shouldRepaint(covariant QrLockOnPainter old) =>
      old.progress != progress;
}
