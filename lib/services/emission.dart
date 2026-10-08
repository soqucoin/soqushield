// The emission schedule, for display only: the chain decides what a block
// pays, and these constants say it on screen. Each cites the node line that
// produces it, at soqucoin main c6b7824c1:
//
//   nSubsidyHalvingInterval = 250000      src/chainparams.cpp:201
//   nInitialSubsidy = 100000              src/chainparams.cpp:202
//   the tail, four intervals in            src/soqucoin.cpp:147
//   return 2500 * COIN                     src/soqucoin.cpp:156
//   nPowTargetSpacing = 60                 src/chainparams.cpp:246
//
// Stagenet carries the same values (chainparams.cpp:1211-1212). Regtest does
// not, and this app never runs on regtest.
//
// Copyright 2026 Soqucoin Labs Inc.

class Emission {
  Emission._();

  /// Blocks between subsidy halvings.
  static const int halvingInterval = 250000;

  /// The subsidy of the first interval, in SOQ.
  static const int initialSubsidy = 100000;

  /// The first height of the perpetual tail: four intervals in.
  static const int tailStart = 4 * halvingInterval;

  /// The tail subsidy, in SOQ, from [tailStart] on.
  static const int tailSubsidy = 2500;

  /// The target spacing between blocks.
  static const Duration targetSpacing = Duration(seconds: 60);

  /// The subsidy paid by the block at [height], in SOQ.
  static int subsidyAt(int height) {
    if (height < 0) return initialSubsidy; // no block before genesis
    if (height >= tailStart) return tailSubsidy;
    return initialSubsidy >> (height ~/ halvingInterval);
  }

  /// The next height at which the subsidy changes after [height], or null
  /// once the tail has begun (it never changes again).
  static int? nextChangeAfter(int height) {
    if (height < 0) return halvingInterval;
    if (height >= tailStart) return null;
    return (height ~/ halvingInterval + 1) * halvingInterval;
  }

  /// The time the chain takes from [from] to [to] at the target spacing.
  static Duration timeBetween(int from, int to) =>
      targetSpacing * (to - from).clamp(0, 1 << 40);
}
