// PILOT — Send on the "Instrument-grade. Quantum-austere." language.
//
// Figure: the TRANSACTION ANATOMY while you type (this send, drawn live) and
// the NTT butterfly while you sign: the wavefront sweeps OUTWARD = your
// payment being quantum-signed (ML-DSA-44), then settles on confirm. The send
// LOGIC is preserved from the full app (SB-5 auth-before-send, SB-8
// re-entrancy lock, Halborn FIND-021 session pause, A2-07 error sanitization).
// SOQ only, transparent only. Until the network has answered since boot (no
// chain tip), a send fails closed before authentication.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/instrument.dart';
import '../../theme/figures.dart';
import '../../models/wallet_keys.dart';
import '../../providers/auth_provider.dart';
import '../../providers/launch_state_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/rpc_service.dart';
import '../../services/tx_builder.dart';

class SendPilotScreen extends ConsumerStatefulWidget {
  const SendPilotScreen({super.key});
  @override
  ConsumerState<SendPilotScreen> createState() => _SendPilotScreenState();
}

class _SendPilotScreenState extends ConsumerState<SendPilotScreen>
    with TickerProviderStateMixin, InstrumentFigureMixin {
  final _amountCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _amountFocus = FocusNode();

  int _phase = 0; // 0=input, 1=signing, 2=confirmed, 3=failed
  bool _inFlight = false; // SB-8: re-entrancy guard against double-tap Send

  late AnimationController _checkCtrl;
  late Animation<double> _checkAnim;

  String _txHash = '';
  String _errorMessage = '';

  // Dynamic fee estimation from RPC
  double _estimatedFee = 0.005; // Fallback: ~4kB Dilithium TX at minrelaytxfee
  bool _feeLoading = true;

  @override
  void initState() {
    super.initState();
    initFigure();
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _checkAnim = CurvedAnimation(parent: _checkCtrl, curve: Curves.elasticOut);

    // Auto-select all text when amount field gains focus
    _amountFocus.addListener(() {
      if (_amountFocus.hasFocus && _amountCtrl.text.isNotEmpty) {
        _amountCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _amountCtrl.text.length,
        );
      }
    });

    Future.microtask(_fetchEstimatedFees);
    // A silent sweep when the screen opens so the figure reads as alive.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fireFigure(-1, haptic: false);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _recipientCtrl.dispose();
    _amountFocus.dispose();
    _checkCtrl.dispose();
    disposeFigure();
    super.dispose();
  }

  // ── send logic ───────────────────────────────────────────────────────────

  /// Fetch a fee estimate from the wallet's network for a 6-block target.
  Future<void> _fetchEstimatedFees() async {
    final rpc = RpcService(network: ref.read(walletProvider).network);
    try {
      final feePerKb = await rpc.estimateSmartFee(6);
      // FN-12: size the estimate to the REAL TX tx_builder builds (~7.6 kB,
      // 2-input Dilithium), not the old 4 kB.
      final standardFee = feePerKb * 7.6;
      if (mounted) {
        setState(() {
          _estimatedFee = standardFee > 0.0001 ? standardFee : 0.005;
          _feeLoading = false;
        });
      }
    } catch (e) {
      debugPrint('FEE: estimateSmartFee failed, using fallback: $e');
      if (mounted) setState(() => _feeLoading = false);
    } finally {
      rpc.dispose();
    }
  }

  String _formatFee(double fee, String ticker) {
    if (fee >= 1.0) return '${fee.toStringAsFixed(2)} $ticker';
    if (fee >= 0.01) return '${fee.toStringAsFixed(4)} $ticker';
    return '${fee.toStringAsFixed(6)} $ticker';
  }

  /// Maximum sendable amount — the consensus MoneyRange cap (MAX_MONEY, a
  /// per-transaction ceiling).
  static const _maxAmount = 20000000000.0;

  Future<void> _startSigning() async {
    // SB-8: reject a second tap while a send is already in flight.
    if (_inFlight) return;

    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final wallet = ref.read(walletProvider);
    final recipient = _recipientCtrl.text.trim();

    if (amount <= 0) {
      _showError('Enter an amount');
      return;
    }
    if (amount > _maxAmount) {
      _showError('Amount exceeds maximum supply');
      return;
    }

    // SB-8: claim the in-flight lock BEFORE the first await.
    setState(() => _inFlight = true);

    final addrError = TxBuilder.validateAddress(recipient, wallet.network);
    if (addrError != null) {
      setState(() => _inFlight = false);
      _showError(addrError);
      return;
    }
    if (wallet.balance <= 0 || amount > wallet.balance) {
      setState(() => _inFlight = false);
      _showError('Insufficient SOQ balance');
      return;
    }
    // No chain tip yet (the network has not answered since boot): a cached
    // balance is not a spendable one. Refuse here, before the device
    // credential and before any key is derived.
    if (wallet.blockHeight == 0) {
      setState(() => _inFlight = false);
      _showError('Waiting for the network');
      return;
    }

    // SB-5: a send moves funds — ALWAYS require the device credential first.
    // The prompt is the app's own system UI: the pause it may cause on
    // Android must not lock the wallet under it.
    final authService = ref.read(authServiceProvider);
    final authenticated = await ref
        .read(sessionProvider.notifier)
        .whileSystemUi(authService.authenticateWithBiometrics);
    if (!authenticated) {
      if (!mounted) {
        _inFlight = false;
        return;
      }
      setState(() => _inFlight = false);
      _showError('Authentication required');
      return;
    }

    // Show signing phase AFTER auth succeeds + fire the signing wavefront.
    setState(() {
      _phase = 1;
      _errorMessage = '';
    });
    HapticFeedback.mediumImpact();
    figureDir = 1; // sign = sweep OUT
    pulse.repeat();

    // CRITICAL: await so the build cycle runs between phase transitions.
    await _broadcastTransaction(recipient, amount);
  }

  Future<void> _broadcastTransaction(String recipient, double amount) async {
    // Pause session timeout during signing (Halborn FIND-021).
    final session = ref.read(sessionProvider.notifier);
    session.pauseForTransaction();

    try {
      final txid = await ref.read(walletProvider.notifier).sendTransaction(
            toAddress: recipient,
            amount: amount,
          );

      if (!mounted) return;
      _txHash = txid;
      pulse.stop();
      setState(() => _phase = 2);
      HapticFeedback.heavyImpact();
      _checkCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      debugPrint('SEND[ERROR] $e');
      // A2-07: Sanitize error — never expose raw exception text.
      final raw = e.toString();
      final String msg;
      if (raw.contains('RpcException(-22)')) {
        msg = 'Transaction rejected — invalid format or inputs already spent';
      } else if (raw.contains('RpcException(-26)')) {
        msg = 'Transaction rejected by mempool — fee too low or policy violation';
      } else if (raw.contains('RpcException(-25)')) {
        msg = 'Transaction missing inputs — UTXOs may have been spent';
      } else if (raw.contains('InsufficientFunds')) {
        msg = raw.replaceFirst(RegExp(r'.*InsufficientFunds.*?: '), '');
      } else if (raw.contains('Network error')) {
        msg = 'Network error — check your connection and try again';
      } else {
        msg = 'Transaction failed. Please try again.';
      }
      pulse.stop();
      pulse.reset();
      setState(() {
        _phase = 3; // Error phase — stays until user dismisses
        _errorMessage = msg;
      });
      HapticFeedback.heavyImpact();
    } finally {
      // ALWAYS resume timeout — even on failure (Halborn FIND-021).
      session.resumeAfterTransaction();
      // SB-8: release the re-entrancy lock once the send has fully resolved.
      _inFlight = false;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: const TextStyle(fontSize: 13)),
      backgroundColor: Instrument.void2,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── surface ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _phase == 0
              ? _input()
              : _phase == 1
                  ? _signing()
                  : _phase == 2
                      ? _confirmed()
                      : _failed(),
        ),
      ),
    );
  }

  // ── Phase 0: input ──
  Widget _input() {
    final wallet = ref.watch(walletProvider);
    final ticker = wallet.network.ticker;
    final balance = wallet.balance;

    // ── the transaction, live, for the anatomy figure ──
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final fee = _estimatedFee;
    final overspend = amount > 0 && amount + fee > balance;
    final change = (balance - amount - fee).clamp(0.0, double.infinity);

    // Before the mainnet endpoints answer, the chain reads no height and the
    // balance is 0: say so in place rather than leave a silent refusal. Once
    // this install has seen Mainnet answer, no height is an outage.
    final noHeight =
        wallet.network == SoqNetwork.mainnet && wallet.blockHeight == 0;
    final seenLive = ref.watch(mainnetSeenLiveProvider);
    final waitingForMainnet = noHeight && !seenLive;
    final reconnecting = noHeight && seenLive;

    return SingleChildScrollView(
      key: const ValueKey('input'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        children: [
          _topBar('SEND'),
          // ── hero: the TRANSACTION ANATOMY — this send, drawn live.
          // Input rail = your balance; the diamond = the ML-DSA-44 signature;
          // the three rails = recipient/change/fee in real proportion.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: figureListenable,
              builder: (_, _) => SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: TxAnatomyPainter(
                    breath: breath.value,
                    pulse: pulseValue,
                    dir: figureDir,
                    accent: Instrument.signal,
                    balanceValue: balance.toStringAsFixed(2),
                    balanceSub: '$ticker · SPENDABLE',
                    toValue:
                        amount > 0 ? amount.toStringAsFixed(2) : '—',
                    toSub: overspend ? 'EXCEEDS BALANCE' : 'RECIPIENT',
                    changeValue: amount > 0 && !overspend
                        ? change.toStringAsFixed(2)
                        : '—',
                    feeValue:
                        _feeLoading ? '…' : '~${fee.toStringAsFixed(4)}',
                    feeSub: 'FEE',
                    sigLabel: 'ML-DSA-44 · 2,420 B',
                    overspend: overspend,
                    hasAmount: amount > 0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          // ── amount readout (tap to focus) ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _amountFocus.requestFocus(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_amountCtrl.text.isEmpty ? '0' : _amountCtrl.text,
                    style: const TextStyle(
                        color: Instrument.readout,
                        fontSize: 56,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1.5,
                        height: 1.0)),
                const SizedBox(width: 9),
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(ticker,
                      style: TextStyle(
                          color: Instrument.signal.withValues(alpha: 0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.0)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // ── amount input ──
          _inputField(
            controller: _amountCtrl,
            focusNode: _amountFocus,
            hint: 'Enter amount',
            suffix: ticker,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (value) {
              if (value.length > 1 &&
                  value.startsWith('0') &&
                  !value.startsWith('0.')) {
                final cleaned = value.replaceFirst(RegExp(r'^0+'), '');
                _amountCtrl.text = cleaned.isEmpty ? '' : cleaned;
                _amountCtrl.selection =
                    TextSelection.collapsed(offset: _amountCtrl.text.length);
              }
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          // ── recipient address ──
          _inputField(
            controller: _recipientCtrl,
            hint: '${wallet.network.addressPrefix}… address',
            formatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))
            ],
          ),
          const SizedBox(height: 12),
          _feeLine(ticker),
          if (waitingForMainnet || reconnecting) ...[
            const SizedBox(height: 14),
            Text(
              waitingForMainnet
                  ? 'Sending opens at mainnet launch. Until the network '
                      'answers, this wallet shows your address and no balance.'
                  : 'Waiting for the network. Sending resumes when it answers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Instrument.faint, fontSize: 11, height: 1.5),
            ),
          ],
          const SizedBox(height: 22),
          InstrumentButton(
            label: 'Send $ticker',
            icon: Icons.north_east_rounded,
            primary: true,
            onTap: _inFlight ? () {} : _startSigning,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Both halves scale down on a narrow phone or a large system text size.
  Widget _feeLine(String ticker) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                  _feeLoading
                      ? 'ESTIMATING FEE…'
                      : 'FEE ~${_formatFee(_estimatedFee, ticker)}',
                  style: TextStyle(
                      color: Instrument.faint,
                      fontSize: 10.5,
                      fontFamily: kMono,
                      letterSpacing: 1.0)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_outlined,
                      size: 11, color: Instrument.signalDim),
                  const SizedBox(width: 5),
                  Text('QUANTUM-SAFE', style: Instrument.eyebrow(size: 10.5)),
                ],
              ),
            ),
          ),
        ],
      );

  // ── Phase 1: signing (the butterfly fires) ──
  Widget _signing() => Center(
        key: const ValueKey('signing'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: figureListenable,
                builder: (_, _) => SizedBox(
                  height: 188,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: NttButterflyPainter(
                      breath: breath.value,
                      pulse: pulseValue,
                      dir: figureDir,
                      accent: Instrument.signal,
                      accentDim: Instrument.signalDim,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text('QUANTUM-SIGNING',
                style: Instrument.eyebrow(size: 14)),
            const SizedBox(height: 10),
            const Text('ML-DSA-44',
                style: TextStyle(
                    color: Instrument.label,
                    fontSize: 11,
                    fontFamily: kMono,
                    letterSpacing: 2.0)),
            const SizedBox(height: 30),
            Text('DO NOT CLOSE THE APP',
                style: Instrument.eyebrow(
                    size: 9.5, color: Instrument.label)),
          ],
        ),
      );

  // ── Phase 2: confirmed ──
  Widget _confirmed() {
    final wallet = ref.read(walletProvider);

    return Center(
      key: const ValueKey('confirmed'),
      child: AnimatedBuilder(
        animation: _checkAnim,
        builder: (context, _) => Transform.scale(
          scale: _checkAnim.value.clamp(0.0, 1.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Instrument.signal.withValues(alpha: 0.10),
                    border: Border.all(
                        color: Instrument.signal.withValues(alpha: 0.5),
                        width: 1),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Instrument.signal, size: 30),
                ),
                const SizedBox(height: 20),
                Text('SENT',
                    style: Instrument.eyebrow(size: 14)),
                const SizedBox(height: 12),
                Text('${_amountCtrl.text} ${wallet.network.ticker}',
                    style: const TextStyle(
                        color: Instrument.readout,
                        fontSize: 30,
                        fontWeight: FontWeight.w300)),
                const SizedBox(height: 8),
                Text('ON-CHAIN · L1',
                    style: Instrument.eyebrow(size: 10.5)),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _txHash));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Hash copied',
                          style: TextStyle(fontSize: 12)),
                      backgroundColor: Instrument.void2,
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                  child: Text(
                      '${_txHash.substring(0, _txHash.length.clamp(0, 16))}…',
                      style: TextStyle(
                          color: Instrument.faint,
                          fontSize: 11.5,
                          fontFamily: kMono,
                          letterSpacing: 0.4)),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: 180,
                  child: InstrumentButton(
                    label: 'Done',
                    icon: Icons.check_rounded,
                    primary: false,
                    onTap: () => context.go('/'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Phase 3: failed ──
  Widget _failed() => Center(
        key: const ValueKey('failed'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD96A6A).withValues(alpha: 0.1),
                  border: Border.all(
                      color: const Color(0xFFD96A6A).withValues(alpha: 0.4),
                      width: 1),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Color(0xFFD96A6A), size: 30),
              ),
              const SizedBox(height: 20),
              Text('TRANSACTION FAILED',
                  style: Instrument.eyebrow(size: 13)),
              const SizedBox(height: 14),
              Text(_errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Instrument.label, fontSize: 13, height: 1.4)),
              const SizedBox(height: 28),
              InstrumentButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                primary: true,
                onTap: () => setState(() {
                  _phase = 0;
                  _errorMessage = '';
                }),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('BACK TO WALLET',
                    style: TextStyle(
                        color: Instrument.faint,
                        fontSize: 11,
                        fontFamily: kMono,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 11 * 0.1)),
              ),
            ],
          ),
        ),
      );

  // ── shared bits ──
  Widget _topBar(String title) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Instrument.label, size: 20),
              onPressed: () => context.go('/'),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: Instrument.eyebrow(size: 11)),
          ],
        ),
      );

  Widget _inputField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    String? suffix,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Instrument.void2,
        borderRadius: BorderRadius.zero,
        border:
            Border.all(color: Instrument.line.withValues(alpha: 0.45), width: 1),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboard,
        inputFormatters: formatters,
        onChanged: onChanged ?? (_) => setState(() {}),
        cursorColor: Instrument.signal,
        style: const TextStyle(
            color: Instrument.readout, fontSize: 14, fontFamily: kMono),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: Instrument.faint, fontSize: 13),
          suffixText: suffix,
          suffixStyle: TextStyle(
              color: Instrument.label, fontSize: 11, fontFamily: kMono),
        ),
      ),
    );
  }
}
