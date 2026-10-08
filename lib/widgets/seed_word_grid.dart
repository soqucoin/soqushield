// The recovery-phrase grid shared by the backup and the restore screens.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/instrument.dart';

/// Twenty-four cells in three columns, sized to the height the grid is given:
/// every row shows without scrolling whenever a cell can be at least
/// [minCellHeight] tall; below that (a small phone, the keyboard up) the grid
/// scrolls. The cells and their numbering are the caller's, through
/// [cellBuilder].
class SeedWordGrid extends StatelessWidget {
  final int count;
  final IndexedWidgetBuilder cellBuilder;

  static const int columns = 3;
  static const double gap = 8;
  static const double minCellHeight = 38;
  static const double maxCellHeight = 48;

  const SeedWordGrid({
    super.key,
    required this.count,
    required this.cellBuilder,
  });

  /// True when [height] holds every row of [count] cells at [minCellHeight]
  /// or more.
  static bool fitsIn(double height, {int count = 24}) =>
      height.isFinite && _cellHeightFor(height, count) >= minCellHeight;

  /// The height at which every row of [count] cells is exactly
  /// [minCellHeight]: the least the grid takes without scrolling.
  static double minHeightFor(int count) {
    final rows = (count + columns - 1) ~/ columns;
    return rows * minCellHeight + gap * (rows - 1);
  }

  static double _cellHeightFor(double height, int count) {
    final rows = (count + columns - 1) ~/ columns;
    return (height - gap * (rows - 1)) / rows;
  }

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = fitsIn(constraints.maxHeight, count: count);
        final cellHeight = fits
            ? math.min(
                _cellHeightFor(constraints.maxHeight, count), maxCellHeight)
            : minCellHeight;
        final cellWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          physics: fits
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: cellWidth / cellHeight,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
          ),
          itemCount: count,
          itemBuilder: cellBuilder,
        );
      },
    );
  }
}

/// One cell's frame: a raised panel with a hairline, the number in a fixed
/// column, [child] beside it. [active] lights the hairline copper (the
/// focused restore field).
class SeedWordCell extends StatelessWidget {
  final int number;
  final Widget child;
  final bool active;

  const SeedWordCell({
    super.key,
    required this.number,
    required this.child,
    this.active = false,
  });

  /// The word's own style: mono, so every glyph is unambiguous to copy down.
  static const TextStyle wordStyle = TextStyle(
    color: Instrument.readout,
    fontSize: 12.5,
    fontFamily: kMono,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Instrument.void2,
          borderRadius: BorderRadius.zero,
          border: Border.all(
              color: active ? Instrument.signal : Instrument.line, width: 1),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text('$number',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Instrument.faint,
                      fontSize: 9.5,
                      fontFamily: kMono)),
            ),
            Expanded(child: child),
          ],
        ),
      );
}

/// A word shown whole in its cell: a long word (eight letters, a large
/// system text size, a narrow phone) scales down rather than ending in an
/// ellipsis, since what is on screen is what a holder writes down.
class SeedWord extends StatelessWidget {
  final String word;
  const SeedWord(this.word, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(word, maxLines: 1, style: SeedWordCell.wordStyle),
        ),
      );
}
