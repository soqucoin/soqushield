// PILOT — Welcome (the front door) on the instrument language.
//
// Wave 3. Figure: the CRYSTALLIZING LATTICE, settled — the network at rest,
// breathing, inviting you to bring your keys online. Two actions: create a
// wallet, or restore one from its 24 words.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/figures.dart';

class WelcomePilotScreen extends ConsumerStatefulWidget {
  const WelcomePilotScreen({super.key});
  @override
  ConsumerState<WelcomePilotScreen> createState() =>
      _WelcomePilotScreenState();
}

class _WelcomePilotScreenState extends ConsumerState<WelcomePilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  @override
  void initState() {
    super.initState();
    initFigure();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The lattice comes online, once; settled at once under reduced motion.
      if (mounted) fireFigure(1, haptic: false);
    });
  }

  @override
  void dispose() {
    disposeFigure();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: figureListenable,
                  builder: (_, _) => SizedBox(
                    height: 188,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: CrystallizingLatticePainter(
                        breath: breath.value,
                        pulse: pulseValue,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('SOQUSHIELD',
                  style: TextStyle(
                      color: Instrument.readout,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 6)),
              const SizedBox(height: 12),
              Text('A self-custodial wallet secured by\npost-quantum cryptography.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Instrument.faint, fontSize: 13, height: 1.5)),
              const Spacer(flex: 3),
              InstrumentButton(
                label: 'Create a wallet',
                icon: Icons.bolt_rounded,
                primary: true,
                onTap: () => context.go('/create-account'),
              ),
              const SizedBox(height: 10),
              _ghostButton('I already have a wallet',
                  () => context.go('/seed-restore')),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  // Foundry .btn secondary: transparent, seam-hi border, mono caps.
  Widget _ghostButton(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Instrument.lineHi, width: 1),
          ),
          child: Center(
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: Instrument.readout,
                    fontSize: 13,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 13 * 0.1)),
          ),
        ),
      );
}
