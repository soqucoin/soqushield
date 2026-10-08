import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'weather_provider.dart';

/// Chain status for the home's status line and custody line: the height,
/// the peer count and whether the node answered at all.
class NetworkStats {
  final int blocks;
  final int peers;

  /// False when the poll could not reach the node. The home screen renders
  /// OFFLINE from this; a failed poll must never read as a live chain.
  final bool reachable;

  const NetworkStats({
    required this.blocks,
    required this.peers,
    required this.reachable,
  });

  const NetworkStats.empty() : blocks = 0, peers = 0, reachable = false;
}

/// Derived from the app's one chain poll (chainWeatherProvider), so the
/// home and the Network screen read the same answer and the node is asked
/// once. Loading until the first poll returns.
final networkStatsProvider = Provider<AsyncValue<NetworkStats>>((ref) =>
    ref.watch(chainWeatherProvider).whenData((w) => NetworkStats(
          blocks: w.height,
          peers: w.peers,
          reachable: w.reachable,
        )));
