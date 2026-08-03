// #214: the Practice tab's green button is a LADDER, not a "move on".
//
// The bug: Skip/Next sits one key from Retry, and `n` pressed for `r` threw the
// puzzle away — no answer shown, no record of what the move was, and (for a
// scheduled item) the next sighting weeks away. The rule these tests hold is
// that NOTHING advances until the answer is on screen: the primary escalates
// hint, another hint, show best, and only then means Next.
//
// Pure Dart — the ladder is entirely [PracticeController.primaryAction], which
// is also what the `n` key calls, so this is a test of the key as much as of
// the button.
//
//   cd flutter && flutter test test/practice_next_guard_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/practice_harness.dart';

const _forkFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pinFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';

/// The position after 1.d4 — where the stored best move of both fixtures
/// lands, so `checkAttempt` can be driven down its no-search branch.
const _afterD4Fen =
    'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1';

/// Two puzzles, one served. TWO on purpose: "it did not advance" is only a
/// claim if there is somewhere to advance to — with a single item the fallback
/// draw in [PracticeController.nextPuzzle] re-serves the same puzzle and a
/// broken guard would look identical to a working one.
({PracticeController practice, FakeBridge bridge, FakeDb db, String served})
    _twoPuzzles() {
  final h = makePractice([
    practiceItem(_forkFen, motifs: ['fork']),
    practiceItem(_pinFen, motifs: ['pin']),
  ]);
  h.practice.startSession();
  return (
    practice: h.practice,
    bridge: h.bridge,
    db: h.db,
    served: h.practice.current!['id'] as String,
  );
}

/// A revealed answer must not survive into the NEXT puzzle (#232's class of
/// bug, reached by a different door). `_serve` resets `revealBest`, and
/// nothing tested it: deleting that line left every test here green while the
/// puzzle after a reveal opened with its own answer already on screen.
///
/// It matters more since #214 than it did before, because revealing is now the
/// third rung of the primary button rather than a buried control — so the
/// state this clears is one most sessions will now enter.
void _revealLeakTests() {
  test('a revealed answer does not follow you to the next puzzle', () {
    final t = _twoPuzzles();
    t.practice.reveal();
    expect(t.practice.revealBest, isTrue, reason: 'precondition');
    expect(t.practice.primaryAction, PracticePrimary.next,
        reason: 'precondition: the ladder is at the top');

    t.practice.doPrimary(); // Next

    expect(t.practice.current!['id'], isNot(t.served),
        reason: 'precondition: it really did advance');
    expect(t.practice.revealBest, isFalse,
        reason: 'the new puzzle opened with its answer showing');
    expect(t.practice.hintTier, 0);
    expect(t.practice.primaryAction, PracticePrimary.hint,
        reason: 'a fresh puzzle starts at the bottom of the ladder');
  });

  test('and neither does a spent hint tier', () {
    // The same leak one rung down: tier 2 draws a circle on the best move's
    // origin square, which is most of the answer on a tactic.
    final t = _twoPuzzles();
    t.practice.hint();
    t.practice.hint();
    expect(t.practice.hintTier, 2, reason: 'precondition');

    t.practice.doPrimary(); // showBest
    t.practice.doPrimary(); // next

    expect(t.practice.current!['id'], isNot(t.served));
    expect(t.practice.hintTier, 0);
    expect(t.practice.revealBest, isFalse);
  });
}

const _failedNf3 = AttemptOutcome(
  san: 'Nf3',
  uci: 'g1f3',
  pass: false,
  drop: 18,
  evalPawns: -1,
  refutationUci: 'b8c6',
  refutationPv: ['b8c6'],
);

void main() {
  group('a served puzzle starts clean', _revealLeakTests);

  group('the primary never advances before the answer (#214)', () {
    test('a fresh puzzle climbs hint, another hint, show best, then Next', () {
      final h = _twoPuzzles();
      final p = h.practice;
      expect(p.items, hasLength(2),
          reason: 'precondition: there IS another puzzle to advance to');
      expect(p.attempt, isNull, reason: 'precondition: unattempted');
      expect(p.solvedOrRevealed, isFalse, reason: 'precondition: no answer up');

      expect(p.primaryAction, PracticePrimary.hint);
      p.doPrimary();
      expect(p.hintTier, 1);
      expect(p.current!['id'], h.served, reason: 'a hint is not a skip');

      expect(p.primaryAction, PracticePrimary.anotherHint);
      p.doPrimary();
      expect(p.hintTier, 2);
      expect(p.current!['id'], h.served);

      expect(p.primaryAction, PracticePrimary.showBest);
      p.doPrimary();
      expect(p.revealBest, isTrue, reason: 'the answer is now on screen');
      expect(p.current!['id'], h.served,
          reason: 'showing the answer is still not a skip');

      // Only now.
      expect(p.primaryAction, PracticePrimary.next);
      p.doPrimary();
      expect(p.current!['id'], isNot(h.served));
    });

    test('a failed attempt goes straight to show best', () {
      // The lower rungs are spent once a move is committed: the motif line
      // tier 1 writes lives in the prompt strip's unattempted branch, which the
      // verdict has replaced, so offering "Hint" here would be a dead press.
      final h = _twoPuzzles();
      final p = h.practice..attempt = _failedNf3;
      expect(p.solvedOrRevealed, isFalse,
          reason: 'precondition: a failure is not an answer');

      expect(p.primaryAction, PracticePrimary.showBest);
      p.doPrimary();
      expect(p.revealBest, isTrue);
      expect(p.current!['id'], h.served,
          reason: 'getting it wrong must not cost you the puzzle unseen');

      expect(p.primaryAction, PracticePrimary.next);
      p.doPrimary();
      expect(p.current!['id'], isNot(h.served));
    });

    test('a pass is an answer, so the primary is Next at once', () {
      final h = _twoPuzzles();
      final p = h.practice
        ..attempt = const AttemptOutcome(
            san: 'Nf3', uci: 'g1f3', pass: true, drop: 2, evalPawns: 0.3);

      expect(p.solvedOrRevealed, isTrue,
          reason: 'a strong move IS the answer, best or not');
      expect(p.primaryAction, PracticePrimary.next);
      p.doPrimary();
      expect(p.current!['id'], isNot(h.served));
    });

    test('Skip is the one thing that leaves a puzzle unanswered', () {
      // The button exists (a puzzle you do not want to work on now is a real
      // thing), it is just a deliberate tap with no key on it. This pins the
      // controller call the Skip button makes.
      final h = _twoPuzzles();
      final p = h.practice;
      expect(p.solvedOrRevealed, isFalse, reason: 'precondition');
      p.nextPuzzle();
      expect(p.current!['id'], isNot(h.served));
      expect(p.revealBest, isFalse, reason: 'and it does not spoil the one it left');
    });
  });

  test('revealing counts as a hint, so the pass after it holds the box',
      () async {
    // reveal() left hintTier at 0, so "show me, then play it" recorded a COLD
    // pass: the brain promotes the Leitner box on `hinted: false`, and the
    // session streak grew. Pre-existing, and #214 makes it reachable in one
    // press of the primary button (or of `n`), which is what tipped it into
    // scope.
    final h = makePractice([practiceItem(_forkFen, bestUci: 'd2d4')]);
    h.practice.startSession();
    expect(h.practice.hintTier, 0, reason: 'precondition: no hint taken yet');

    h.practice.reveal();
    expect(h.practice.hintTier, 3, reason: 'the reveal IS the top of the ladder');

    // The stored best move: checkAttempt's no-search branch, so it commits
    // without an arbiter.
    await h.practice.checkAttempt('d2d4', 'd4', _afterD4Fen);
    expect(h.practice.attempt?.pass, isTrue, reason: 'precondition: it passed');

    final recorded =
        h.bridge.calls.where((c) => c.fn == 'recordResult').toList();
    expect(recorded, hasLength(1));
    expect(recorded.single.args[3], isTrue,
        reason: 'the brain must be told this pass was hinted');
    expect(h.practice.sessionStreak, 0,
        reason: 'a shown answer does not extend a cold streak');
  });

  group('the flows that interact with it', () {
    test('a game session still walks its scope once and ends (#197)', () {
      // The finite walk goes through nextPuzzle, so a guard that stranded it
      // would leave "practise this game's mistakes" unfinishable.
      final h = makePractice([
        practiceItem(_forkFen, motifs: ['fork']),
        practiceItem(_pinFen, motifs: ['pin']),
      ]);
      h.practice.startGameSession({_forkFen: 'a2a3', _pinFen: 'a2a3'});
      expect(h.practice.inGameSession, isTrue, reason: 'precondition');
      final first = h.practice.current!['id'] as String;

      // One left by Skip, one answered through the ladder: both routes step.
      h.practice.nextPuzzle();
      final second = h.practice.current!['id'] as String;
      expect(second, isNot(first));

      h.practice.reveal();
      expect(h.practice.primaryAction, PracticePrimary.next);
      h.practice.doPrimary();

      expect(h.practice.current, isNull);
      expect(h.practice.gameDoneNote, contains('2 mistakes'),
          reason: 'the session ends rather than looping');
    });

    test('a game session that is skipped all the way through still ends', () {
      final h = makePractice([practiceItem(_forkFen), practiceItem(_pinFen)]);
      h.practice.startGameSession({_forkFen: 'a2a3', _pinFen: 'a2a3'});
      h.practice.nextPuzzle();
      h.practice.nextPuzzle();
      expect(h.practice.current, isNull);
      expect(h.practice.gameDoneNote, isNotNull);
    });
  });
}
