import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wallet_keys.dart';
import '../services/weather_service.dart';
import 'launch_state_provider.dart';
import 'wallet_provider.dart';

/// The selected network's weather, the app's one chain poll, every 30
/// seconds from its node; watch() re-subscribes on a network switch. The
/// home's status line (networkStatsProvider) derives from it. A Mainnet
/// answer marks the install as having seen Mainnet live.
///
/// Kept while the app runs, so the home's figures hold across the tabs and
/// the pushed routes; with no watcher (the lock screen, onboarding) the poll
/// pauses on its last figure. A watcher returning after a long pause reads
/// that figure until the next tick, so the Network screen shows no clock for
/// a figure older than the poll period.
final chainWeatherProvider = StreamProvider<ChainWeather>((ref) async* {
  final network = ref.watch(walletProvider.select((w) => w.network));
  Future<ChainWeather> poll() async {
    final weather = await fetchChainWeather(network);
    if (weather.reachable && network == SoqNetwork.mainnet && ref.mounted) {
      ref.read(mainnetSeenLiveProvider.notifier).markMainnetLive();
    }
    return weather;
  }

  yield await poll();
  await for (final _ in Stream.periodic(pollPeriod)) {
    yield await poll();
  }
});

/// The chain poll's period; a figure older than this is stale.
const Duration pollPeriod = Duration(seconds: 30);

/// The pool's public weather, polled every minute while the Network tab is
/// shown and disposed when it is not, so each visit starts with a fresh poll.
/// Not tied to the wallet's network: the pool reports on the chain it mines.
final poolWeatherProvider =
    StreamProvider.autoDispose<PoolWeather>((ref) async* {
  yield await fetchPoolWeather();
  await for (final _ in Stream.periodic(const Duration(seconds: 60))) {
    yield await fetchPoolWeather();
  }
});
