// The network's weather: what the chain and the pool report right now, read
// through public endpoints only. Nothing here holds a key, a token or an
// account; the figures are the ones anyone can read from the node's public
// RPC proxy and from the pool's public API, and the app only shows them.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/wallet_keys.dart';
import 'rpc_service.dart';

/// What the selected network's node reports. [reachable] false when the node
/// did not answer; every other field is then zero or null.
class ChainWeather {
  final bool reachable;
  final int height;
  final DateTime? tipTime;
  final double difficulty;

  /// Hashes per second, the node's own estimate (`networkhashps`).
  final double hashrate;
  final int mempoolTx;
  final int peers;
  final DateTime fetchedAt;

  const ChainWeather({
    required this.reachable,
    required this.height,
    required this.tipTime,
    required this.difficulty,
    required this.hashrate,
    required this.mempoolTx,
    required this.peers,
    required this.fetchedAt,
  });

  ChainWeather.unreachable(DateTime at)
      : this(
            reachable: false,
            height: 0,
            tipTime: null,
            difficulty: 0,
            hashrate: 0,
            mempoolTx: 0,
            peers: 0,
            fetchedAt: at);

  /// Time since the tip block, never negative (a tip timestamp may run a
  /// little ahead of the phone's clock).
  Duration sinceTip(DateTime now) {
    final t = tipTime;
    if (t == null) return Duration.zero;
    final d = now.difference(t);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Four read-only calls on the selected network's proxy: the mining summary,
/// the peer count, the tip hash and the tip block (for its time). This is
/// the app's one chain poll; the home's status line derives from it. Any
/// failure yields [ChainWeather.unreachable].
Future<ChainWeather> fetchChainWeather(SoqNetwork network,
    {RpcService? rpc}) async {
  final client = rpc ?? RpcService(network: network);
  try {
    final info = await client.getMiningInfo();
    final net = await client.getNetworkInfo();
    final hash = await client.getBestBlockHash();
    final block = await client.getBlock(hash);
    final time = block['time'];
    // The calls run one after another, so a block can land between the
    // mining summary and the tip: the height is the fetched tip's, the one
    // its time belongs to, and the summary's count is the fallback.
    return ChainWeather(
      reachable: true,
      height: math.max(0, _int(block['height']) ?? _int(info['blocks']) ?? 0),
      tipTime: time is num
          ? DateTime.fromMillisecondsSinceEpoch(time.toInt() * 1000, isUtc: true)
          : null,
      difficulty: _double(info['difficulty']) ?? 0,
      hashrate: _double(info['networkhashps']) ?? 0,
      mempoolTx: _int(info['pooledtx']) ?? 0,
      peers: _int(net['connections']) ?? 0,
      fetchedAt: DateTime.now(),
    );
  } catch (e) {
    debugPrint('WEATHER: chain unreachable: $e');
    return ChainWeather.unreachable(DateTime.now());
  } finally {
    if (rpc == null) client.dispose();
  }
}

/// One region of the pool's stratum front.
class PoolRegion {
  final String region;
  final bool up;
  final int workers;
  const PoolRegion({required this.region, required this.up, required this.workers});
}

/// One block the pool found: its height and when. The finder is the pool's
/// business, not this app's, and is never read.
class PoolBlock {
  final int height;
  final DateTime time;
  const PoolBlock({required this.height, required this.time});
}

/// What the pool reports publicly. Any field may be null when its endpoint
/// did not answer; [reachable] is false only when none did.
class PoolWeather {
  final bool reachable;

  /// Hashes per second, the pool's own stratum rate.
  final double? poolHashrate;
  final int? activeMiners;
  final int? workers;
  final int? blocksPerHour;
  final int? blocks24h;
  final int? blocks7d;
  final double? luck24h;
  final double? luck7d;
  final double? roundEffortPct;
  final String? overall; // 'operational' and the like
  final List<PoolRegion> regions;
  final String? nextPayoutEta;
  final double? feeRate; // 0.015 = 1.50 percent
  final String? scheme; // 'PPLNS'
  final List<PoolBlock> latestBlocks;
  final DateTime fetchedAt;

  const PoolWeather({
    required this.reachable,
    this.poolHashrate,
    this.activeMiners,
    this.workers,
    this.blocksPerHour,
    this.blocks24h,
    this.blocks7d,
    this.luck24h,
    this.luck7d,
    this.roundEffortPct,
    this.overall,
    this.regions = const [],
    this.nextPayoutEta,
    this.feeRate,
    this.scheme,
    this.latestBlocks = const [],
    required this.fetchedAt,
  });
}

/// The pool's public API host. The only pool host this app talks to.
const String kPoolApiHost = 'api.soqupool.com';

/// Four public GETs on the pool's API, each failing on its own. The finder of
/// a block and anything about an account is never read.
Future<PoolWeather> fetchPoolWeather({http.Client? client}) async {
  final c = client ?? http.Client();
  Future<Map<String, dynamic>?> get(String path) async {
    try {
      final r = await c
          .get(Uri.https(kPoolApiHost, path))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body);
      return d is Map<String, dynamic> ? d : null;
    } catch (e) {
      debugPrint('WEATHER: pool $path failed: $e');
      return null;
    }
  }

  try {
    final results = await Future.wait(
        [get('/pool'), get('/pool/luck'), get('/pool/status'), get('/pool/terms')]);
    return _parsePool(results);
  } catch (e) {
    // No answer, however shaped, stops the poll: a body the reader cannot
    // take reads as the pool not answering.
    debugPrint('WEATHER: pool unreadable: $e');
    return PoolWeather(reachable: false, fetchedAt: DateTime.now());
  } finally {
    if (client == null) c.close();
  }
}

PoolWeather _parsePool(List<Map<String, dynamic>?> results) {
  {
    final pool = results[0], luck = results[1], status = results[2], terms = results[3];
    final now = DateTime.now();
    if (pool == null && luck == null && status == null && terms == null) {
      return PoolWeather(reachable: false, fetchedAt: now);
    }
    final rate = pool?['PoolHashRate'];
    final round = luck?['currentRound'];
    return PoolWeather(
      reachable: true,
      poolHashrate: rate is Map ? _double(rate['Raw']) : null,
      activeMiners: _int(pool?['ActiveMiners']),
      workers: _int(pool?['Workers']),
      blocksPerHour: _int(pool?['BlocksPerHour']),
      blocks24h: _int(luck?['blocksLast24h']),
      blocks7d: _int(luck?['blocksLast7d']),
      luck24h: _double(luck?['luck24h']),
      luck7d: _double(luck?['luck7d']),
      roundEffortPct: round is Map ? _double(round['effortPct']) : null,
      overall: _str(status?['overall']),
      regions: _regions(status?['nodes']),
      nextPayoutEta: (status?['payouts'] is Map)
          ? _str((status!['payouts'] as Map)['next_eta'])
          : null,
      feeRate: _double(terms?['fee_rate']),
      scheme: _str(terms?['scheme']),
      latestBlocks: _blocks(pool?['LatestBlocks'], now),
      fetchedAt: now,
    );
  }
}

List<PoolRegion> _regions(Object? raw) {
  if (raw is! List) return const [];
  final out = <PoolRegion>[];
  for (final n in raw) {
    if (n is! Map) continue;
    final region = n['region'];
    if (region is! String) continue;
    out.add(PoolRegion(
      region: region,
      up: n['status'] == 'up',
      workers: _int(n['workers']) ?? 0,
    ));
  }
  return out;
}

/// The chain this app shows, as the pool's feed names it.
const String _poolChainName = 'soqucoin';

/// The pool's rows carry `created` as `2026-10-06 04:08:09.059411 +0000 UTC`
/// and `minutesAgo`; the first is read, the second is the fallback. The feed
/// lists every chain the pool mines in one list (Dogecoin rows sit between
/// Soqucoin rows live), so a row is kept only when it names this chain.
List<PoolBlock> _blocks(Object? raw, DateTime now) {
  if (raw is! List) return const [];
  final out = <PoolBlock>[];
  for (final b in raw) {
    if (b is! Map) continue;
    final chain = b['chain'];
    if (chain is! String || chain.toLowerCase() != _poolChainName) continue;
    final height = _int(b['blockHeight']);
    if (height == null) continue;
    DateTime? time;
    final created = b['created'];
    if (created is String && created.length >= 19) {
      time = DateTime.tryParse('${created.substring(0, 10)}T${created.substring(11, 19)}Z');
    }
    final ago = _int(b['minutesAgo']);
    // A row with no usable time is dropped; a fallback age past a year is
    // not a recent block and is dropped too.
    time ??= (ago == null || ago < 0 || ago > 525600)
        ? null
        : now.subtract(Duration(minutes: ago));
    if (time == null) continue;
    out.add(PoolBlock(height: height, time: time));
  }
  return out;
}

/// Typed accessors: anything but the expected shape reads as absent, and a
/// number that is not finite (a hostile host's `1e400`) reads as absent too.
int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;
double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _str(Object? v) => v is String ? v : null;

// ── formatting, one voice for the figures ──

/// `20.4 GH/s`, `6.9 PH/s`, `850 H/s`.
String fmtHashrate(double hps) {
  if (!hps.isFinite || hps < 0) return '—';
  const units = ['H/s', 'kH/s', 'MH/s', 'GH/s', 'TH/s', 'PH/s', 'EH/s'];
  var v = hps;
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  final digits = i == 0 ? 0 : (v < 10 ? 2 : 1);
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

/// `407.8`, `97.0M`, `1.2k`.
String fmtDifficulty(double d) {
  if (!d.isFinite || d < 0) return '—';
  if (d >= 1e9) return '${(d / 1e9).toStringAsFixed(1)}G';
  if (d >= 1e6) return '${(d / 1e6).toStringAsFixed(1)}M';
  if (d >= 1e4) return '${(d / 1e3).toStringAsFixed(1)}k';
  return d.toStringAsFixed(1);
}

/// `0:42`, `12:05`, `1:02:33`.
String fmtClock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// `~96 D`, `~5 H`, `~12 MIN`, for a span the chain will take at its target
/// spacing.
String fmtEta(Duration d) {
  if (d.inDays >= 2) return '~${d.inDays} D';
  if (d.inHours >= 2) return '~${d.inHours} H';
  return '~${d.inMinutes} MIN';
}

/// `1 MIN AGO`, `12 MIN AGO`, `3 HR AGO`, `JUST NOW`.
String fmtAgo(Duration d) {
  if (d.inMinutes < 1) return 'JUST NOW';
  if (d.inMinutes < 60) return '${d.inMinutes} MIN AGO';
  if (d.inHours < 24) return '${d.inHours} HR AGO';
  return '${d.inDays} D AGO';
}

/// `07:02:16 UTC`, the clock time of a block.
String fmtUtcTime(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(u.hour)}:${two(u.minute)}:${two(u.second)} UTC';
}

/// The time since the last block for a screen reader, to the minute, so a
/// focused reading does not change every second: `under a minute`,
/// `1 minute`, `12 minutes`, `1 hour 2 minutes`.
String fmtSpokenSince(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  String unit(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
  if (d.inHours < 1) return unit(d.inMinutes, 'minute');
  final m = d.inMinutes % 60;
  return m == 0
      ? unit(d.inHours, 'hour')
      : '${unit(d.inHours, 'hour')} ${unit(m, 'minute')}';
}
