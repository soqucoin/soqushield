import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The preferences instance the app's entry point loads before the first
/// frame, so a flag kept there is known at the first build. Null in a scope
/// that loaded none (a test, or an entry point whose load failed): the flag
/// then loads asynchronously and reads false until it has.
final preloadedPreferencesProvider = Provider<SharedPreferences?>((_) => null);

/// Whether this install has ever seen Mainnet answer.
///
/// Before launch the mainnet endpoints do not answer, and the app says so
/// ("Mainnet opens at launch"). Once they have answered, an unreachable
/// Mainnet is an outage, and the app says that instead. The flag is kept in
/// plain preferences: it is not a secret, it is about the network and not
/// the wallet (a wipe leaves it), and it must survive a restart.
///
/// With the preferences preloaded, the stored value is the first value, so
/// a post-launch install that starts offline never shows the pre-launch
/// line, not even for the first frames.
class MainnetSeenLiveNotifier extends Notifier<bool> {
  static const key = 'soqshield_mainnet_seen_live';

  @override
  bool build() {
    final preloaded = ref.watch(preloadedPreferencesProvider);
    if (preloaded != null) return preloaded.getBool(key) == true;
    Future.microtask(_load);
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) state = true;
  }

  /// Record that a Mainnet poll was answered. Idempotent.
  Future<void> markMainnetLive() async {
    if (state) return;
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
  }
}

final mainnetSeenLiveProvider =
    NotifierProvider<MainnetSeenLiveNotifier, bool>(MainnetSeenLiveNotifier.new);
