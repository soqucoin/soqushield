// The network's weather: what the chain reports right now and who found its
// last 1,440 blocks, read through public endpoints only. Nothing here holds
// a key, a token or an account; the figures are the ones anyone can read
// from the node's public RPC proxy and from the public explorer, and the app
// only shows them.
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

/// One pool's share of the window's blocks, as the public explorer groups
/// them: the pool's name when the explorer knows the address the pool pays
/// its block reward to, else that address itself. The address is the pool's
/// own, never a member's: a pool pays its members later, from its own
/// wallet, and nothing here reads a member.
class PoolShare {
  /// The explorer's name for the pool, or empty when it has none.
  final String name;

  /// The payout address the explorer grouped by, when it has no name for it.
  final String? address;
  final int blocks;
  const PoolShare({required this.name, this.address, required this.blocks});

  /// The name, or `sq1pyvjd6u…gmgyul` for a pool the explorer has no name
  /// for.
  String get label {
    final a = address;
    if (a == null) return name;
    if (a.length <= 20) return a;
    return '${a.substring(0, 10)}…${a.substring(a.length - 6)}';
  }
}

/// Who found the last [kPoolsWindow] blocks on Mainnet, read from the
/// public explorer's mining summary over that many blocks back from the
/// tip. [reachable] false when the explorer did not answer; [pools] is then
/// empty.
class PoolsWeather {
  final bool reachable;

  /// The window's first and last height, from the explorer's tip.
  final int startHeight;
  final int endHeight;

  /// The blocks the summary grouped, over every group, listed or not: the
  /// denominator of every share.
  final int blocks;

  /// The groups that found a block, listed or not; null reads as the
  /// listed ones.
  final int? groups;

  /// The listed pools, most blocks first, a tie by label: at most
  /// [kPoolsListed] of them.
  final List<PoolShare> pools;
  final DateTime fetchedAt;

  const PoolsWeather({
    required this.reachable,
    this.startHeight = 0,
    this.endHeight = 0,
    this.blocks = 0,
    this.groups,
    this.pools = const [],
    required this.fetchedAt,
  });

  /// How many pools found a block, the listed ones and the rest.
  int get groupCount => groups ?? pools.length;

  /// How many found a block but are not listed.
  int get unlisted => groupCount - pools.length;

  /// A pool's share of the window's blocks, 0 to 1.
  double shareOf(PoolShare pool) =>
      blocks <= 0 ? 0 : (pool.blocks / blocks).clamp(0.0, 1.0);
}

/// The window the pools are read over, in blocks: about a day at the
/// chain's sixty-second target, which the chain only approximates, so the
/// window is named in blocks wherever it is shown.
const int kPoolsWindow = 1440;

/// The most pools listed from one answer.
const int kPoolsListed = 24;

/// The longest name kept.
const int _maxNameLength = 40;

/// Two public GETs on the Mainnet explorer, the host the network endpoints
/// name: the tip height, then the mining summary over the [kPoolsWindow]
/// blocks ending at it. The explorer groups the blocks by the address each
/// coinbase pays, or by the pool's name when it knows the address; this
/// reader keeps the names, the addresses and the counts and nothing else.
/// The pools report on Mainnet whatever network the wallet is on. Any
/// failure, at either call, yields an unreachable answer.
Future<PoolsWeather> fetchPoolsWeather({http.Client? client}) async {
  final c = client ?? http.Client();
  final explorer = SoqNetwork.mainnet.explorerUrl;
  try {
    if (explorer == null) {
      return PoolsWeather(reachable: false, fetchedAt: DateTime.now());
    }
    final origin = Uri.parse(explorer);
    final tipAnswer = await c
        .get(origin.replace(path: '/api/blocks/tip/height'))
        .timeout(const Duration(seconds: 8));
    final tip = tipAnswer.statusCode == 200
        ? int.tryParse(tipAnswer.body.trim())
        : null;
    if (tip == null || tip < 0) {
      return PoolsWeather(reachable: false, fetchedAt: DateTime.now());
    }
    final start = math.max(0, tip - kPoolsWindow + 1);
    final answer = await c
        .get(origin.replace(path: '/api/mining/miner-summary', queryParameters: {
          'startHeight': '$start',
          'endHeight': '$tip',
        }))
        .timeout(const Duration(seconds: 25));
    if (answer.statusCode != 200) {
      return PoolsWeather(reachable: false, fetchedAt: DateTime.now());
    }
    // Read as UTF-8 whatever charset the answer claims: a pool's name is
    // text, and a wrong label on the answer must not drop the day's pools.
    final body = jsonDecode(utf8.decode(answer.bodyBytes, allowMalformed: true));
    if (body is! Map<String, dynamic>) {
      return PoolsWeather(reachable: false, fetchedAt: DateTime.now());
    }
    return _parsePools(body, start, tip);
  } catch (e) {
    // No answer, however shaped, stops the poll: a body the reader cannot
    // take reads as the explorer not answering.
    debugPrint('WEATHER: pools unreadable: $e');
    return PoolsWeather(reachable: false, fetchedAt: DateTime.now());
  } finally {
    if (client == null) c.close();
  }
}

/// The explorer's own prefix on a group it could only name by its address.
const String _addressOnly = 'address-only:';

/// The explorer's `miners` map: one entry per group, keyed by the pool's
/// name or by `address-only:` and the address, each with the heights of
/// its blocks. Every group with a block counts towards the total and the
/// group count; a group whose key reads as nothing is counted but not
/// listed, and the listed ones are sorted and capped at [kPoolsListed], so
/// a share is always a share of every block grouped. The explorer's own
/// counts and fees are not read: the count is the heights' count.
PoolsWeather _parsePools(Map<String, dynamic> body, int start, int end) {
  final now = DateTime.now();
  final miners = body['miners'];
  final pools = <PoolShare>[];
  var total = 0;
  var groups = 0;
  if (miners is Map) {
    for (final entry in miners.entries) {
      final key = entry.key;
      final group = entry.value;
      if (key is! String || group is! Map) continue;
      final heights = group['blocks'];
      if (heights is! List || heights.isEmpty) continue;
      total += heights.length;
      groups++;
      if (key.startsWith(_addressOnly)) {
        final address = key.substring(_addressOnly.length);
        if (_looksLikeAddress(address)) {
          pools.add(PoolShare(name: '', address: address, blocks: heights.length));
          continue;
        }
      }
      final name = _cleanName(key);
      if (name.isEmpty) continue;
      pools.add(PoolShare(name: name, blocks: heights.length));
    }
  }
  pools.sort((a, b) {
    final byBlocks = b.blocks.compareTo(a.blocks);
    return byBlocks != 0 ? byBlocks : a.label.compareTo(b.label);
  });
  return PoolsWeather(
    reachable: true,
    startHeight: start,
    endHeight: end,
    blocks: total,
    groups: groups,
    pools: pools.take(kPoolsListed).toList(),
    fetchedAt: now,
  );
}

/// A Mainnet payout address as the explorer writes one: the bech32m
/// alphabet, lower case, of a plausible length.
bool _looksLikeAddress(String s) =>
    s.length >= 14 &&
    s.length <= 90 &&
    RegExp(r'^[a-z0-9]+$').hasMatch(s);

/// A name with its control and invisible characters removed, trimmed and
/// cut to [_maxNameLength]: a hostile host's name renders as text, no
/// longer than a line.
String _cleanName(String raw) {
  final cleaned = raw
      .replaceAll(
          RegExp('[\\u0000-\\u001F\\u007F-\\u009F\\u200B-\\u200F'
              '\\u202A-\\u202E\\u2066-\\u2069\\uFEFF]'),
          '')
      .trim();
  return cleaned.length <= _maxNameLength
      ? cleaned
      : cleaned.substring(0, _maxNameLength);
}

/// Typed accessors: anything but the expected shape reads as absent, and a
/// number that is not finite (a hostile host's `1e400`) reads as absent too.
int? _int(Object? v) => v is num && v.isFinite ? v.toInt() : null;
double? _double(Object? v) => v is num && v.isFinite ? v.toDouble() : null;

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

/// `72%`, `9%`, and `<1%` for a share that rounds to nothing but is not
/// nothing.
String fmtShare(double share) {
  if (!share.isFinite || share < 0) return '—';
  final pct = (share * 100).round();
  if (pct == 0 && share > 0) return '<1%';
  return '$pct%';
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
