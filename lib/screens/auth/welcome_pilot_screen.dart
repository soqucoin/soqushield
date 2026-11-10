// Welcome, the front door. The Soqucoin mark the splash assembled rests here
// in points, over the wordmark and two actions: create a wallet, or restore
// one from its 24 words.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/point_scene.dart';

class WelcomePilotScreen extends ConsumerStatefulWidget {
  const WelcomePilotScreen({super.key});
  @override
  ConsumerState<WelcomePilotScreen> createState() => _WelcomePilotScreenState();
}

class _WelcomePilotScreenState extends ConsumerState<WelcomePilotScreen> {
  // Fewer points than the splash: the figure is smaller here.
  final PointField _mark = PointField.mark(count: 1500);

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
              SizedBox(
                height: 208,
                width: double.infinity,
                child: PointScene(field: _mark),
              ),
              const SizedBox(height: 26),
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: InstrumentWordmark(size: 20),
              ),
              const SizedBox(height: 14),
              Text(
                'A self-custodial wallet secured by\npost-quantum cryptography.',
                textAlign: TextAlign.center,
                style: Instrument.lead(size: 14),
              ),
              const Spacer(flex: 3),
              InstrumentButton(
                label: 'Create a wallet',
                icon: Icons.bolt_rounded,
                primary: true,
                onTap: () => context.go('/create-account'),
              ),
              const SizedBox(height: 10),
              _ghostButton(
                'I already have a wallet',
                () => context.go('/seed-restore'),
              ),
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
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Instrument.readout,
            fontSize: 13,
            fontFamily: kMono,
            fontWeight: FontWeight.w600,
            letterSpacing: 13 * 0.1,
          ),
        ),
      ),
    ),
  );
}
