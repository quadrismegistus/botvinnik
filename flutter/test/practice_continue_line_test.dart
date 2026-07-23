// #143 part 2: "continue the line". After a PASSED puzzle the player can keep
// playing forward — the engine answers the move they found, the position one
// move later is served as a fresh target, and a one-move puzzle becomes a drill
// of the line it came from.
//
// The orchestration lives entirely in PracticeController.continueLine (two
// depth-bounded searches, dartchess SAN, the same stale-verdict guard
// checkAttempt uses), so it is testable in pure Dart with a scripted arbiter.
//
//   cd flutter && flutter test test/practice_continue_line_test.dart

import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/practice_harness.dart';

// 1.e4 e5, White to move. The puzzle's stored best is 1.Nf3.
const _puzzleFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';

EngineMove _line(String uci, {double score = 0.3, int? mate}) =>
    EngineMove(pv: [uci], score: score, mate: mate, depth: 12, multipv: 1);

/// Returns a canned result per `search` call, in order, so a whole continueLine
/// (reply search, then next-target search) can be driven by `await`. A null
/// entry stands for the engine coming back empty.
class ScriptedArbiter implements SearchArbiter {
  final List<List<EngineMove>?> responses;
  final List<String> fens = [];
  int _i = 0;
  ScriptedArbiter(this.responses);

  int get searches => fens.length;

  @override
  Future<List<EngineMove>?> search({
    required String fen,
    String? ownerFen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) {
    fens.add(fen);
    final r = _i < responses.length ? responses[_i] : null;
    _i++;
    return Future<List<EngineMove>?>.value(r);
  }

  @override
  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      Completer<List<EngineMove>?>().future;
  @override
  void bumpGeneration() {}
  @override
  void cancelAnalyses({required String exceptFen}) {}
  @override
  Object? get engineError => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A search the test resolves by hand — the window continueLine's guard lives
/// in. FIFO: `resolve` completes the oldest still-pending search.
class ManualArbiter implements SearchArbiter {
  final List<Completer<List<EngineMove>?>> _pending = [];
  final List<String> fens = [];
  int get searches => fens.length;

  void resolve(List<EngineMove>? lines) => _pending.removeAt(0).complete(lines);

  @override
  Future<List<EngineMove>?> search({
    required String fen,
    String? ownerFen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) {
    fens.add(fen);
    final c = Completer<List<EngineMove>?>();
    _pending.add(c);
    return c.future;
  }

  @override
  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      Completer<List<EngineMove>?>().future;
  @override
  void bumpGeneration() {}
  @override
  void cancelAnalyses({required String exceptFen}) {}
  @override
  Object? get engineError => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Apply a UCI move to a FEN and return the resulting FEN — the same thing the
/// controller does, so the test asserts against a position rather than a
/// hand-typed FEN string that could drift from dartchess's normalisation.
String _after(String fen, String uci) => Chess.fromSetup(Setup.parseFen(fen))
    .playUnchecked(NormalMove.fromUci(uci))
    .fen;

/// Drive a puzzle to a PASS by playing its stored best move — the best-move
/// branch of checkAttempt needs no search, so it commits synchronously.
Future<void> _passWithBest(
    PracticeController practice, Map<String, dynamic> item) async {
  final best = item['bestUci'] as String;
  await practice.checkAttempt(
      best, item['bestSan'] as String, _after(item['fen'] as String, best));
}

void main() {
  test('continueLine plays the engine reply and serves the next position', () async {
    // reply search -> 1...Nc6 ; target search -> 2.Bc4 for White
    final arbiter = ScriptedArbiter([
      [_line('b8c6')],
      [_line('f1c4', score: 0.5)],
    ]);
    final item = practiceItem(_puzzleFen, bestUci: 'g1f3', bestSan: 'Nf3');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _passWithBest(h.practice, item);
    expect(h.practice.attempt?.pass, isTrue);
    expect(h.practice.lineDepth, 0);
    expect(h.practice.sessionSolved, 1);

    await h.practice.continueLine();

    // The reply was searched from the position after the player's move; the
    // target from the position after the reply.
    final afterMove = _after(_puzzleFen, 'g1f3');
    final afterReply = _after(afterMove, 'b8c6');
    expect(arbiter.fens, [afterMove, afterReply]);

    // The board is now the position one move later, a fresh target on it.
    expect(h.practice.continuing, isFalse);
    expect(h.practice.lineDepth, 1);
    expect(h.practice.attempt, isNull);
    expect(h.practice.current?['fen'], afterReply);
    expect(h.practice.current?['bestUci'], 'f1c4');
    expect(h.practice.current?['bestSan'], 'Bc4');
    expect((h.practice.current?['evalBestPawns'] as num).toDouble(), 0.5);

    // The stored puzzle was recorded once (the original pass); nothing else.
    final recorded = h.bridge.calls.where((c) => c.fn == 'recordResult').toList();
    expect(recorded, hasLength(1));
    expect(recorded.single.args[1], _puzzleFen);
  });

  test('a solved line continuation does not touch the Leitner schedule', () async {
    final arbiter = ScriptedArbiter([
      [_line('b8c6')],
      [_line('f1c4', score: 0.5)],
    ]);
    final item = practiceItem(_puzzleFen, bestUci: 'g1f3', bestSan: 'Nf3');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    await _passWithBest(h.practice, item); // records the stored puzzle (lineDepth 0)
    await h.practice.continueLine(); // now on lineDepth 1
    expect(h.practice.lineDepth, 1);
    expect(h.practice.sessionSolved, 1);

    // Solve the CONTINUED position with its best move. It passes, but being a
    // line continuation it must neither record nor bump session progress.
    final cont = h.practice.current!;
    await _passWithBest(h.practice, cont);
    expect(h.practice.attempt?.pass, isTrue);

    expect(h.practice.sessionSolved, 1,
        reason: 'a line continuation is a drill, not a collected solve');
    expect(h.bridge.calls.where((c) => c.fn == 'recordResult'), hasLength(1),
        reason: 'only the stored puzzle moves a Leitner box');
  });

  test('a mate reached in the line ends the drill with a note', () async {
    // Fool's mate. After 1.f3 e5 the player (White) "passes" by playing 2.g4
    // (the best-move branch grades a stored best as a pass regardless of its
    // real merit), leaving Black to reply — and the scripted reply is 2...Qh4#,
    // which ends the game. There is no next target, so the drill stops with a
    // note instead of a puzzle.
    const puzzleFen =
        'rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq e6 0 2';
    final arbiter = ScriptedArbiter([
      [_line('d8h4', mate: 1)], // Qh4#, a legal Black reply that mates
    ]);
    final item = practiceItem(puzzleFen, bestUci: 'g2g4', bestSan: 'g4');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();
    await _passWithBest(h.practice, item); // _fenAfterAttempt = position after g4

    // Sanity: the scripted reply really does end the game from there.
    final mated = Chess.fromSetup(Setup.parseFen(_after(puzzleFen, 'g2g4')))
        .playUnchecked(NormalMove.fromUci('d8h4'));
    expect(mated.isGameOver, isTrue);

    await h.practice.continueLine();

    expect(h.practice.current, isNull, reason: 'no next target after mate');
    expect(h.practice.continuing, isFalse);
    expect(h.practice.lineDepth, 1);
    expect(h.practice.lineNote, contains('Line over'));
    // Only the single reply search fired — no target search on a finished game.
    expect(arbiter.searches, 1);
  });

  test('a puzzle served mid-continue drops the whole continuation', () async {
    // The stale-verdict guard (#155), extended to the two-search continue flow:
    // Skip/Next inside the reply search must abandon it, not install a target on
    // the freshly served puzzle.
    final arbiter = ManualArbiter();
    final itemA = practiceItem(_puzzleFen, bestUci: 'g1f3', bestSan: 'Nf3');
    const fenB = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final itemB = practiceItem(fenB);
    final h = makePractice([itemA, itemB], arbiter: arbiter);
    h.practice.startSession();
    expect(h.practice.current?['id'], _puzzleFen);

    await _passWithBest(h.practice, itemA);
    expect(h.practice.attempt?.pass, isTrue);

    final fut = h.practice.continueLine();
    expect(h.practice.continuing, isTrue);
    expect(arbiter.searches, 1, reason: 'the reply search is in flight');

    // Skip to another puzzle while the reply search is parked.
    h.practice.nextPuzzle();
    expect(h.practice.current?['id'], fenB);
    expect(h.practice.continuing, isFalse,
        reason: 'serving a new puzzle resets the continue state');
    expect(h.practice.lineDepth, 0);

    // The abandoned reply now resolves — it must land nothing.
    arbiter.resolve([_line('b8c6')]);
    await fut;

    expect(h.practice.current?['id'], fenB,
        reason: 'the freshly served puzzle is untouched');
    expect(h.practice.lineDepth, 0);
    expect(h.practice.continuing, isFalse);
    expect(arbiter.searches, 1,
        reason: 'the target search must never have fired');
  });

  test('continueLine is a no-op after a FAILED attempt', () async {
    // Non-best move -> a search whose eval makes it a loss. FakeGrading.winChance
    // returns 0, so drop = wcBest(60) - 0 = 60 -> fail.
    final arbiter = ScriptedArbiter([
      [_line('c7c5')], // the "refutation" line for the failing check
    ]);
    final item = practiceItem(_puzzleFen, bestUci: 'g1f3', bestSan: 'Nf3');
    final h = makePractice([item], arbiter: arbiter);
    h.practice.startSession();

    // Play a legal NON-best move: 1.a3.
    await h.practice.checkAttempt('a2a3', 'a3', _after(_puzzleFen, 'a2a3'));
    expect(h.practice.attempt?.pass, isFalse);

    final searchesBefore = arbiter.searches;
    await h.practice.continueLine();
    expect(h.practice.continuing, isFalse);
    expect(h.practice.lineDepth, 0);
    expect(arbiter.searches, searchesBefore,
        reason: 'a failed attempt cannot be continued — no search fires');
  });
}
