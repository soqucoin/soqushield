/// How the wallet presents itself. Today that is one choice: whether the
/// screen may be captured. It is the owner's, and it persists.
///
/// Stored in the shared secure storage alongside the session settings. A
/// wipe deletes the keys by name (SecureStorageService.wipeWallet) and
/// resets the notifier, so the platform goes back to protected too.
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
    this.allowScreenCapture = false,
    this.loaded = false,
  });

  DisplayPrefs copyWith({
    bool? allowScreenCapture,
    bool? loaded,
  }) =>
      DisplayPrefs(
        allowScreenCapture: allowScreenCapture ?? this.allowScreenCapture,
        loaded: loaded ?? this.loaded,
      );
}

class DisplayPrefsNotifier extends Notifier<DisplayPrefs> {
  static const _keyAllowCapture = 'soq_allow_capture_v1';

  /// Every key this notifier stores. A wipe deletes them by name
  /// ([SecureStorageService.displayKeys] names the same list, pinned by a
  /// test): on iOS the wallet instance's deleteAll does not reach them.
  static const storedKeys = [_keyAllowCapture];

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
    var allowed = false;
    try {
      final cap = await _storage.read(key: _keyAllowCapture);
      // Anything other than an explicit "true" means protected. A storage
      // read that fails, or a value written by a build that did not have this
      // setting, lands on the safe side.
      allowed = cap == 'true';
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
        allowScreenCapture: ScreenCapture.ownerAllows, loaded: true);
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
