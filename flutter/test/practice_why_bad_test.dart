// #215: "why the move was bad". A failed attempt keeps the opponent's whole
// punishing line (not just its first move) so the drill can PLAY the cost, and
// derives a plain-language punishment — mate, or the piece it wins — in Dart
// from the position after your move. Pure-Dart testable with a scripted arbiter.
//
//   cd flutter && flutter test test/practice_why_bad_test.dart

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/game_harness.dart' show FakeArbiter;
import 'support/practice_harness.dart';

// The item's own fen is nominal here — checkAttempt takes the after-your-move
// fen as an argument, and that (not the puzzle fen) is what the refutation and
// the punishment are read from. So each test hands in the position it wants.
const _puzzleFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

// Black to move; the White rook on h1 hangs to Qxh1 (Ka1 keeps White off the
// h4-e1 diagonal, so the side-not-to-move isn't in check — a legal position).
const _hangRook = '4k3/8/8/8/7q/8/8/K6R b - - 0 1';

// Black to move; Re1 is back-rank mate (Kg1 boxed in by its own f2/g2/h2 pawns).
const _backRankMate = '4r1k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1';

EngineMove _line(List<String> pv) =>
    EngineMove(pv: pv, score: 5, mate: null, depth: 12, multipv: 1);

String _after(String fen, String uci) => Chess.fromSetup(Setup.parseFen(fen))
    .playUnchecked(NormalMove.fromUci(uci))
    .fen;

/// Drive a NON-best move to a (failed) verdict: FakeGrading scores every reply
/// at 0 win chance, so any non-best move loses the item's whole wcBest and fails.
Future<void> _playBadMove(
    PracticeController practice, String fenAfter) async {
  // 'a2a3' != the item's stored best ('d2d4'), so checkAttempt takes the search
  // branch and grades against the scripted refutation.
  await practice.checkAttempt('a2a3', 'a3', fenAfter);
}

void main() {
  test('a failed attempt keeps the whole refutation line, not just move one',
      () async {
    final arbiter = FakeArbiter(searchLines: [_line(['h4h1', 'a1a2'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _playBadMove(h.practice, _hangRook);

    final att = h.practice.attempt!;
    expect(att.pass, isFalse);
    expect(att.refutationUci, 'h4h1');
    expect(att.refutationPv, ['h4h1', 'a1a2'],
        reason: 'the drill needs the full line to play it, not just move one');
  });

  test('the punishment names the piece the refutation wins', () async {
    final arbiter = FakeArbiter(searchLines: [_line(['h4h1'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _playBadMove(h.practice, _hangRook);

    expect(h.practice.attempt!.punishment, contains('rook'));
  });

  test('the punishment calls a mating refutation checkmate', () async {
    final arbiter = FakeArbiter(searchLines: [_line(['e8e1'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _playBadMove(h.practice, _backRankMate);

    expect(h.practice.attempt!.punishment, contains('checkmate'));
  });

  test('a subtler refutation (no mate, no capture) leaves punishment null',
      () async {
    // A quiet developing reply from the after-move position: nothing captured,
    // no mate — the win-chance drop carries it, punishment stays null.
    final arbiter = FakeArbiter(searchLines: [_line(['b8c6'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _playBadMove(h.practice, _after(_puzzleFen, 'd1h5'));

    expect(h.practice.attempt!.punishment, isNull);
  });

  test('the preview walks the punishment line ply by ply, then stops', () async {
    final arbiter = FakeArbiter(searchLines: [_line(['h4h1', 'a1a2'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();
    await _playBadMove(h.practice, _hangRook);

    h.practice.startRefutationPreview();
    expect(h.practice.refutePreviewing, isTrue);
    expect(h.practice.refutePreviewFen, _hangRook,
        reason: 'ply 0 is the after-your-move position, before any punishment');

    h.practice.stepRefutationPreview();
    expect(h.practice.refutePreviewFen, _after(_hangRook, 'h4h1'));

    h.practice.stepRefutationPreview();
    expect(h.practice.refutePreviewFen,
        _after(_after(_hangRook, 'h4h1'), 'a1a2'));

    // One past the end: the preview ends and the board returns to the attempt.
    h.practice.stepRefutationPreview();
    expect(h.practice.refutePreviewing, isFalse);
    expect(h.practice.refutePreviewFen, isNull);
  });

  test('serving the next puzzle cancels a running preview', () async {
    final arbiter = FakeArbiter(searchLines: [_line(['h4h1'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();
    await _playBadMove(h.practice, _hangRook);

    h.practice.startRefutationPreview();
    expect(h.practice.refutePreviewing, isTrue);

    h.practice.nextPuzzle();
    expect(h.practice.refutePreviewing, isFalse);
    expect(h.practice.refutePreviewFen, isNull);
  });

  test('retry cancels a running preview', () async {
    final arbiter = FakeArbiter(searchLines: [_line(['h4h1'])]);
    final item = practiceItem(_puzzleFen, bestUci: 'd2d4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();
    await _playBadMove(h.practice, _hangRook);

    h.practice.startRefutationPreview();
    h.practice.retry();
    expect(h.practice.refutePreviewing, isFalse);
    expect(h.practice.attempt, isNull);
  });
}
