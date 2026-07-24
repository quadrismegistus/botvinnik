// The chart's pure decisions: which moves earn a line, and how end labels
// are spread apart without losing their order.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/ui/maia3_pane.dart';

Maia3MoveCurves _curves(List<Map<String, double>> rungs) => Maia3MoveCurves(
      perElo: [
        for (var i = 0; i < rungs.length; i++)
          Maia3RungCurve(600 + i * 100, rungs[i])
      ],
      wdlByElo: const [],
    );

void main() {
  group('pickMoves', () {
    test('orders by peak popularity anywhere on the ladder, capped at 5', () {
      final curves = _curves([
        {'e4': 0.5, 'd4': 0.3, 'Nf3': 0.1, 'c4': 0.05, 'g3': 0.03, 'b3': 0.02},
        // Nf3 peaks late — its PEAK (0.6) should outrank d4's (0.3)
        {'e4': 0.3, 'd4': 0.1, 'Nf3': 0.6, 'c4': 0.0, 'g3': 0.0, 'b3': 0.0},
      ]);
      final picked = Maia3ChartPainter.pickMoves(curves);
      expect(picked.length, 5);
      expect(picked.sublist(0, 3), ['Nf3', 'e4', 'd4']);
      expect(picked, isNot(contains('b3')));
    });

    test('fewer legal moves than the cap is fine', () {
      final picked = Maia3ChartPainter.pickMoves(_curves([
        {'Kxh2': 1.0}
      ]));
      expect(picked, ['Kxh2']);
    });

    test('forceInclude is a no-op when the move is already picked', () {
      final curves = _curves([
        {'e4': 0.5, 'd4': 0.3, 'Nf3': 0.1, 'c4': 0.05, 'g3': 0.03},
      ]);
      expect(Maia3ChartPainter.pickMoves(curves, forceInclude: 'd4'),
          Maia3ChartPainter.pickMoves(curves));
    });

    test('forceInclude bumps the weakest pick to make room', () {
      final curves = _curves([
        {'e4': 0.5, 'd4': 0.3, 'Nf3': 0.1, 'c4': 0.05, 'g3': 0.03, 'b3': 0.02},
      ]);
      final picked = Maia3ChartPainter.pickMoves(curves, forceInclude: 'b3');
      expect(picked.length, 5);
      expect(picked, contains('b3'));
      expect(picked, isNot(contains('g3')), reason: 'weakest pick bumped');
    });

    test('forceInclude of an illegal move is dropped, not fabricated', () {
      final curves = _curves([
        {'e4': 0.5, 'd4': 0.3},
      ]);
      final picked = Maia3ChartPainter.pickMoves(curves, forceInclude: 'Qxh7#');
      expect(picked, isNot(contains('Qxh7#')));
    });
  });

  group('eloAtX', () {
    test('snaps to the nearest rung across the plot width', () {
      final curves = _curves([
        {'e4': 1.0},
        {'e4': 1.0},
        {'e4': 1.0},
      ]);
      // rungs at 600/700/800; gutters are 26 left, 46 right (see the
      // module-level constants) — pick a size wide enough to matter.
      const size = Size(200, 160);
      expect(Maia3ChartPainter.eloAtX(curves, size, 26), 600);
      expect(Maia3ChartPainter.eloAtX(curves, size, 200 - 46), 800);
      expect(Maia3ChartPainter.eloAtX(curves, size, (200 - 26 - 46) / 2 + 26),
          700);
    });

    test('null with no rungs or a zero-width plot', () {
      expect(
          Maia3ChartPainter.eloAtX(_curves([]), const Size(200, 160), 100),
          isNull);
      expect(
          Maia3ChartPainter.eloAtX(
              _curves([
                {'e4': 1.0}
              ]),
              const Size(10, 160),
              5),
          isNull);
    });
  });

  group('spreadLabels', () {
    test('separates a cluster to the minimum gap, preserving order', () {
      final ys = Maia3ChartPainter.spreadLabels([50, 51, 52], 12, 0, 200);
      expect(ys[1] - ys[0], greaterThanOrEqualTo(12));
      expect(ys[2] - ys[1], greaterThanOrEqualTo(12));
      expect(ys, orderedEquals(List.of(ys)..sort()));
    });

    test('a cluster at the bottom is pushed back inside the range', () {
      final ys = Maia3ChartPainter.spreadLabels([195, 196, 197], 12, 0, 200);
      expect(ys.last, lessThanOrEqualTo(200));
      expect(ys.first, greaterThanOrEqualTo(0));
      expect(ys[1] - ys[0], greaterThanOrEqualTo(12));
      expect(ys[2] - ys[1], greaterThanOrEqualTo(12));
    });

    test('well-separated labels are untouched', () {
      expect(Maia3ChartPainter.spreadLabels([10, 100, 190], 12, 0, 200),
          [10, 100, 190]);
    });
  });
}
