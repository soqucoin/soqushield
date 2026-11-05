/// How the wallet presents itself: whether balances are hidden, and whether
/// the screen may be captured. Both are the owner's choice and both persist.
///
/// Hiding balances used to be a tap on the Home readout and nothing more — it
/// lived in that screen's local state, so it came undone the moment you
/// switched tabs or reopened the app. Someone who hides their balance to hand
/// the phone over wants it to STAY hidden.
///
/// Stored in the shared secure storage alongside the session settings, so a
/// wipe clears it with everything else (SecureStorageService.wipeWallet
/// calls deleteAll on that namespace).
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/screen_capture.dart';
import '../services/secure_storage_service.dart' show kSharedSecureStorage;

@immutable
class DisplayPrefs {
  /// Hide every figure that says how much the wallet holds.
  final bool hideBalances;

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
    this.allowScreenCapture = false,
    this.loaded = false,
  });

  DisplayPrefs copyWith({
    bool? hideBalances,
    bool? allowScreenCapture,
    bool? loaded,
  }) =>
      DisplayPrefs(
        hideBalances: hideBalances ?? this.hideBalances,
        allowScreenCapture: allowScreenCapture ?? this.allowScreenCapture,
        loaded: loaded ?? this.loaded,
      );
}

class DisplayPrefsNotifier extends Notifier<DisplayPrefs> {
  static const _keyHideBalances = 'soq_hide_balances_v1';
  static const _keyAllowCapture = 'soq_allow_capture_v1';

  FlutterSecureStorage get _storage => kSharedSecureStorage;

  @override
  DisplayPrefs build() {
    Future.microtask(_load);
    return const DisplayPrefs();
  }

  Future<void> _load() async {
    // An awaited storage read, so the provider can be disposed underneath
    // this — a wipe invalidating it, or a container torn down. Writing
    // `state` after that throws, so the gap is followed by a mounted check.
    var allowed = false;
    try {
      final hide = await _storage.read(key: _keyHideBalances);
      if (!ref.mounted) return;
      final cap = await _storage.read(key: _keyAllowCapture);
      if (!ref.mounted) return;

      // Anything other than an explicit "true" means protected. A storage
      // read that fails, or a value written by a build that did not have this
      // setting, lands on the safe side.
      allowed = cap == 'true';
      state = DisplayPrefs(
        hideBalances: hide == 'true',
        allowScreenCapture: allowed,
        loaded: true,
      );
    } catch (e) {
      debugPrint('DisplayPrefs: load failed, keeping defaults: $e');
      if (!ref.mounted) return;
      state = state.copyWith(loaded: true);
    }
    // Apply the stored capture rule to the platform. Until this runs the
    // native side is in its own default, which is protected. Read from the
    // local, not from `state`, which this must not touch after a dispose.
    await ScreenCapture.setAllowed(allowed);
  }

  /// Hide or show every balance figure.
  Future<void> setHideBalances(bool hide) async {
    state = state.copyWith(hideBalances: hide);
    await _storage.write(key: _keyHideBalances, value: hide.toString());
  }

  /// Flip the hidden state — the Home readout's tap gesture.
  Future<void> toggleHideBalances() => setHideBalances(!state.hideBalances);

  /// Allow or forbid OS screen capture.
  ///
  /// The platform is told first and the preference is only stored once that
  /// succeeded, so a stored "allowed" can never outlive a screen the native
  /// side is still protecting (or the reverse — which would be worse).
  Future<void> setAllowScreenCapture(bool allow) async {
    await ScreenCapture.setAllowed(allow);
    state = state.copyWith(allowScreenCapture: allow);
    await _storage.write(key: _keyAllowCapture, value: allow.toString());
  }
}

final displayPrefsProvider =
    NotifierProvider<DisplayPrefsNotifier, DisplayPrefs>(
        DisplayPrefsNotifier.new);

/// Whether balances are hidden right now — the one thing most widgets need.
final hideBalancesProvider = Provider<bool>(
    (ref) => ref.watch(displayPrefsProvider.select((p) => p.hideBalances)));
