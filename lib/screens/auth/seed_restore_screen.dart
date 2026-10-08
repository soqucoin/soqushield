// Restore from the 24 words on the instrument language.
//
// Twenty-four numbered fields on one screen, a paste action, one lit primary
// button once every field holds a word. The validation, the screen-lock
// requirement and the restore path are the 2.1.0 screen's, unchanged.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/key_service.dart';
import '../../theme/instrument.dart';
import '../../widgets/seed_word_grid.dart';

/// Seed phrase restore screen — allows the user to enter their
/// 24-word mnemonic to restore a wallet on a new device.
class SeedRestoreScreen extends ConsumerStatefulWidget {
  const SeedRestoreScreen({super.key});

  @override
  ConsumerState<SeedRestoreScreen> createState() => _SeedRestoreScreenState();
}

class _SeedRestoreScreenState extends ConsumerState<SeedRestoreScreen> {
  final List<TextEditingController> _controllers =
      List.generate(24, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(24, (_) => FocusNode());
  final _keyService = KeyService();
  bool _restoring = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The focused cell lights its hairline: repaint on every focus move.
    for (final f in _focusNodes) {
      f.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.removeListener(_onFocusChange);
      f.dispose();
    }
    super.dispose();
  }

  bool get _allFilled =>
      _controllers.every((c) => c.text.trim().isNotEmpty);

  String get _mnemonic =>
      _controllers.map((c) => c.text.trim().toLowerCase()).join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InstrumentTopBar(
                label: 'RESTORE', onBack: () => context.go('/welcome')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('Restore Wallet',
                      style: TextStyle(
                          color: Instrument.readout,
                          fontSize: 19,
                          fontWeight: FontWeight.w400)),
                  const SizedBox(height: 6),
                  Text(
                      'Enter your 24-word recovery phrase to restore your '
                      'wallet on this device.',
                      style: TextStyle(
                          color: Instrument.faint, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 12),
                  InstrumentActionChip(
                    label: 'Paste from clipboard',
                    icon: Icons.content_paste_rounded,
                    onTap: _pasteAll,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: SeedWordGrid(count: 24, cellBuilder: (_, i) => _cell(i)),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.error_outline,
                          size: 14, color: Instrument.threat),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Instrument.threat,
                              fontSize: 11.5,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: _restoring
                  ? const InstrumentBusyButton(label: 'RESTORING')
                  : InstrumentButton(
                      label: 'Restore wallet',
                      icon: Icons.vpn_key_outlined,
                      primary: true,
                      enabled: _allFilled,
                      onTap: _restore,
                    ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }

  Widget _cell(int index) => SeedWordCell(
        number: index + 1,
        active: _focusNodes[index].hasFocus,
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) {
            if (index < 23) {
              _focusNodes[index + 1].requestFocus();
            }
          },
          style: SeedWordCell.wordStyle,
          cursorColor: Instrument.signal,
          decoration: const InputDecoration(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 10),
            isDense: true,
          ),
          textInputAction:
              index < 23 ? TextInputAction.next : TextInputAction.done,
          // The words are a secret: no correction, no suggestions, and no
          // keyboard may learn them for its personal dictionary.
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
        ),
      );

  Future<void> _pasteAll() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text == null) return;

      final words = data!.text!.trim().split(RegExp(r'\s+'));
      if (words.length != 24) {
        setState(() => _error = 'Clipboard must contain exactly 24 words');
        return;
      }

      for (var i = 0; i < 24; i++) {
        _controllers[i].text = words[i].toLowerCase();
      }
      setState(() => _error = null);
      if (!kIsWeb) HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() => _error = 'Unable to read clipboard');
    }
  }

  Future<void> _restore() async {
    final mnemonic = _mnemonic;

    // Validate mnemonic
    if (!_keyService.validateMnemonic(mnemonic)) {
      setState(() => _error = 'Invalid recovery phrase. Check your words and try again.');
      if (!kIsWeb) HapticFeedback.heavyImpact();
      return;
    }

    // bead agx: the app locks on every launch via the device screen lock.
    // Importing on a device WITHOUT one produces an unopenable wallet after
    // restart — require enrollment before restore.
    if (!await ref.read(authServiceProvider).isDeviceAuthAvailable()) {
      setState(() => _error = 'Set a screen lock (PIN, pattern or passcode) '
          'in your device settings first — SoquShield uses it to protect '
          'your wallet.');
      if (!kIsWeb) HapticFeedback.heavyImpact();
      return;
    }

    setState(() {
      _restoring = true;
      _error = null;
    });
    if (!kIsWeb) HapticFeedback.mediumImpact();

    try {
      await ref.read(walletProvider.notifier).restoreFromMnemonic(mnemonic);

      // SB-F1: a restored wallet must ALSO register the account name that the
      // auth gate (hasAccount → soq_account_name) checks on cold start.
      // restoreFromMnemonic writes the mnemonic but not that name, so without
      // this the restored wallet is invisible on the next launch and the user
      // is bounced back to onboarding believing their funds are lost. Mirror the
      // create-account path: write the name + flip auth to authenticated.
      final authService = ref.read(authServiceProvider);
      if (!await authService.hasAccount()) {
        await authService.createAccount('My Wallet');
      }
      await ref.read(authProvider.notifier).onAccountCreated();

      if (mounted) context.go('/risk-disclosure');
    } catch (e) {
      debugPrint('Restore error: $e');
      setState(() {
        _error = 'Restoration failed: ${e.toString()}';
        _restoring = false;
      });
    }
  }
}
