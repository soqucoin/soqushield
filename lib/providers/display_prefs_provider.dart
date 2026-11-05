/// How the wallet presents itself: whether balances are hidden, and whether
/// the screen may be captured. Both are the owner's choice and both persist.
///
/// Hiding balances used to be a tap on the Home readout and nothing more — it
/// lived in that screen's local state, so it came undone the moment you
/// switched tabs or reopened the app. Someone who hides their balance to hand
/// the phone over wants it to STAY hidden.
///
/// Stored in the shared secure storage alongside the session settings. A
/// wipe deletes the keys by name (SecureStorageService.wipeWallet) and
/// resets the notifier: balances shown, the platform back to protected.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/fiat_currency.dart';
import '../services/screen_capture.dart';
import '../services/secure_storage_service.dart' show kSharedSecureStorage;

@immutable
class DisplayPrefs {
  /// Hide every figure that says how much the wallet holds.
  final bool hideBalances;

  /// Whether to show what a balance is worth in money at all.
  ///
  /// ⛔ Defaults to FALSE. The wallet's own unit is SOQ; a money figure is an
  /// extra the owner asks for, read from a rate the company cached. Off by
  /// default also means a wallet that has never been into Settings makes no
  /// price request at all.
  final bool showFiat;

  /// The currency money figures are shown in.
  final FiatCurrency currency;

  /// Whether the OS may capture this app's screen.
  ///
  /// ⛔ Defaults to FALSE — protection on. A wallet that silently permitted
  /// screenshots would also permit screen RECORDING and casting, which is the
  /// live channel in a remote-support scam. The owner can turn it off, but it
  /// has to be a decision they made.
  final bool allowScreenCapture;

  /// False until the stored value has been read.
  final bool loaded;

  const DisplayPrefs({
    this.hideBalances = false,
    this.showFiat = false,
    this.currency = FiatCurrency.usd,
    this.allowScreenCapture = false,
    this.loaded = false,
  });

  DisplayPrefs copyWith({
    bool? hideBalances,
    bool? showFiat,
    FiatCurrency? currency,
    bool? allowScreenCapture,
    bool? loaded,
  }) =>
      DisplayPrefs(
        hideBalances: hideBalances ?? this.hideBalances,
        showFiat: showFiat ?? this.showFiat,
        currency: currency ?? this.currency,
        allowScreenCapture: allowScreenCapture ?? this.allowScreenCapture,
        loaded: loaded ?? this.loaded,
      );
}

class DisplayPrefsNotifier extends Notifier<DisplayPrefs> {
  static const _keyHideBalances = 'soq_hide_balances_v1';
  static const _keyShowFiat = 'soq_show_fiat_v1';
  static const _keyCurrency = 'soq_fiat_currency_v1';
  static const _keyAllowCapture = 'soq_allow_capture_v1';

  /// Every key this notifier stores. A wipe deletes them by name
  /// ([SecureStorageService.displayKeys] names the same list, pinned by a
  /// test): on iOS the wallet instance's deleteAll does not reach them.
  static const storedKeys = [
    _keyHideBalances,
    _keyShowFiat,
    _keyCurrency,
    _keyAllowCapture,
  ];

  FlutterSecureStorage get _storage => kSharedSecureStorage;

  /// The stored values, read once. Every setter waits on it, so a read that
  /// finishes late can never overwrite a choice made while it was pending.
  late Future<void> _ready;

  @override
  DisplayPrefs build() {
    _ready = Future.microtask(_load);
    return const DisplayPrefs();
  }

  Future<void> _load() async {
    // An awaited storage read, so the provider can be disposed underneath
    // this — a container torn down. Writing `state` after that throws, so
    // each gap is followed by a mounted check.
    var hide = false;
    var fiat = false;
    String? cur;
    var allowed = false;
    try {
      // Read separately: a failure on one key does not cost the others.
      hide = await _readFlag(_keyHideBalances);
      // Anything but an explicit "true" leaves the money line off, so a
      // failed read never switches it on behind the owner.
      fiat = await _readFlag(_keyShowFiat);
      cur = await _readString(_keyCurrency);
      allowed = await _readFlag(_keyAllowCapture);
    } catch (e) {
      debugPrint('DisplayPrefs: load failed, keeping defaults: $e');
    }
    if (!ref.mounted) return;
    // Apply the stored capture rule to the platform. Until this runs the
    // native side is in its own default, which is protected; a phrase
    // screen's shield keeps it protected whatever this says.
    await ScreenCapture.setAllowed(allowed);
    if (!ref.mounted) return;
    state = DisplayPrefs(
        hideBalances: hide,
        showFiat: fiat,
        currency: FiatCurrency.fromCode(cur),
        allowScreenCapture: ScreenCapture.ownerAllows,
        loaded: true);
  }

  /// Anything other than an explicit "true" is false. A storage read that
  /// fails, or a value written by a build that did not have the setting,
  /// lands on the default: protected, balances shown, the money line off.
  Future<bool> _readFlag(String key) async {
    try {
      return await _storage.read(key: key) == 'true';
    } catch (e) {
      debugPrint('DisplayPrefs: $key unreadable, using the default: $e');
      return false;
    }
  }

  /// The stored string, or null when it is absent or cannot be read.
  Future<String?> _readString(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('DisplayPrefs: $key unreadable, using the default: $e');
      return null;
    }
  }

  /// Hide or show every balance figure.
  Future<void> setHideBalances(bool hide) async {
    await _ready;
    if (!ref.mounted) return;
    state = state.copyWith(hideBalances: hide);
    await _storage.write(key: _keyHideBalances, value: hide.toString());
  }

  /// Flip the hidden state — the Home readout's tap gesture. It flips the
  /// loaded value, not the default that stood in before the read.
  Future<void> toggleHideBalances() async {
    await _ready;
    if (!ref.mounted) return;
    await setHideBalances(!state.hideBalances);
  }

  /// Turn the money line on or off.
  Future<void> setShowFiat(bool show) async {
    await _ready;
    if (!ref.mounted) return;
    state = state.copyWith(showFiat: show);
    await _storage.write(key: _keyShowFiat, value: show.toString());
  }

  /// Choose the currency money figures are shown in.
  Future<void> setCurrency(FiatCurrency currency) async {
    await _ready;
    if (!ref.mounted) return;
    if (currency == state.currency) return;
    state = state.copyWith(currency: currency);
    await _storage.write(key: _keyCurrency, value: currency.code);
  }

  /// Allow or forbid OS screen capture. Returns whether the choice took
  /// effect AND was stored.
  ///
  /// The platform is told first and the preference is only stored once that
  /// succeeded, so a stored "allowed" can never outlive a screen the native
  /// side is still protecting. A platform refusal leaves everything as it
  /// was. A failed store of "allowed" puts protection back; a failed store
  /// of "protected" keeps protection on while storage still says allowed,
  /// and the caller tells the owner the change was not saved.
  Future<bool> setAllowScreenCapture(bool allow) async {
    await _ready;
    if (!ref.mounted) return false;
    if (!await ScreenCapture.setAllowed(allow)) return false;
    if (!ref.mounted) return false;
    state = state.copyWith(allowScreenCapture: allow);
    try {
      await _storage.write(key: _keyAllowCapture, value: allow.toString());
      return true;
    } catch (e) {
      debugPrint('DisplayPrefs: capture choice not stored: $e');
      if (allow) {
        await ScreenCapture.setAllowed(false);
        if (ref.mounted) state = state.copyWith(allowScreenCapture: false);
      }
      return false;
    }
  }

  /// Back to protected, for a wipe: the next wallet on this device must not
  /// inherit the last one's capture permission. The stored keys go with
  /// SecureStorageService.wipeWallet.
  Future<void> resetToDefaults() async {
    await _ready;
    if (!ref.mounted) return;
    state = const DisplayPrefs(loaded: true);
    await ScreenCapture.setAllowed(false);
  }
}

final displayPrefsProvider =
    NotifierProvider<DisplayPrefsNotifier, DisplayPrefs>(
        DisplayPrefsNotifier.new);

/// Whether balances are hidden right now — the one thing most widgets need.
///
/// Masked until the stored value has been read: after a restart with hiding
/// on, the first frames must not show the holdings before the read lands.
final hideBalancesProvider = Provider<bool>((ref) => ref.watch(
    displayPrefsProvider.select((p) => !p.loaded || p.hideBalances)));

/// The currency money figures are shown in.
final fiatCurrencyProvider = Provider<FiatCurrency>(
    (ref) => ref.watch(displayPrefsProvider.select((p) => p.currency)));
