// Recovery phrase (backup) on the instrument language.
//
// The first screen a new holder meets after key generation, and the one
// Settings reopens. The grid is the instrument: all 24 words on one screen,
// numbered, nothing decorative. The logic (the reveal gate, the copy with the
// clipboard clear, the confirmation, the continue) is the 2.1.0 screen's,
// unchanged.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/instrument.dart';
import '../../widgets/seed_word_grid.dart';

/// Seed phrase backup screen — displays the 24-word mnemonic
/// and requires the user to confirm they've written it down.
///
/// SECURITY: This screen should only be shown ONCE after wallet creation.
/// The seed phrase is the ONLY way to recover the wallet.
class SeedBackupScreen extends ConsumerStatefulWidget {
  const SeedBackupScreen({super.key});

  @override
  ConsumerState<SeedBackupScreen> createState() => _SeedBackupScreenState();
}

class _SeedBackupScreenState extends ConsumerState<SeedBackupScreen> {
  bool _revealed = false;
  bool _confirmed = false;
  bool _saving = false;
  List<String> _loadedWords = [];

  @override
  void initState() {
    super.initState();
    _loadSeedPhrase();
  }

  /// Load seed phrase from state or re-read from secure storage.
  Future<void> _loadSeedPhrase() async {
    final walletState = ref.read(walletProvider);
    if (walletState.seedPhrase != null) {
      setState(() => _loadedWords = walletState.seedPhrase!.words);
      return;
    }

    // Seed was cleared from memory after backup — reload from storage
    try {
      final storage = SecureStorageService();
      final mnemonic = await storage.readMnemonic();
      if (mnemonic != null && mnemonic.isNotEmpty) {
        setState(() => _loadedWords = mnemonic.split(' '));
      }
    } catch (e) {
      debugPrint('Failed to reload seed: $e');
    }
  }

  void _back() {
    // During onboarding (backup not yet confirmed), back = abort to welcome.
    // If already confirmed (viewing from settings), back = return to app.
    final wallet = ref.read(walletProvider);
    context.go(wallet.backupConfirmed ? '/' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final words = _loadedWords;

    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InstrumentTopBar(label: 'RECOVERY PHRASE', onBack: _back),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                // A short surface at a large system text size cannot hold
                // the header, a readable grid and the actions at once: the
                // page scrolls and the grid takes its least height. Otherwise
                // the grid takes the room between the header and the actions
                // and scrolls itself only below a 38-point cell. The bound is
                // the height under which the header and the actions, at that
                // text size, leave the grid less than a few rows.
                final pageScrolls = constraints.maxHeight <
                    480 * MediaQuery.textScalerOf(context).scale(1);
                final middle = _revealed
                    ? SeedWordGrid(
                        count: words.length,
                        cellBuilder: (_, i) => SeedWordCell(
                          number: i + 1,
                          child: SeedWord(words[i]),
                        ),
                      )
                    : _revealPanel();
                final body = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize:
                        pageScrolls ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      const SizedBox(height: 12),
                      const Text('Write down these 24 words in order.',
                          style: TextStyle(
                              color: Instrument.readout,
                              fontSize: 19,
                              fontWeight: FontWeight.w400)),
                      const SizedBox(height: 6),
                      Text('This is the ONLY way to recover your wallet.',
                          style: TextStyle(
                              color: Instrument.faint,
                              fontSize: 12,
                              height: 1.4)),
                      const SizedBox(height: 14),
                      _warning(),
                      const SizedBox(height: 14),
                      if (pageScrolls)
                        SizedBox(
                          height: _revealed
                              ? SeedWordGrid.minHeightFor(words.length)
                              : 200,
                          child: middle,
                        )
                      else
                        Expanded(child: middle),
                      if (_revealed) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: InstrumentActionChip(
                            label: 'Copy all',
                            icon: Icons.copy_outlined,
                            onTap: () => _copyAll(words),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _confirmRow(),
                        const SizedBox(height: 12),
                        if (_saving)
                          const InstrumentBusyButton(label: 'SAVING')
                        else
                          InstrumentButton(
                            label: 'Continue',
                            icon: Icons.east_rounded,
                            primary: true,
                            enabled: _confirmed,
                            onTap: _onContinue,
                          ),
                      ],
                      const SizedBox(height: 18),
                    ],
                  ),
                );
                return pageScrolls
                    ? SingleChildScrollView(
                        physics: const BouncingScrollPhysics(), child: body)
                    : body;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _warning() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: Instrument.threat.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.warning_amber_rounded,
                  size: 15, color: Instrument.threat),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Never share your recovery phrase. Anyone with these words '
                'can steal your funds.',
                style: TextStyle(
                    color: Instrument.label, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      );

  /// SB-5: gate the reveal behind a fresh device-credential check.
  ///
  /// The one-time onboarding display happens inside a just-created, already
  /// authenticated session, so it reveals directly. But re-viewing the phrase
  /// from Settings (wallet already backed up) is a seed-export action and must
  /// demand biometric/passcode re-auth *every time* — otherwise anyone holding
  /// an unlocked phone can lift the recovery phrase.
  Future<void> _onRevealTapped() async {
    final wallet = ref.read(walletProvider);
    if (wallet.backupConfirmed && !kIsWeb) {
      final service = ref.read(authServiceProvider);
      final ok = await ref
          .read(sessionProvider.notifier)
          .whileSystemUi(service.authenticateWithBiometrics);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Authentication required to view your recovery phrase'),
              backgroundColor: Instrument.void2,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    if (!kIsWeb) HapticFeedback.mediumImpact();
    if (mounted) setState(() => _revealed = true);
  }

  Widget _revealPanel() => Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onRevealTapped,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              border: Border.all(color: Instrument.lineHi, width: 1),
            ),
            // The panel scales down rather than overflowing when the room
            // between the header and the bottom is short.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 26, color: Instrument.label),
                  const SizedBox(height: 12),
                  const Text('Tap to reveal recovery phrase',
                      style: TextStyle(
                          color: Instrument.readout,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Make sure no one is watching',
                      style: TextStyle(color: Instrument.faint, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      );

  void _copyAll(List<String> words) {
    Clipboard.setData(ClipboardData(text: words.join(' ')));
    if (!kIsWeb) HapticFeedback.lightImpact();

    // SECURITY: Auto-clear clipboard after 60 seconds
    // to prevent other apps from reading the mnemonic.
    Future.delayed(const Duration(seconds: 60), () {
      Clipboard.setData(const ClipboardData(text: ''));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            '⚠ Recovery phrase copied — clipboard auto-clears in 60s',
            style: TextStyle(fontSize: 12)),
        backgroundColor: Instrument.void2,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ),
    );
  }

  Widget _confirmRow() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _confirmed = !_confirmed),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.zero,
                color: _confirmed
                    ? Instrument.signal.withValues(alpha: 0.18)
                    : Colors.transparent,
                border: Border.all(
                    color: _confirmed ? Instrument.signal : Instrument.lineHi,
                    width: 1.5),
              ),
              child: _confirmed
                  ? const Icon(Icons.check_rounded,
                      size: 15, color: Instrument.signal)
                  : null,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'I have written down my recovery phrase and stored it securely',
                style: TextStyle(
                    color: Instrument.label, fontSize: 12, height: 1.3),
              ),
            ),
          ],
        ),
      );

  Future<void> _onContinue() async {
    setState(() => _saving = true);
    if (!kIsWeb) HapticFeedback.mediumImpact();

    try {
      await ref.read(walletProvider.notifier).confirmBackup();

      if (mounted) context.go('/risk-disclosure');
    } catch (e) {
      debugPrint('Backup confirm error: $e');
      if (mounted) context.go('/risk-disclosure');
    }
  }
}
