// MovePreview.arrowsFor: the pure guard that decides whether "your move vs the
// best" can be drawn as two arrows. Its reason to exist is the promotion case —
// e7e8q vs e7e8n share from AND to, so two arrows would land on the identical
// line and read as one; there the caller must fall back to a sentence.
//
//   cd flutter && flutter test test/move_preview_test.dart

import 'package:botvinnik_mobile/ui/move_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two distinct moves yield a pair of arrows', () {
    final a = MovePreview.arrowsFor('g1f3', 'd2d4');
    expect(a, isNotNull);
    expect(a!.$1.uci, 'g1f3'); // played
    expect(a.$2.uci, 'd2d4'); // best
  });

  test('a promotion differing only in piece yields no board', () {
    // Same from and to — the whole reason arrowsFor exists.
    expect(MovePreview.arrowsFor('e7e8q', 'e7e8n'), isNull);
  });

  test('a promotion to a different square still draws', () {
    // e7e8q vs e7f8q differ in destination — two real arrows.
    expect(MovePreview.arrowsFor('e7e8q', 'e7f8q'), isNotNull);
  });

  test('a too-short or unparseable uci yields no board', () {
    expect(MovePreview.arrowsFor('e2', 'd2d4'), isNull);
    expect(MovePreview.arrowsFor('d2d4', 'x'), isNull);
  });

  test('castling parses to a single legal king arrow', () {
    final a = MovePreview.arrowsFor('e1g1', 'g1f3');
    expect(a, isNotNull);
    expect(a!.$1.uci, 'e1g1');
  });
}
