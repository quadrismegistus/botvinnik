// Practice by motif (#126): the filter the brain has always supported and the
// Dart wrapper used to throw away.
//
//   cd flutter && flutter test test/practice_motif_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/practice_harness.dart';

// Two positions, so the filtered pool is a strict subset of the whole one.
const _forkFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pinFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
const _untaggedFen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';

void main() {
  test('no filter still serves an item, and marshals as undefined not null',
      () {
    final h = makePractice([
      practiceItem(_forkFen, motifs: ['fork']),
      practiceItem(_pinFen, motifs: ['pin']),
    ]);

    h.practice.startSession();

    expect(h.practice.current, isNotNull,
        reason: 'an unfiltered session must serve something');

    // The whole point of the omit sentinel: reconstruct the JavaScript the
    // real host would have run. `undefined` in the motif slot engages the
    // brain's default; a Dart null would come through as the literal `null`,
    // and this is the only layer at which the two can be told apart —
    // measured, the brain's own `if (motif)` gate treats them alike today.
    final call = h.bridge.calls.singleWhere((c) => c.fn == 'nextItem');
    expect(
      brainExprFor(call),
      'JSON.stringify(brain.nextItem(${jsonEncode(h.practice.items)},'
      'null,undefined,undefined,undefined,true) ?? null)',
    );
  });

  test('a motif filter serves only items carrying that motif', () {
    final h = makePractice([
      practiceItem(_forkFen, motifs: ['fork', 'material']),
      practiceItem(_pinFen, motifs: ['pin']),
    ]);

    h.practice.setMotifFilter('pin');
    expect(h.practice.current?['id'], _pinFen);

    // and the string reaches the brain as a string, not as a stray null
    final call = h.bridge.calls.last;
    expect(brainExprFor(call), contains(',undefined,"pin",undefined,true)'));

    h.practice.setMotifFilter('fork');
    expect(h.practice.current?['id'], _forkFen);

    h.practice.setMotifFilter(null);
    expect(h.practice.current, isNotNull,
        reason: 'clearing the filter must serve from everything again');
  });

  test('the picker options come from the player own items, with counts', () {
    final h = makePractice([
      practiceItem(_forkFen, motifs: ['fork', 'material']),
      practiceItem(_pinFen, motifs: ['material']),
      practiceItem(_untaggedFen), // collected before tagging: no motifs
    ]);

    expect(h.practice.motifCounts, {'material': 2, 'fork': 1},
        reason: 'commonest first, and nothing the items do not carry');
  });

  test('an item below the serve threshold contributes no picker option', () {
    final h = makePractice([
      practiceItem(_forkFen, motifs: ['fork']),
      practiceItem(_pinFen, motifs: ['skewer'], drop: 6),
    ]);

    // 6% is collected (the floor is 5) but not served (the default bar is
    // 15), so offering "skewer" would be offering an empty queue.
    expect(h.practice.servable.length, 1);
    expect(h.practice.motifCounts, {'fork': 1});
  });

  test('Next keeps serving when the filter is down to one item', () {
    final h = makePractice([
      practiceItem(_forkFen, motifs: ['fork']),
      practiceItem(_pinFen, motifs: ['pin']),
    ]);

    h.practice.setMotifFilter('fork');
    expect(h.practice.current?['id'], _forkFen);

    h.practice.nextPuzzle();
    expect(h.practice.current?['id'], _forkFen,
        reason: 'excluding the only match must not empty the tab');
  });
}
