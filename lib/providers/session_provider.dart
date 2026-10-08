import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/secure_storage_service.dart' show kSharedSecureStorage;
import 'auth_provider.dart';
import 'wallet_provider.dart';

/// Session timeout settings managed in secure storage.
class SessionConfig {
  /// Timeout duration in minutes (0 = disabled)
  final int timeoutMinutes;

  /// Number of failed biometric attempts before wipe warning
  final int failedAttemptLimit;

  /// Current failed attempt count
  final int failedAttempts;

  /// Whether auto-lock on background is enabled
  final bool lockOnBackground;

  /// SB-5: wall-clock instant before which unlock attempts are refused
  /// (anti-brute-force backoff). Persisted so killing/relaunching the app
  /// cannot reset the cooldown. Null when not in a backoff window.
  final DateTime? lockedUntil;

  const SessionConfig({
    this.timeoutMinutes = 5,
    this.failedAttemptLimit = 10,
    this.failedAttempts = 0,
    this.lockOnBackground = true,
    this.lockedUntil,
  });

  SessionConfig copyWith({
    int? timeoutMinutes,
    int? failedAttemptLimit,
    int? failedAttempts,
    bool? lockOnBackground,
    DateTime? lockedUntil,
    bool clearLockout = false,
  }) {
    return SessionConfig(
      timeoutMinutes: timeoutMinutes ?? this.timeoutMinutes,
      failedAttemptLimit: failedAttemptLimit ?? this.failedAttemptLimit,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockOnBackground: lockOnBackground ?? this.lockOnBackground,
      lockedUntil: clearLockout ? null : (lockedUntil ?? this.lockedUntil),
    );
  }

  /// Available timeout options for settings UI.
  static const timeoutOptions = [1, 2, 5, 10, 15, 30, 0]; // 0 = never
  static String timeoutLabel(int minutes) =>
      minutes == 0 ? 'Never' : '$minutes min';
}

/// Manages session security — timeout timer, failed attempts, auto-lock.
class SessionNotifier extends Notifier<SessionConfig> {
  static const _keyTimeout = 'soq_session_timeout_v1';
  static const _keyLockOnBg = 'soq_lock_on_bg_v1';
  static const _keyFailedAttempts = 'soq_failed_attempts_v1';
  static const _keyLockedUntil = 'soq_locked_until_v1';

  final FlutterSecureStorage _storage = kSharedSecureStorage;
  Timer? _inactivityTimer;
  bool _transactionInProgress = false;

  @override
  SessionConfig build() {
    // Load stored config asynchronously
    Future.microtask(() => _loadConfig());
    ref.onDispose(() => _inactivityTimer?.cancel());
    return const SessionConfig();
  }

  Future<void> _loadConfig() async {
    final timeoutStr = await _storage.read(key: _keyTimeout);
    final lockOnBgStr = await _storage.read(key: _keyLockOnBg);
    final failedStr = await _storage.read(key: _keyFailedAttempts);
    final lockedUntilStr = await _storage.read(key: _keyLockedUntil);

    state = SessionConfig(
      timeoutMinutes: int.tryParse(timeoutStr ?? '') ?? 5,
      lockOnBackground: lockOnBgStr != 'false',
      failedAttempts: int.tryParse(failedStr ?? '') ?? 0,
      lockedUntil:
          lockedUntilStr != null ? DateTime.tryParse(lockedUntilStr) : null,
    );

    // Only start timer if wallet is initialized — prevents timeout
    // during onboarding (e.g., user writing down seed phrase).
    try {
      final wallet = ref.read(walletProvider);
      if (wallet.isInitialized) {
        _startTimer();
      }
    } catch (_) {
      // walletProvider may not be initialized yet — skip timer
    }
  }

  /// Pause timeout during active transaction signing/broadcast.
  /// Prevents the wallet from locking mid-send — standard banking-app pattern.
  void pauseForTransaction() {
    _transactionInProgress = true;
    _inactivityTimer?.cancel();
    debugPrint('Session: timeout paused for transaction');
  }

  /// Resume timeout after transaction completes (success or failure).
  /// MUST be called in a finally block to prevent permanent unlock.
  void resumeAfterTransaction() {
    _transactionInProgress = false;
    if (_pausedDuringTransaction) {
      // The app left the screen while the signer held the key; the key is
      // cleared now that the send is over.
      _pausedDuringTransaction = false;
      ref.read(walletProvider.notifier).clearKeyCache();
    }
    if (_lockAfterTransaction) {
      _lockAfterTransaction = false;
      ref.read(authProvider.notifier).lock();
    }
    _startTimer();
    debugPrint('Session: timeout resumed after transaction');
  }

  /// A pause seen while a send was in progress; the key clear it would have
  /// done waits for the send to end.
  bool _pausedDuringTransaction = false;

  /// Record user activity: a touch anywhere in the app restarts the
  /// inactivity timer (the app root reports every pointer down).
  void recordActivity() {
    _startTimer();
  }

  /// Set the session timeout duration.
  Future<void> setTimeoutMinutes(int minutes) async {
    await _storage.write(key: _keyTimeout, value: minutes.toString());
    state = state.copyWith(timeoutMinutes: minutes);
    _startTimer();
  }

  /// Toggle auto-lock on app background.
  Future<void> setLockOnBackground(bool enabled) async {
    await _storage.write(key: _keyLockOnBg, value: enabled.toString());
    state = state.copyWith(lockOnBackground: enabled);
  }

  /// SB-5: escalating backoff applied after [attempts] consecutive failures.
  /// Short waits early (so a fat-fingered owner isn't punished) ramping to long
  /// cooldowns that make online brute force impractical.
  static Duration _backoffFor(int attempts) {
    if (attempts < 3) return Duration.zero;
    if (attempts < 5) return const Duration(seconds: 30);
    if (attempts < 7) return const Duration(minutes: 1);
    if (attempts < 10) return const Duration(minutes: 5);
    return const Duration(minutes: 30); // at/over the wipe-warning limit
  }

  /// Record a failed authentication attempt and arm the backoff window.
  Future<void> recordFailedAttempt() async {
    final newCount = state.failedAttempts + 1;
    await _storage.write(key: _keyFailedAttempts, value: newCount.toString());

    final backoff = _backoffFor(newCount);
    DateTime? lockedUntil;
    if (backoff > Duration.zero) {
      lockedUntil = DateTime.now().add(backoff);
      await _storage.write(
          key: _keyLockedUntil, value: lockedUntil.toIso8601String());
    }
    state = state.copyWith(failedAttempts: newCount, lockedUntil: lockedUntil);

    debugPrint('Failed auth attempt $newCount/${state.failedAttemptLimit}'
        '${backoff > Duration.zero ? ' — locked out for ${backoff.inSeconds}s' : ''}');
  }

  /// Reset failed attempt counter and clear any backoff (on successful auth).
  Future<void> resetFailedAttempts() async {
    await _storage.write(key: _keyFailedAttempts, value: '0');
    await _storage.delete(key: _keyLockedUntil);
    state = state.copyWith(failedAttempts: 0, clearLockout: true);
  }

  /// Remaining backoff before another unlock attempt is permitted (Zero if none).
  Duration get remainingLockout {
    final until = state.lockedUntil;
    if (until == null) return Duration.zero;
    final rem = until.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  /// True while inside an active backoff window — the lock screen must refuse
  /// new attempts until it elapses.
  bool get isInLockout => remainingLockout > Duration.zero;

  /// True once the failed-attempt limit (wipe-warning threshold) is reached.
  bool get isLockedOut => state.failedAttempts >= state.failedAttemptLimit;

  // ── the app's own system UI ──
  //
  // A biometric prompt, the device-credential screen and the share sheet are
  // system UI the app itself raised. On Android they can pause the activity
  // (the credential screen and the share chooser always do), so a background
  // and a foreground event arrive around them exactly as when the user leaves
  // the app. Those cycles must not lock the wallet mid-send, mid-reveal or
  // mid-export: the site raising the UI wraps it in [whileSystemUi], and a
  // pause seen behind it is matched to its resume without a lock, unless the
  // app stayed away longer than [systemUiGrace].
  bool _systemUiActive = false;
  bool _pausedBehindSystemUi = false;
  DateTime? _pausedAt;

  /// How long a pause behind the app's own system UI may last before its
  /// resume counts as a return from elsewhere and locks.
  static const systemUiGrace = Duration(minutes: 1);

  /// The clock, replaceable by a test.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Run [action], which raises system UI of the app's own, without the
  /// background and foreground events around it locking the wallet.
  Future<T> whileSystemUi<T>(Future<T> Function() action) async {
    _systemUiActive = true;
    _pausedBehindSystemUi = false;
    try {
      return await action();
    } finally {
      _systemUiActive = false;
    }
  }

  /// Called when the app is paused (no longer visible).
  ///
  /// A departure clears the cached secret key (re-derived from the mnemonic
  /// on the next sign) and the resume locks. Two pauses do neither: one
  /// behind the app's own prompt or share sheet (a resume within the grace
  /// continues; past it, the resume clears and locks), and one during a send,
  /// whose signer is using that key; the key is cleared when the send ends.
  void onAppBackground() {
    _pausedAt ??= clock();
    if (_systemUiActive) {
      _pausedBehindSystemUi = true;
      return;
    }
    if (_transactionInProgress) {
      _pausedDuringTransaction = true;
      return;
    }
    if (state.lockOnBackground) {
      _inactivityTimer?.cancel();
      ref.read(walletProvider.notifier).clearKeyCache();
      // Lock will be triggered by onAppForeground
    }
  }

  /// Called when the app is resumed. Only a resume that follows a pause is a
  /// return from a departure (the first resume at launch, and a resume after
  /// an inactive state, follow none); a pause behind the app's own system UI,
  /// resumed within [systemUiGrace], is not a departure either; and a send in
  /// progress is never interrupted by a lock (its timeout rule holds it).
  void onAppForeground() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    final behindOwnUi = _pausedBehindSystemUi;
    _pausedBehindSystemUi = false;
    final away =
        pausedAt == null ? Duration.zero : clock().difference(pausedAt);
    final departure = pausedAt != null &&
        !_systemUiActive &&
        (!behindOwnUi || away > systemUiGrace);
    if (departure && state.lockOnBackground) {
      if (_transactionInProgress) {
        // Never under a send. A departure that outlasted the grace locks
        // when the send ends; a short one continues.
        if (away > systemUiGrace) _lockAfterTransaction = true;
      } else {
        // A pause behind the app's own UI skipped the clear; a departure
        // that outlasted the grace clears here.
        if (behindOwnUi) ref.read(walletProvider.notifier).clearKeyCache();
        ref.read(authProvider.notifier).lock();
      }
    }
    _startTimer();
  }

  /// A departure during a send that outlasted the grace: the lock is applied
  /// when the send ends.
  bool _lockAfterTransaction = false;

  /// Start or restart the inactivity timer. Only a wallet past its backup is
  /// timed: a created wallet is initialised while its phrase is still being
  /// written down, and a lock there would route past the backup. Restore and
  /// the backup's confirmation both mark the backup done.
  void _startTimer() {
    _inactivityTimer?.cancel();

    if (state.timeoutMinutes <= 0) return; // Disabled
    if (!_walletBackedUp) return;

    _inactivityTimer = Timer(
      Duration(minutes: state.timeoutMinutes),
      _onTimeout,
    );
  }

  bool get _walletBackedUp {
    try {
      final w = ref.read(walletProvider);
      return w.isInitialized && w.backupConfirmed;
    } catch (_) {
      return false;
    }
  }

  void _onTimeout() {
    if (_transactionInProgress) {
      debugPrint('Session: timeout suppressed — transaction in progress');
      return;
    }
    debugPrint('Session timeout — locking wallet');
    // A7-01: Zero cached secret key on timeout lock, not just on background.
    // Without this, the 2560-byte Dilithium sk persists in heap behind
    // the lock screen after an inactivity timeout.
    ref.read(walletProvider.notifier).clearKeyCache();
    ref.read(authProvider.notifier).lock();
  }
}

/// Session security provider.
final sessionProvider = NotifierProvider<SessionNotifier, SessionConfig>(
  SessionNotifier.new,
);
