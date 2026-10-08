// Risk disclosure on the instrument language.
//
// Four plain rows between hairlines and one lit primary action. The copy and
// the route are the 2.1.0 screen's, unchanged.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';

/// Risk disclosure screen — shown after wallet creation, before entering the app.
///
/// Required for App Store compliance (Apple Section 3.1.5).
/// Informs users about crypto asset risks, self-custody responsibilities,
/// and the irreversibility of blockchain transactions.
class RiskDisclosureScreen extends StatelessWidget {
  const RiskDisclosureScreen({super.key});

  static const _disclosures = [
    _Disclosure(
      icon: Icons.trending_down_rounded,
      title: 'Price Volatility',
      body: 'Digital assets are highly volatile and may lose '
          'significant value. Only use funds you can afford to lose.',
    ),
    _Disclosure(
      icon: Icons.lock_outline_rounded,
      title: 'Self-Custody',
      body: 'SoquShield does not hold your funds. You are solely '
          'responsible for your recovery phrase. If lost, your '
          'assets cannot be recovered by anyone.',
    ),
    _Disclosure(
      icon: Icons.swap_horiz_rounded,
      title: 'Irreversible Transactions',
      body: 'Blockchain transactions cannot be reversed or cancelled '
          'once confirmed. Always verify addresses before sending.',
    ),
    _Disclosure(
      icon: Icons.shield_outlined,
      title: 'Post-Quantum Security',
      body: 'SoquShield uses ML-DSA-44 (FIPS 204) signatures, '
          'quantum-resistant cryptography designed for long-term '
          'security against future quantum threats.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InstrumentTopBar(label: 'BEFORE YOU START'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('Important Information',
                      style: TextStyle(
                          color: Instrument.readout,
                          fontSize: 19,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 6),
                  Text('Please review before continuing',
                      style: TextStyle(color: Instrument.faint, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                physics: const BouncingScrollPhysics(),
                children: [
                  const InstrumentDivider(),
                  for (final d in _disclosures) ...[
                    _row(d),
                    const InstrumentDivider(),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: InstrumentButton(
                label: 'I Understand — Continue',
                icon: Icons.check_rounded,
                primary: true,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  context.go('/');
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'This is not financial advice. Do your own research.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Instrument.faint, fontSize: 10, height: 1.4),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _row(_Disclosure d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(d.icon, size: 18, color: Instrument.label),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.title,
                      style: const TextStyle(
                          color: Instrument.readout,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 5),
                  Text(d.body,
                      style: const TextStyle(
                          color: Instrument.label,
                          fontSize: 12,
                          height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Disclosure {
  final IconData icon;
  final String title;
  final String body;

  const _Disclosure({
    required this.icon,
    required this.title,
    required this.body,
  });
}
