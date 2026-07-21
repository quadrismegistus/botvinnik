// The mover-POV to white-POV conversion, which used to be written out twice.
//
// #154 added a black-to-move case for the Book pane's copy. The Lines pane had
// an independent copy of the same expressions, and deleting it left the whole
// suite green — so the two panels, which stack in the wide layout, could have
// printed +1.0 and -1.0 for the same move with nothing to catch it. There is
// one implementation now, and this is the test on it.
//
//   cd flutter && flutter test test/eval_text_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/ui/eval_text.dart';

const _whiteToMove = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _blackToMove = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1';

void main() {
  test('white to move: the brain\'s score passes through', () {
    expect(whitePovEval(score: 1.0, mate: null, blackToMove: false), '+1.0');
    expect(whitePovEval(score: -0.5, mate: null, blackToMove: false), '-0.5');
    expect(whitePovEval(score: 0, mate: 3, blackToMove: false), '#3');
  });

  test('black to move: it flips, so White stays the reference', () {
    // The brain reports from the MOVER's view. A +1.0 for Black is White being
    // a pawn down, and the app prints that as -1.0 everywhere.
    expect(whitePovEval(score: 1.0, mate: null, blackToMove: true), '-1.0');
    expect(whitePovEval(score: -0.5, mate: null, blackToMove: true), '+0.5');
  });

  test('a mate carries its sign across the flip', () {
    // Black mating in 3 is Black winning, which is negative in White's terms —
    // the same convention the score uses, so the two cannot disagree.
    expect(whitePovEval(score: 0, mate: 3, blackToMove: true), '#-3');
    expect(whitePovEval(score: 0, mate: -3, blackToMove: true), '#3');
  });

  test('zero never prints as -0.0', () {
    expect(whitePovEval(score: 0, mate: null, blackToMove: false), '+0.0');
    expect(whitePovEval(score: 0, mate: null, blackToMove: true), '+0.0');
  });

  test('a mate row has no score, and that must not throw', () {
    // The regression that collapsing the two copies introduced: taking `score`
    // as non-null made the caller force-unwrap it BEFORE the mate check, so
    // every mate row threw and took the whole Book table down with it. A mate
    // row genuinely carries no centipawn score.
    expect(whitePovEval(score: null, mate: 3, blackToMove: false), '#3');
    expect(whitePovEval(score: null, mate: 3, blackToMove: true), '#-3');
    expect(whitePovEval(score: null, mate: null, blackToMove: false), '');
  });

  test('fenBlackToMove reads the side-to-move field', () {
    expect(fenBlackToMove(_whiteToMove), isFalse);
    expect(fenBlackToMove(_blackToMove), isTrue);
  });

  test('the EngineMove convenience agrees with the raw form', () {
    const line =
        EngineMove(pv: ['e2e4'], score: 1.0, mate: null, depth: 18, multipv: 1);
    expect(whitePovEvalOf(line, true),
        whitePovEval(score: 1.0, mate: null, blackToMove: true));
    expect(whitePovEvalOf(line, true), '-1.0');
  });
}
