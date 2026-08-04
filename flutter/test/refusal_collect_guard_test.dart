// The #286 refusal-collect guard (_refusalCollected in game_controller.dart):
// one POSITION + one move = one counted occurrence. Both tests began as
// adversarial-review probes that failed against the first (single-slot,
// ply-keyed) guard: alternating refused moves displaced the slot and
// re-counted a retry, and after an undo into a different line the same
// (ply, uci) in a genuinely different position matched the stale slot — so
// the new mistake never reached practice at all. The guard is now a set
// keyed by (fenBefore, uci), the same identity _refusalAttempts uses.
//
//   cd flutter && flutter test test/refusal_collect_guard_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/game_harness.dart';

/// FakeArbiter whose BOT searches answer per-position, so the square bot can
/// reply legally from more than one position. Refusal checks keep the plain
/// childLines refutation.
class RoutedArbiter extends FakeArbiter {
  final Map<String, List<EngineMove>> botReplies;
  final List<EngineMove> defaultReply;
  final List<EngineMove> refusalLines;

  RoutedArbiter({
    required this.botReplies,
    required this.defaultReply,
    required this.refusalLines,
    super.analysisLines,
  });

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
    searchRequests.add((priority: priority, depth: depth, multiPv: multiPv));
    if (priority == SearchPriority.refusalCheck) {
      return Future.value(refusalLines);
    }
    return Future.value(botReplies[fen] ?? defaultReply);
  }
}

/// FakeGrading with a switch: when [good] is set, every graded move is the
/// engine's own first line (in pre-lines, rank 1, zero drop), so it commits
/// without a refusal and without moving the collect slot.
class SwitchableGrading extends FakeGrading {
  bool good = false;
  SwitchableGrading({super.winChanceOf});

  @override
  MoveGrade gradeMove({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required List<EngineMove> preLines,
  }) {
    final base = super.gradeMove(
        ply: ply,
        fenBefore: fenBefore,
        san: san,
        uci: uci,
        color: color,
        preLines: preLines);
    if (!good) return base;
    return MoveGrade({
      ...base.raw,
      'rank': 1,
      'evalPawns': 0.3,
      'isBest': true,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double winChanceOf(double? eval, int? mate) => eval == null ? 20 : 80;

  final childLines = [
    EngineMove(pv: ['h7h5'], score: -0.9, mate: null, depth: 10, multipv: 1),
  ];

  Future<void> settle([int ms = 200]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('alternating refused moves A,B,A — A must count once', () async {
    final settings = await loadSettings(black: kSquareBotId);
    final practice = FakePractice();
    final game = GameController(
        FakeArbiter(analysisLines: kFakeLines, searchLines: childLines),
        FakeBot({kSquareBotId: squareBotPersona}),
        FakeGrading(winChanceOf: winChanceOf),
        settings,
        null,
        practice);
    game.newGame(refuseBlunders: true);

    game.playUci('e2e4'); // refused, collected
    await settle();
    game.playUci('g2g4'); // different mistake, refused, collected
    await settle();
    game.playUci('e2e4'); // the SAME mistake as attempt 1, retried
    await settle();

    expect(game.refusedMoves, 3, reason: 'precondition: all three refused');
    final e4s = practice.collected.where((m) => m['uci'] == 'e2e4').length;
    // Contract under test (the field's own doc): "One ply, one move, one
    // occurrence" — e2e4 at ply 1 was already collected at attempt 1.
    expect(e4s, 1,
        reason: 'observed ${practice.collected.length} collects total; '
            'e2e4 collected $e4s times');
    game.dispose();
  });

  test('same (ply, uci) in a DIFFERENT position — the new mistake '
      'must still reach practice', () async {
    const startFen = kStandardStartFen;
    const afterD4 =
        'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1';
    const afterD4h5c4 =
        'rnbqkbnr/ppppppp1/8/7p/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2';
    const afterE4 =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

    EngineMove reply(String uci) =>
        EngineMove(pv: [uci], score: 0, mate: null, depth: 12, multipv: 1);

    final grading = SwitchableGrading(winChanceOf: winChanceOf);
    final practice = FakePractice();
    final settings = await loadSettings(black: kSquareBotId);
    final game = GameController(
        RoutedArbiter(
          analysisLines: kFakeLines,
          refusalLines: childLines,
          botReplies: {
            afterD4: [reply('h7h5')],
            afterD4h5c4: [reply('g7g6')],
            afterE4: [reply('h7h5')],
          },
          defaultReply: [reply('h7h5')],
        ),
        FakeBot({kSquareBotId: squareBotPersona}),
        grading,
        settings,
        null,
        practice);
    game.newGame(refuseBlunders: true);
    expect(game.position.fen, startFen);

    // Ply 1: a "best" move commits without touching the refusal slot.
    grading.good = true;
    game.playUci('d2d4');
    await settle(2200); // bot opening wait can spin up to 1500ms wall clock
    expect(game.moves.length, 2,
        reason: 'precondition: d4 committed, bot replied');
    final p1 = game.position.fen; // ply-3 position, d4-line

    // Ply 3: the blunder. Refused and collected — slot = (3, g2g4).
    grading.good = false;
    game.playUci('g2g4');
    await settle();
    expect(game.refusedMoves, 1, reason: 'precondition: refused');
    expect(practice.collected.map((m) => m['fenBefore']), contains(p1),
        reason: 'precondition: the d4-line g2g4 was collected');

    // Play something sound instead, let the game move on, then take it all back.
    grading.good = true;
    game.playUci('c2c4');
    await settle(2200);
    expect(game.moves.length, 4,
        reason: 'precondition: c4 committed, bot replied');
    game.undo();
    game.undo();
    expect(game.moves, isEmpty, reason: 'precondition: back to the start');

    // A different first move: a different ply-3 position.
    game.playUci('e2e4');
    await settle(2200);
    expect(game.moves.length, 2,
        reason: 'precondition: e4 committed, bot replied');
    final p2 = game.position.fen;
    expect(p2, isNot(p1), reason: 'precondition: genuinely different position');

    // The same square-for-square blunder in the NEW position: a distinct
    // mistake (distinct fen, distinct practice item) that must be collected.
    grading.good = false;
    game.playUci('g2g4');
    await settle();
    expect(game.refusedMoves, 2,
        reason: 'precondition: the e4-line g2g4 was refused, not committed');
    expect(practice.collected.map((m) => m['fenBefore']), contains(p2),
        reason: 'the e4-line g2g4 is a different position\'s blunder and must '
            'reach practice; fens collected: '
            '${practice.collected.map((m) => m['fenBefore']).toList()}');
    game.dispose();
  });
}
