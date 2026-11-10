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

  // The figure's height when the screen has room for it.
  static const double _figureHeight = 208;

  // The gaps and the two actions under the figure, with four points to spare.
  static const double _fixedRest = 26 + 14 + 16 + 54 + 10 + 54 + 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: LayoutBuilder(
            builder: (context, box) {
              // What sits under the figure: the fixed parts, then the wordmark
              // and the two-line lead, which stand 1.45 times their size tall.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final rest = _fixedRest + (20 + 2 * 14) * 1.45 * scale;
              if (box.maxHeight >= _figureHeight + rest) {
                return Column(children: _body(_figureHeight, roomy: true));
              }
              // A short screen (a phone on its side, a large text size): the
              // figure gives way, and the column scrolls if it still does
              // not fit, so both actions can always be reached.
              final figure = (box.maxHeight - rest)
                  .clamp(64.0, _figureHeight)
                  .toDouble();
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _body(figure, roomy: false),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // The screen's parts, top to bottom. With room the spacers place them; on
  // a short screen they stack with fixed gaps under a smaller figure.
  List<Widget> _body(double figure, {required bool roomy}) => [
    if (roomy) const Spacer(flex: 2),
    SizedBox(
      height: figure,
      width: double.infinity,
      child: PointScene(field: _mark),
    ),
    const SizedBox(height: 26),
    const FittedBox(fit: BoxFit.scaleDown, child: InstrumentWordmark(size: 20)),
    const SizedBox(height: 14),
    Text(
      'A self-custodial wallet secured by\npost-quantum cryptography.',
      textAlign: TextAlign.center,
      style: Instrument.lead(size: 14),
    ),
    if (roomy) const Spacer(flex: 3) else const SizedBox(height: 16),
    InstrumentButton(
      label: 'Create a wallet',
      icon: Icons.bolt_rounded,
      primary: true,
      onTap: () => context.go('/create-account'),
    ),
    const SizedBox(height: 10),
    _ghostButton('I already have a wallet', () => context.go('/seed-restore')),
    if (roomy) const Spacer(flex: 1),
  ];

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
