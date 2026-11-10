// Create Account ("Activation"). The figure is the module lattice, the
// structure ML-DSA rests on, in points and edges. On Activate it bursts apart
// and locks back into order: the keys coming online. Logic preserved verbatim
// from CreateAccountScreen (createAccount → biometric pref → createWallet
// (ML-DSA-44) → onAccountCreated → /seed-backup; name validation).
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/point_scene.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';

class CreateAccountPilotScreen extends ConsumerStatefulWidget {
  const CreateAccountPilotScreen({super.key});
  @override
  ConsumerState<CreateAccountPilotScreen> createState() =>
      _CreateAccountPilotScreenState();
}

class _CreateAccountPilotScreenState
    extends ConsumerState<CreateAccountPilotScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  bool _enableBiometric = true;
  bool _creating = false;

  final PointField _lattice = PointField.lattice();
  // The burst on Activate: the points fly apart and come back into order.
  late final AnimationController _burst = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  late final Animation<double> _scatter = _burst.drive(_Burst());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    _burst.dispose();
    super.dispose();
  }

  // ── preserved verbatim from CreateAccountScreen._createAccount ──
  Future<void> _createAccount() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (!kIsWeb) HapticFeedback.heavyImpact();
      return;
    }

    // bead agx: the app locks on every launch via the device screen lock.
    // Creating a wallet on a device WITHOUT one produces an unopenable
    // wallet after restart — require enrollment before creation.
    if (!await ref.read(authServiceProvider).isDeviceAuthAvailable()) {
      if (!mounted) return;
      if (!kIsWeb) HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Set a screen lock (PIN, pattern or passcode) in your device '
            'settings first — SoquShield uses it to protect your wallet.',
            style: TextStyle(fontSize: 13)),
        backgroundColor: Instrument.void2,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 6),
      ));
      return;
    }

    setState(() => _creating = true);
    if (!kIsWeb) HapticFeedback.mediumImpact();
    // The lattice bursts and reorders — keys coming online (the haptic above
    // is the confirmation; the figure holds still under reduced motion).
    _burst.forward(from: 0);

    try {
      final service = ref.read(authServiceProvider);
      await service.createAccount(name);

      if (!_enableBiometric) {
        await service.setBiometricEnabled(false);
      }

      // Generate PQ wallet with ML-DSA-44 keys
      await ref.read(walletProvider.notifier).createWallet(name);

      // Update auth state — ONLY after wallet is successfully created
      await ref.read(authProvider.notifier).onAccountCreated();

      // Navigate to seed backup (user MUST see their recovery phrase)
      if (mounted) context.go('/seed-backup');
    } catch (e) {
      debugPrint('Account creation error: $e');
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Wallet creation failed. Please try again.',
              style: TextStyle(fontSize: 13)),
          backgroundColor: Instrument.void2,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 8),
              // The figure gives way to the keyboard, so the name field and
              // Activate stay in view while the name is typed.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: typing ? 108 : 176,
                width: double.infinity,
                child: PointScene(field: _lattice, scatter: _scatter),
              ),
              const SizedBox(height: 6),
              Text('KEY GENESIS · MODULE LATTICE',
                  style: Instrument.eyebrow(size: 9, color: Instrument.faint)),
              const SizedBox(height: 18),
              Text('Name your wallet',
                  textAlign: TextAlign.center,
                  style: Instrument.heading(size: 22)),
              const SizedBox(height: 6),
              Text('Your post-quantum keys are generated on this device.',
                  textAlign: TextAlign.center, style: Instrument.lead(size: 13)),
              const SizedBox(height: 18),
              _nameField(),
              const SizedBox(height: 14),
              _biometricToggle(),
              const SizedBox(height: 26),
              SizedBox(
                height: 54,
                child: _creating
                    ? _activatingButton()
                    : InstrumentButton(
                        label: 'Activate',
                        icon: Icons.bolt_rounded,
                        primary: true,
                        onTap: _createAccount,
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Instrument.label, size: 20),
              onPressed: _creating ? null : () => context.go('/welcome'),
            ),
            const SizedBox(width: 12),
            Text('NEW WALLET', style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  Widget _nameField() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Instrument.void2,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: Instrument.line.withValues(alpha: 0.45), width: 1),
        ),
        child: TextField(
          controller: _nameController,
          focusNode: _focusNode,
          enabled: !_creating,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createAccount(),
          inputFormatters: [
            // A2-08: restrict to safe characters
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 _\-]')),
          ],
          cursorColor: Instrument.signal,
          style: const TextStyle(color: Instrument.readout, fontSize: 15),
          decoration: InputDecoration(
            counterText: '',
            border: InputBorder.none,
            hintText: 'e.g. Personal',
            hintStyle: TextStyle(color: Instrument.faint, fontSize: 14),
          ),
        ),
      );

  Widget _biometricToggle() => FutureBuilder<bool>(
        future: ref.read(authServiceProvider).isBiometricAvailable(),
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () => setState(() => _enableBiometric = !_enableBiometric),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.zero,
                border: Border.all(
                    color: Instrument.line.withValues(alpha: 0.45), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.fingerprint_rounded,
                      size: 17, color: Instrument.label),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Unlock with Face ID / Touch ID',
                        style: TextStyle(
                            color: Instrument.label, fontSize: 13)),
                  ),
                  _switch(_enableBiometric),
                ],
              ),
            ),
          );
        },
      );

  Widget _switch(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: on ? Instrument.signal.withValues(alpha: 0.4) : Instrument.line,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? Instrument.signal : Instrument.label),
          ),
        ),
      );

  Widget _activatingButton() => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          color: Instrument.signal.withValues(alpha: 0.10),
          border: Border.all(
              color: Instrument.signal.withValues(alpha: 0.5), width: 1),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Instrument.signal),
              ),
              const SizedBox(width: 12),
              Text('GENERATING KEYS', style: Instrument.eyebrow(size: 12)),
            ],
          ),
        ),
      );
}

/// The burst's scatter over its run, in scene units: out, then back to rest.
class _Burst extends Animatable<double> {
  @override
  double transform(double t) => 2.4 * math.sin(math.pi * t);
}
