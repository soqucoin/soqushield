import 'package:convert/convert.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wallet_keys.dart';
import '../models/utxo.dart';
import '../services/balance_service.dart';
import '../services/key_service.dart';
import '../services/rpc_service.dart';
import '../services/secure_storage_service.dart';
import '../services/utxo_service.dart';
import '../services/tx_builder.dart';
import '../services/tx_parser.dart';
import '../services/tx_history_service.dart';

// ═══════════════════════════════════════════
//  Wallet Transaction Model (for Activity UI)
// ═══════════════════════════════════════════

/// `faucet` stays at index 2: stored history rows carry the enum index
/// (TxHistoryService), and stagenet installs upgrading from the full app
/// still hold faucet rows.
enum TxType { sent, received, faucet }

/// Lightweight transaction record for display in the Activity feed.
class WalletTransaction {
  final String txid;
  final TxType type;
  final double amount;
  final DateTime timestamp;
  final int confirmations;

  const WalletTransaction({
    required this.txid,
    required this.type,
    required this.amount,
    required this.timestamp,
    this.confirmations = 0,
  });
}

/// Full wallet state — real keys, real balance, real address.
class WalletState {
  /// SOQ confirmed balance from UTXO set
  final double balance;

  /// Unconfirmed balance delta (negative = outgoing pending, positive = incoming)
  final double pendingBalance;

  /// Active wallet keys (address, public key, etc.)
  final WalletKeys? keys;

  /// Seed phrase (only present immediately after creation, before backup)
  final SeedPhrase? seedPhrase;

  /// Current network. Mainnet for a new install; an existing install keeps
  /// the network it stored (SecureStorageService.readNetwork).
  final SoqNetwork network;

  /// Whether seed phrase backup has been confirmed
  final bool backupConfirmed;

  /// Whether wallet is initialized (has keys)
  final bool isInitialized;

  /// Loading state
  final bool isLoading;

  /// Error message
  final String? error;

  /// Block height from node
  final int blockHeight;

  /// Transaction history for Activity feed
  final List<WalletTransaction> recentTransactions;

  const WalletState({
    this.balance = 0,
    this.pendingBalance = 0,
    this.keys,
    this.seedPhrase,
    this.network = SoqNetwork.mainnet,
    this.backupConfirmed = false,
    this.isInitialized = false,
    this.isLoading = false,
    this.error,
    this.blockHeight = 0,
    this.recentTransactions = const [],
  });

  /// Optimistic balance: confirmed + pending (what the user "really" has).
  /// Use this for display; use [balance] for transaction validation.
  double get displayBalance => balance + pendingBalance;

  /// Whether there is a pending (unconfirmed) transaction.
  bool get hasPendingTx => pendingBalance.abs() > 0.001;

  WalletState copyWith({
    double? balance,
    double? pendingBalance,
    WalletKeys? keys,
    SeedPhrase? seedPhrase,
    SoqNetwork? network,
    bool? backupConfirmed,
    bool? isInitialized,
    bool? isLoading,
    String? error,
    int? blockHeight,
    bool clearSeedPhrase = false,
    bool clearError = false,
    List<WalletTransaction>? recentTransactions,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      keys: keys ?? this.keys,
      seedPhrase: clearSeedPhrase ? null : (seedPhrase ?? this.seedPhrase),
      network: network ?? this.network,
      backupConfirmed: backupConfirmed ?? this.backupConfirmed,
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      blockHeight: blockHeight ?? this.blockHeight,
      recentTransactions: recentTransactions ?? this.recentTransactions,
    );
  }

  /// Convenience: wallet address for display
  String get address => keys?.address ?? '';

  /// Convenience: has a wallet been created
  bool get hasWallet => keys != null;
}

/// Wallet state notifier — manages the full wallet lifecycle.
class WalletNotifier extends Notifier<WalletState> {
  late final KeyService _keyService;
  late final SecureStorageService _storageService;
  late final RpcService _rpcService;
  late final BalanceService _balanceService;

  /// Parsed-raw-tx cache for history reconstruction — public chain data,
  /// bounded by the 100-entry history cap.
  final Map<String, ParsedTx> _parsedTxCache = {};
  late final UtxoService _utxoService;
  late final TxBuilder _txBuilder;

  // Auto-refresh timer — polls balance every 30s like a real wallet
  Timer? _refreshTimer;
  static const _refreshInterval = Duration(seconds: 30);

  /// Bumped by a network switch. A refresh captures it when it starts and
  /// writes nothing once it has moved on, so a reply from the old network
  /// never lands in the new network's state.
  int _refreshGeneration = 0;

  // SECURITY: Session-scoped keypair cache. Derived once from mnemonic on
  // first sign operation, then reused for the session. This avoids reading
  // the mnemonic from SecureStorage into a new immutable Dart String on
  // every transaction. The secretKey is zeroed on wipe/lock.
  Uint8List? _cachedPk;
  Uint8List? _cachedSk;

  @override
  WalletState build() {
    _keyService = KeyService();
    _storageService = SecureStorageService();
    _rpcService = RpcService();
    _balanceService = BalanceService();
    _utxoService = UtxoService(_rpcService);
    _txBuilder = TxBuilder(_rpcService, _utxoService);

    // Check for existing wallet on startup
    Future.microtask(() => _loadExistingWallet());

    return const WalletState(isLoading: true);
  }

  /// Point the RPC client, the ElectrumX client and the history partition at
  /// [network], and drop the per-chain parse cache. Called at boot, on create,
  /// on restore and on a switch, so no service runs on its constructor default
  /// while the wallet is on another network. The UTXO partition is handled at
  /// each call site (synchronous at boot/create/restore, reloaded on a switch).
  void _applyNetwork(SoqNetwork network) {
    _parsedTxCache.clear(); // txids are per-chain
    _rpcService.setNetwork(network);
    _balanceService.setNetwork(network);
    TxHistoryService.setNetwork(network);
  }

  /// Load existing wallet from secure storage.
  Future<void> _loadExistingWallet() async {
    try {
      debugPrint('BOOT[1/5] Checking secure storage for existing wallet...');
      final hasWallet = await _storageService.hasWallet();
      if (!hasWallet) {
        debugPrint('BOOT[1/5] No wallet found — showing onboarding');
        state = const WalletState(isLoading: false);
        return;
      }

      // Read stored mnemonic and re-derive keys
      final mnemonic = await _storageService.readMnemonic();
      if (mnemonic == null) {
        state = const WalletState(isLoading: false);
        return;
      }

      final network = await _storageService.readNetwork();
      final accountIndex = await _storageService.readAccountIndex();
      final backupConfirmed = await _storageService.isBackupConfirmed();

      final seed = SeedPhrase(
        words: mnemonic.split(' '),
        backupConfirmed: backupConfirmed,
      );

      final keys = await _keyService.deriveFromMnemonic(
        seed,
        network: network,
        accountIndex: accountIndex,
      );

      // ── FIPS 204 Migration Detection ──
      // If the stored address differs from the freshly derived address,
      // the key derivation algorithm changed (Round 3 → FIPS 204).
      // All cached UTXOs belong to the OLD address and are unspendable.
      // Clear the stale cache to prevent phantom balance display.
      final storedAddress = await _storageService.readAddress();
      if (storedAddress != null && storedAddress != keys.address) {
        debugPrint('MIGRATION: Key algorithm changed');
        debugPrint('  Old address: $storedAddress');
        debugPrint('  New address: ${keys.address}');
        await _utxoService.clear();
        // Update stored address to new FIPS 204 address
        await _storageService.storeWallet(
          mnemonic: mnemonic,
          keys: keys,
          network: network,
        );
        debugPrint('MIGRATION: Stale UTXO cache cleared, address updated');
      }

      // Every service follows the STORED network before anything is loaded
      // or fetched, so a mainnet wallet never reads the stagenet partition
      // or queries the stagenet indexer at boot.
      _applyNetwork(network);
      _utxoService.setNetworkSync(network);

      // Load UTXO set (empty after migration, populated on first refresh)
      await _utxoService.load();

      debugPrint('BOOT[3/5] Wallet loaded — address: ${keys.address}');
      debugPrint('BOOT[3/5] Cached UTXO balance: ${_utxoService.soqBalance} SOQ');

      // SOQ only: a set cached by the 2.1 build can still hold USDSOQ
      // outputs, and this wallet's balance is SOQ.
      state = WalletState(
        keys: keys,
        network: network,
        backupConfirmed: backupConfirmed,
        isInitialized: true,
        isLoading: false,
        balance: _utxoService.soqBalance,
        recentTransactions: await TxHistoryService.load(), // F14
      );

      // Verify UTXOs and refresh the balance in background
      debugPrint('BOOT[4/5] Starting ElectrumX balance refresh...');
      _refreshBalance();

      // Start auto-refresh polling — catches pool payouts, external deposits
      _startAutoRefresh();
    } catch (e) {
      debugPrint('Load wallet error: $e');
      state = WalletState(
        isLoading: false,
        error: 'Failed to load wallet: $e',
      );
    }
  }

  /// Create a new wallet with a fresh mnemonic on the current network.
  Future<void> createWallet(String accountName) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Generate mnemonic
      final seed = _keyService.generateMnemonic();

      // Derive Dilithium keys
      final keys = await _keyService.deriveFromMnemonic(
        seed,
        network: state.network,
      );

      // Store securely
      await _storageService.storeWallet(
        mnemonic: seed.mnemonic,
        keys: keys,
        network: state.network,
      );

      _applyNetwork(state.network);
      _utxoService.setNetworkSync(state.network);

      state = WalletState(
        keys: keys,
        seedPhrase: seed, // Keep seed phrase for backup screen
        network: state.network,
        backupConfirmed: false,
        isInitialized: true,
        isLoading: false,
      );

      // Fetch the balance and start polling, as restore does
      _refreshBalance();
      _startAutoRefresh();

      // F12: Don't log full addresses (visible in debug/profile builds)
      debugPrint('Wallet created successfully');
    } catch (e) {
      debugPrint('Create wallet error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create wallet: $e',
      );
    }
  }

  /// Restore wallet from existing mnemonic on the current network.
  Future<void> restoreFromMnemonic(String mnemonic) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final seed = SeedPhrase(
        words: mnemonic.split(' '),
        backupConfirmed: true, // User already has the phrase
      );

      // Validate
      if (!_keyService.validateMnemonic(mnemonic)) {
        throw Exception('Invalid mnemonic');
      }

      // Derive keys
      final keys = await _keyService.deriveFromMnemonic(
        seed,
        network: state.network,
      );

      // Store
      await _storageService.storeWallet(
        mnemonic: mnemonic,
        keys: keys,
        network: state.network,
      );
      await _storageService.confirmBackup();

      _applyNetwork(state.network);
      _utxoService.setNetworkSync(state.network);

      state = WalletState(
        keys: keys,
        network: state.network,
        backupConfirmed: true,
        isInitialized: true,
        isLoading: false,
      );

      // Fetch the balance and start polling
      _refreshBalance();
      _startAutoRefresh();

      debugPrint('Wallet restored successfully');
    } catch (e) {
      debugPrint('Restore error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Restore failed: $e',
      );
    }
  }

  /// Mark seed phrase backup as confirmed.
  Future<void> confirmBackup() async {
    await _storageService.confirmBackup();
    state = state.copyWith(
      backupConfirmed: true,
      clearSeedPhrase: true, // Clear seed from memory after backup
    );
  }

  /// Refresh balance from node.
  Future<void> refreshBalance() async => _refreshBalance();

  /// FN-18: refresh for the Activity screen that SURFACES failures, unlike the
  /// background [_refreshBalance] which swallows them for silent polling. Probes
  /// the backend first — a connectivity/backend outage (the dominant failure a
  /// store reviewer or offline user hits) throws here — so the UI can render a
  /// distinct error state with retry instead of a misleading empty history. On
  /// success it runs the normal best-effort refresh to repopulate balance +
  /// history.
  Future<void> syncActivity() async {
    if (state.address.isEmpty) return;
    await _balanceService.getChainTip(); // throws on backend/connectivity failure
    await _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    final generation = _refreshGeneration;
    // True once a network switch has happened since this refresh started.
    bool stale() => generation != _refreshGeneration;
    try {
      debugPrint('REFRESH: address="${state.address.isEmpty ? "(empty)" : state.address.substring(0, 20)}..."');
      // Primary: ElectrumX-backed balance via Cloudflare Worker
      // This is the authoritative source — indexes ALL addresses without
      // importaddress, catches external deposits, pool payouts, faucet sends.
      if (state.address.isNotEmpty) {
        try {
          // Get balance from ElectrumX (via REST bridge)
          debugPrint('REFRESH[1/3] Fetching balance from ElectrumX...');
          final balResult = await _balanceService.getBalance(state.address);
          if (stale()) return;
          debugPrint('REFRESH[1/3] ElectrumX balance: ${balResult.confirmedSoq} SOQ (${balResult.confirmedSat} sat)');
          debugPrint('REFRESH[1/3] Pending: ${balResult.unconfirmedSoq} SOQ');

          final effectivePending = balResult.unconfirmedSoq;
          state = state.copyWith(
            balance: balResult.confirmedSoq,
            pendingBalance: effectivePending,
          );

          // Get block height from ElectrumX
          final tip = await _balanceService.getChainTip();
          if (stale()) return;
          debugPrint('REFRESH[2/3] Chain tip: $tip');
          state = state.copyWith(blockHeight: tip);

          // Discover UTXOs from ElectrumX and sync to local tracker
          debugPrint('REFRESH[3/3] Fetching UTXOs...');
          final electrumUtxos = await _balanceService.getUtxos(state.address);
          if (stale()) return;
          debugPrint('REFRESH[3/3] Got ${electrumUtxos.length} UTXOs');
          for (final utxo in electrumUtxos) {
            await _utxoService.addUtxo(utxo);
            // Each add awaits secure storage; a switch during one must stop
            // the rest from landing in the new network's partition.
            if (stale()) return;
          }

          // Sync transaction history from ElectrumX → Activity feed
          await _syncTransactionHistory(tip, electrumUtxos, generation);
          if (stale()) return;

          // ── F6 FIX: Auto-clear pending when confirmed balance already
          //    reflects the expected post-TX amount ──
          // When ElectrumX returns unconfirmedSoq == 0 but we still have a
          // local pendingBalance, the TX has confirmed and the pending is
          // stale. Clear it to prevent double-counting on the display.
          if (state.pendingBalance != 0 && effectivePending == 0) {
            debugPrint('REFRESH F6: Clearing stale pendingBalance='
                '${state.pendingBalance} (ElectrumX shows 0 unconfirmed)');
            state = state.copyWith(pendingBalance: 0);
          }

          debugPrint('REFRESH: Complete — balance=${state.balance} SOQ, height=${state.blockHeight}');
          return;
        } catch (e) {
          debugPrint('REFRESH: ElectrumX balance fetch failed, falling back to node: $e');
        }
      } else {
        debugPrint('REFRESH: Skipped — no address set');
      }

      // Fallback: the node itself. The height, then the cached outputs
      // verified against the node; the verification takes the generation
      // check, so its own save is retired by a switch or a wipe as the
      // provider's writes are. (No discovery here: `listunspent` needs a
      // wallet, and the public nodes run with the wallet disabled.)
      try {
        final blockCount = await _rpcService.getBlockCount();
        if (stale()) return;
        state = state.copyWith(blockHeight: blockCount);

        await _utxoService.refresh(cancelled: stale);
        if (stale()) return;
        state = state.copyWith(balance: _utxoService.soqBalance);
      } catch (e) {
        debugPrint('Node fallback also failed: $e');
      }
    } catch (e) {
      debugPrint('Balance refresh error: $e');
    }
  }

  /// Start periodic balance polling — every 30s, fetches from server.
  /// This ensures pool payouts and external deposits appear automatically
  /// without user interaction.
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (state.isInitialized && state.hasWallet) {
        _refreshBalance();
      }
    });
  }

  /// Stop polling (called on wallet wipe).
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _fastRefreshTimer?.cancel();
    _fastRefreshTimer = null;
  }

  // Fast-refresh timer — aggressive polling after a send
  Timer? _fastRefreshTimer;

  /// After sending a TX, poll every 5s for 60s to quickly pick up
  /// on-chain confirmation and clear the "pending" indicator.
  void _startFastRefresh() {
    _fastRefreshTimer?.cancel();
    var ticks = 0;
    const maxTicks = 12; // 12 × 5s = 60s
    _fastRefreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      ticks++;
      if (!state.hasPendingTx || ticks >= maxTicks) {
        debugPrint('FAST-REFRESH: Stopped (pending=${state.hasPendingTx}, ticks=$ticks)');
        timer.cancel();
        _fastRefreshTimer = null;

        // ── F2 FIX: Always clear pendingBalance when fast-refresh ends ──
        // The confirmed balance from ElectrumX is the source of truth.
        // If the TX confirmed, pendingBalance is already 0 (ElectrumX set it).
        // If it didn't confirm in 60s, clear anyway — the user can refresh
        // manually. This prevents the stuck "+6.00 pending" ghost display.
        if (state.hasPendingTx) {
          debugPrint('FAST-REFRESH: Clearing stale pendingBalance=${state.pendingBalance}');
          state = state.copyWith(pendingBalance: 0);
        }
        return;
      }
      debugPrint('FAST-REFRESH[$ticks/$maxTicks]: Polling...');
      _refreshBalance();
    });
  }

  /// Send a real PQ-signed SOQ transaction to the network. Transparent only.
  ///
  /// Returns the transaction ID on success.
  /// Throws [InsufficientFundsException] or [RpcException] on failure.
  Future<String> sendTransaction({
    required String toAddress,
    required double amount,
  }) async {
    if (!state.hasWallet) throw Exception('No wallet');
    // The send screen refuses before the credential on no chain tip; this is
    // the same rule at the provider, for any other caller.
    if (state.blockHeight == 0) throw StateError('No chain tip yet');

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // 1. Fetch LIVE UTXOs from ElectrumX (not stale local cache)
      debugPrint('SEND[2/6] Fetching live UTXOs from ElectrumX...');
      final liveUtxos = await _balanceService.getUtxos(state.address);
      await _utxoService.syncFromRemote(liveUtxos);
      debugPrint('SEND[2/6] ${liveUtxos.length} UTXOs, '
          'total=${liveUtxos.fold<int>(0, (s, u) => s + u.valueSat)} sat');

      // 2. Get keypair — use session cache or derive from mnemonic
      debugPrint('SEND[3/6] Getting FIPS 204 keypair...');
      if (_cachedPk == null || _cachedSk == null) {
        final mnemonic = await _storageService.readMnemonic();
        if (mnemonic == null) throw Exception('Wallet data corrupted');
        final seed = SeedPhrase(words: mnemonic.split(' '));
        final accountIndex = await _storageService.readAccountIndex();
        final (pk, sk) = await _keyService.deriveNativeKeyPair(
          seed,
          network: state.network,
          accountIndex: accountIndex,
        );
        _cachedPk = pk;
        _cachedSk = sk;
        debugPrint('SEND[3/6] Keypair derived and cached (pk ${pk.length} bytes)');
      } else {
        debugPrint('SEND[3/6] Using cached keypair');
      }
      final publicKey = _cachedPk!;
      final secretKey = _cachedSk!;

      // 3. Build, sign, and broadcast
      debugPrint('SEND[4/6] Building transaction...');
      final txid = await _txBuilder.sendTransaction(
        toAddress: toAddress,
        amountSoq: amount,
        secretKey: secretKey,
        publicKey: publicKey,
        myAddress: state.address,
        assetType: AssetType.soq,
        confidential: false,
      );

      // SB-F2: record the outgoing tx in the Activity feed. Append + persist
      // on broadcast success so it shows immediately and survives restart.
      final sentTx = WalletTransaction(
        txid: txid,
        type: TxType.sent,
        amount: amount,
        timestamp: DateTime.now(),
        confirmations: 0,
      );

      // Optimistic balance: immediately deduct the sent amount + fee
      // so the user sees the balance change before on-chain confirmation.
      // Dilithium TXs are ~4kB, so fee ≈ 0.005 SOQ at minrelaytxfee
      final estFee = 0.005;
      final optimisticBalance = state.balance - amount - estFee;
      final updatedHistory = [sentTx, ...state.recentTransactions];
      state = state.copyWith(
        balance: optimisticBalance > 0 ? optimisticBalance : 0,
        pendingBalance: -(amount + estFee),
        isLoading: false,
        recentTransactions: updatedHistory,
      );
      await TxHistoryService.save(updatedHistory);

      debugPrint('SEND[5/6] Tx sent: $txid');
      debugPrint('SEND[5/6] Optimistic balance: ${state.balance} (pending: ${state.pendingBalance})');

      // Fast-refresh: poll every 5s for 60s to quickly pick up confirmation
      // This clears the "pending" indicator as soon as the TX is mined.
      _startFastRefresh();

      return txid;
    } catch (e) {
      debugPrint('SEND[ERROR] $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Transaction failed: $e',
      );
      rethrow;
    }
    // NOTE: the secret key is the session-scoped _cachedSk. It is NOT zeroed
    // here — the cache is cleared in wipeWallet() and clearKeyCache() when the
    // session ends. Zeroing on every TX would defeat the purpose of caching.
  }

  /// Switch network — propagates to ALL services.
  ///
  /// Services switched:
  ///   - RpcService (JSON-RPC endpoint)
  ///   - BalanceService (ElectrumX REST endpoint)
  ///   - UtxoService (UTXO storage partition)
  ///   - TxHistoryService (tx history storage partition)
  ///
  /// The mainnet endpoints are real hostnames that fail closed until genesis
  /// re-homing — switching pre-launch shows honest connection errors, never
  /// fake data.
  ///
  /// Switches run one at a time and the last request wins: a request for the
  /// network already selected, or already being switched to, is a no-op; a
  /// request for another network waits for the switch in flight to commit and
  /// then runs, unless a later request has chosen differently by then.
  Future<void> setNetwork(SoqNetwork network) async {
    if (network == (_switchTarget ?? state.network)) {
      await _switchInFlight;
      return;
    }
    _switchTarget = network;
    final previous = _switchInFlight;
    final mine = Completer<void>();
    _switchInFlight = mine.future;
    try {
      if (previous != null) await previous.catchError((_) {});
      // Superseded while queued: a later request chose another network.
      if (_switchTarget == network) await _switchTo(network);
    } finally {
      if (identical(_switchInFlight, mine.future)) {
        _switchInFlight = null;
        _switchTarget = null;
      }
      mine.complete();
    }
  }

  /// The network a switch in flight is heading to, else null.
  SoqNetwork? _switchTarget;
  Future<void>? _switchInFlight;

  Future<void> _switchTo(SoqNetwork network) async {
    if (network == state.network) return;

    // Hold both polls while the services and the state change, and retire
    // every refresh already in flight: nothing started on the old network
    // may write after this point.
    _refreshTimer?.cancel();
    _fastRefreshTimer?.cancel();
    _fastRefreshTimer = null;
    _refreshGeneration++;
    _parsedTxCache.clear();
    final previous = state.network;
    _applyNetwork(network);
    try {
      await _utxoService.setNetwork(network);

      debugPrint('Network: Switched all services to ${network.displayName}');

      if (state.isInitialized) {
        // Re-derive keys for the new network, at the stored account index
        final mnemonic = await _storageService.readMnemonic();
        if (mnemonic != null) {
          final seed = SeedPhrase(words: mnemonic.split(' '));
          final accountIndex = await _storageService.readAccountIndex();
          final keys = await _keyService.deriveFromMnemonic(
            seed,
            network: network,
            accountIndex: accountIndex,
          );
          await _storageService.storeWallet(
            mnemonic: mnemonic,
            keys: keys,
            network: network,
          );
          clearKeyCache(); // the cached keypair belongs to the old HRP
          // The new network's own history partition, nothing carried across.
          final history = await TxHistoryService.load();
          state = state.copyWith(
            keys: keys,
            network: network,
            balance: 0,
            pendingBalance: 0,
            blockHeight: 0,
            recentTransactions: history,
          );
          _refreshBalance();
          _startAutoRefresh();
        }
      } else {
        state = state.copyWith(network: network);
      }
    } catch (e) {
      // A switch that fails (a storage write refused, a derivation error)
      // leaves nothing half-applied: the services return to the network the
      // state still names, and its poll resumes. The caller sees the error.
      _parsedTxCache.clear();
      _applyNetwork(previous);
      await _utxoService.setNetwork(previous);
      clearKeyCache();
      if (state.isInitialized) {
        _refreshBalance();
        _startAutoRefresh();
      }
      rethrow;
    }
  }

  /// Sync transaction history from ElectrumX into the Activity feed.
  ///
  /// Compares chain-reported txids against locally-tracked transactions
  /// and discovers new incoming TXs (pool payouts, external deposits) that
  /// weren't initiated from SoquShield.
  Future<void> _syncTransactionHistory(
    int tipHeight,
    List<Utxo> currentUtxos,
    int generation,
  ) async {
    try {
      if (state.address.isEmpty) return;

      final chainHistory = await _balanceService.getHistory(state.address);
      if (generation != _refreshGeneration) return;
      if (chainHistory.isEmpty) return;

      // Build a set of txids we already know about
      final knownTxids = state.recentTransactions.map((t) => t.txid).toSet();

      // Build a map of txid → total value from current UTXOs
      // (UTXOs belonging to our address in a given TX = received amount)
      final utxoValueByTxid = <String, double>{};
      for (final utxo in currentUtxos) {
        utxoValueByTxid.update(
          utxo.txid,
          (v) => v + utxo.value,
          ifAbsent: () => utxo.value,
        );
      }

      // Discover new transactions — BOTH directions (bead m4f P2). Sends are
      // recorded locally at broadcast (SB-F2), but after a seed restore that
      // local record is gone, so unknown txids are reconstructed from raw
      // transactions: outputs paying our script = received; inputs spending
      // our own earlier outputs = sent. Single-address wallet, so "ours" is
      // one script compare. SOQ only — USDSOQ outputs ride other witness
      // versions and stay out of this feed.
      final ourSpkHex = hex.encode(_txBuilder.scriptPubKeyForAddress(state.address));
      var rawFetches = 0;
      // Bounded per cycle so a 100-entry restore can't hammer the REST bridge
      // (120 rpm rate limit) — the 30s poll converges over a few cycles.
      const maxRawFetchesPerSync = 40;

      Future<ParsedTx?> parsedTx(String txid) async {
        final cached = _parsedTxCache[txid];
        if (cached != null) return cached;
        if (rawFetches >= maxRawFetchesPerSync) return null;
        rawFetches++;
        try {
          final raw = await _balanceService.getRawTransaction(txid);
          return _parsedTxCache[txid] = TxParser.parse(raw);
        } catch (e) {
          debugPrint('HISTORY: raw fetch/parse failed for $txid: $e');
          return null;
        }
      }

      // Block-time estimate at the 60s target spacing. The REST bridge has no
      // header endpoint, so this is approximate by design (variance in block
      // times) — but derived from height, not fabricated at render time.
      DateTime estimateBlockTime(int confs) => DateTime.now()
          .subtract(Duration(minutes: confs > 0 ? confs : 0));

      final newTxs = <WalletTransaction>[];
      for (final entry in chainHistory) {
        if (knownTxids.contains(entry.txid)) continue;
        final confs = entry.height > 0 ? tipHeight - entry.height + 1 : 0;

        final tx = await parsedTx(entry.txid);
        if (tx == null) {
          // Budget exhausted or fetch failed — fall back to the old
          // UTXO-derived receive detection so fresh deposits still land.
          final amount = utxoValueByTxid[entry.txid];
          if (amount != null && amount > 0) {
            newTxs.add(WalletTransaction(
              txid: entry.txid,
              type: TxType.received,
              amount: amount,
              timestamp: estimateBlockTime(confs),
              confirmations: confs,
            ));
          }
          continue;
        }

        var receivedSat = 0;
        for (final out in tx.outputs) {
          if (hex.encode(out.scriptPubKey) == ourSpkHex) {
            receivedSat += out.valueSat;
          }
        }

        // Inputs we spent: prevouts of a single-address wallet's sends are its
        // own earlier outputs, and those source txs are in this same history.
        var spentSat = 0;
        for (final txIn in tx.inputs) {
          final prev = await parsedTx(txIn.prevTxid);
          if (prev != null && txIn.prevVout < prev.outputs.length) {
            final o = prev.outputs[txIn.prevVout];
            if (hex.encode(o.scriptPubKey) == ourSpkHex) {
              spentSat += o.valueSat;
            }
          }
        }

        if (spentSat > 0) {
          // Net outflow (recipient amount + fee; change already netted out).
          final net = (spentSat - receivedSat) / 100000000.0;
          if (net > 0) {
            newTxs.add(WalletTransaction(
              txid: entry.txid,
              type: TxType.sent,
              amount: net,
              timestamp: estimateBlockTime(confs),
              confirmations: confs,
            ));
          }
        } else if (receivedSat > 0) {
          newTxs.add(WalletTransaction(
            txid: entry.txid,
            type: TxType.received,
            amount: receivedSat / 100000000.0,
            timestamp: estimateBlockTime(confs),
            confirmations: confs,
          ));
        }
      }

      // The raw fetches above awaited; a switch since then means these rows
      // belong to the old network and must not reach the new partition.
      if (generation != _refreshGeneration) return;

      if (newTxs.isNotEmpty) {
        debugPrint('HISTORY: Discovered ${newTxs.length} new incoming TX(s)');
        final merged = [...newTxs, ...state.recentTransactions]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        // Cap at 100 entries
        final capped = merged.length > 100 ? merged.sublist(0, 100) : merged;
        state = state.copyWith(recentTransactions: capped);
        // The save fixes its partition at the call, so the rows land under
        // this network's key whatever a switch does while it awaits.
        await TxHistoryService.save(capped);
      }
    } catch (e) {
      debugPrint('HISTORY: Sync failed (non-fatal): $e');
    }
  }

  /// SECURITY: Zero and clear the session-scoped keypair cache.
  /// Called on wipe, lock, and app background to ensure secret key
  /// material doesn't persist in Dart heap when the wallet isn't active.
  void clearKeyCache() {
    if (_cachedSk != null) {
      _cachedSk!.fillRange(0, _cachedSk!.length, 0);
      _cachedSk = null;
    }
    _cachedPk = null;
  }

  /// Wipe wallet from device. IRREVERSIBLE.
  Future<void> wipeWallet() async {
    _stopAutoRefresh();
    // Retire the refresh in flight: stopping the timers does not cancel a
    // reply already awaited, and it must write nothing after the deletes.
    _refreshGeneration++;
    clearKeyCache(); // Zero secret key from memory FIRST
    // Every network's UTXO partition, through the instance that wrote them:
    // on iOS the two storage instances use different keychain accessibility,
    // and the plugin's deleteAll matches only its own.
    await _utxoService.clearAll();
    await _storageService.wipeWallet(); // SS-10: deleteAll() also clears the XMSS vault seed
    await TxHistoryService.clear(); // F14
    await _wipeResidualPrefsData(); // SS-10: clear residual SharedPreferences data
    state = const WalletState();
  }

  /// SS-10: remove residual per-user data from SharedPreferences so a resold
  /// device carries nothing over to the next owner, across every network
  /// partition. The secure-storage namespace (mnemonic + XMSS vault seed) is
  /// wiped separately via SecureStorageService.wipeWallet(); this covers the
  /// plaintext SharedPreferences surface, including the keys earlier builds
  /// wrote for features this build no longer carries:
  ///   - `soqshield_tx_history_<network>` (the other network's history;
  ///     TxHistoryService.clear() covers only the current one)
  ///   - `soqshield_lightning_*` (pre-Opt2 legacy channel state)
  ///   - `soqshield_channels_<network>` (self-custody channels)
  ///   - `soq_sns_cache_<network>` (SNS name-resolution cache)
  ///   - `soqushield_quests_*` (quest/badge progress)
  Future<void> _wipeResidualPrefsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stale = prefs
          .getKeys()
          .where((k) =>
              k.startsWith('soqshield_tx_history_') ||
              k.startsWith('soqshield_lightning_') ||
              k.startsWith('soqshield_channels_') ||
              k.startsWith('soq_sns_cache_') ||
              k.startsWith('soqushield_quests_'))
          .toList();
      for (final k in stale) {
        await prefs.remove(k);
      }
    } catch (e) {
      debugPrint('[wipeWallet] residual cleanup skipped: $e');
    }
  }
}

final walletProvider = NotifierProvider<WalletNotifier, WalletState>(
    WalletNotifier.new);
