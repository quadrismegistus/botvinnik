// A test harness for GameController's state machine — undo, redo, browse,
// newGame-from-FEN — with fake engine dependencies so it runs in pure Dart,
// no browser and no device.
//
// The fakes never return: every search/analysis stays pending, so the async
// grading and analysis tail never runs and the tests see only the synchronous
// state (position, moves, undo/redo, browse). That is exactly the layer where
// the FEN-start, undo, and browse bugs lived — and where a canvas Playwright
// test could assert nothing.

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';
import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';

/// Canned analysis deep enough (depth >= 10) to carry the grading pipeline
/// past its "no usable child" abort.
const kFakeLines = [
  EngineMove(pv: ['d2d4'], score: 0.3, mate: null, depth: 15, multipv: 1),
];

/// A SearchArbiter whose searches never resolve, so the grading/analysis tail
/// downstream of a move never runs. Only the synchronous state ops are exercised.
///
/// Pass [analysisLines] to make `analysis()` COMPLETE instead, which drives the
/// grading pipeline through to the practice-collect guard. `search()` never
/// resolves either way — that keeps a bot turn parked at move-picking rather
/// than running down the unstubbed shapedMove/botSpec path.
class FakeArbiter implements SearchArbiter {
  final List<EngineMove>? analysisLines;

  /// Push [analysisLines] through `onUpdate` as well as returning them, which
  /// fills the controller's `_partials`.
  ///
  /// Off by default because it changes grading inputs (`_partials` is one of
  /// the places `_storedMoveOf` looks for pre/post lines). It exists for tests
  /// that must get PAST the bot turn's opening wait: that loop spins until the
  /// analysis reaches depth 10 *or* 1500ms of `DateTime.now()` elapse — and
  /// `tester.pump` advances fake timers, not the wall clock, so the timeout
  /// never fires under a widget test. Depth-10 partials are the only exit.
  final bool streamPartials;

  /// Make `search()` RESOLVE with these lines instead of hanging forever, after
  /// an optional [searchDelay]. Needed by any test that must watch a bot turn
  /// run to completion — the default never-resolving search parks it at
  /// move-picking, which is what most tests want and this one cannot use.
  ///
  /// The delay is the window a new game can land in, which is the only way to
  /// exercise a turn abandoned mid-flight.
  final List<EngineMove>? searchLines;
  final Duration searchDelay;
  FakeArbiter({
    this.analysisLines,
    this.streamPartials = false,
    this.searchLines,
    this.searchDelay = Duration.zero,
  });

  @override
  Future<List<EngineMove>?> analysis(String fen,
      {void Function(List<EngineMove>)? onUpdate}) {
    final lines = analysisLines;
    if (lines == null) return Completer<List<EngineMove>?>().future;
    if (streamPartials) onUpdate?.call(lines);
    return Future<List<EngineMove>?>.value(lines);
  }

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
    final lines = searchLines;
    if (lines == null) return Completer<List<EngineMove>?>().future;
    return Future<List<EngineMove>?>.delayed(searchDelay, () => lines);
  }

  @override
  void bumpGeneration() {}
  @override
  void cancelAnalyses({required String exceptFen}) {}
  @override
  Object? get engineError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A stand-in persona for tests that need a bot on the board. Only the fields
/// the controller reads before it picks a move matter — it never gets that far
/// in these tests, because the fake arbiter's search never resolves.
const kTestBotId = 'testbot';
const testBotPersona = Persona({
  'id': kTestBotId,
  'name': 'Test Bot',
  'elo': 1500,
  'family': 'squarefish',
  'blurb': '',
});

/// A square persona that genuinely EXERCISES the square branch — it carries a
/// `shapedLabel`, without which `p.shapedLabel!` throws before the branch does
/// anything and the catch-all swallows it. [testBotPersona] deliberately does
/// not, so tests wanting the parked-at-move-picking state keep it.
const kSquareBotId = 'squarebot';
const squareBotPersona = Persona({
  'id': kSquareBotId,
  'name': 'Square Bot',
  'elo': 1500,
  'family': 'squarefish',
  'blurb': '',
  'shapedLabel': 1200,
});

/// A persona whose family has no branch in `_pickBotMove` at all, so a bot turn
/// falls straight through to the Stockfish stand-in. `dala` is the real such
/// family (#45: never implemented), which makes it the honest fixture for the
/// substitution path — no engine has to be stubbed to reach it.
const kFallbackBotId = 'fallbackbot';
const fallbackBotPersona = Persona({
  'id': kFallbackBotId,
  'name': 'Fallback Bot',
  'elo': 1500,
  'family': 'dala',
  'blurb': '',
});

/// A fish persona, which reaches the same final block as [fallbackBotPersona]
/// — but legitimately, because that block IS the fish engine. It is the only
/// family that arrives there having played itself, which makes it the one
/// fixture that can tell a real substitution from the normal case.
/// `numericElo` is display elo + SCALE_OFFSET, as `fish()` builds it.
const kFishBotId = 'fish-1500';
const fishBotPersona = Persona({
  'id': kFishBotId,
  'name': 'Fish 1500',
  'elo': 1500,
  'family': 'stockfish',
  'blurb': '',
  'numericElo': 1740,
});

class FakeBot implements BotApi {
  final Map<String, Persona> byId;
  const FakeBot([this.byId = const {}]);
  @override
  List<Persona> personas() => byId.values.toList(growable: false);
  @override
  Persona? personaById(String id) => byId[id];

  // Enough of the stand-in path to produce a move. `skill` is the simplest of
  // the three botSpec kinds — it searches once and plays the first line, with
  // no sampling or repetition logic to stub.
  @override
  int internalElo(Persona p) => p.elo + 240;

  // Enough of the SQUARE branch to let it run and return, rather than throwing
  // on `p.shapedLabel!` before it reaches its own arbiter call. Without these,
  // a test claiming "square never falls through" proves nothing — square dies
  // upstream and the catch-all swallows it.
  @override
  int shapedSearchDepth(int label) => 8;
  @override
  String? shapedMove({
    required List<EngineMove> lines,
    required int label,
    required String seed,
    required String fen,
    String? lastMoveTo,
  }) =>
      lines.first.uci;
  @override
  String avoidRepetition(
          String uci, List<String> fenHistory, List<EngineMove> lines) =>
      uci;
  @override
  Map<String, dynamic> botSpec(int internalElo) =>
      const {'kind': 'skill', 'depth': 8, 'level': 3};
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeGrading implements GradingApi {
  /// A blunder-shaped grade, so a move that reaches the collect guard is one
  /// practice would want. Only the fields the pipeline and _storedMoveOf read
  /// need to be here.
  @override
  MoveGrade gradeMove({
    required int ply,
    required String fenBefore,
    required String san,
    required String uci,
    required String color,
    required List<EngineMove> preLines,
  }) =>
      MoveGrade({
        'ply': ply,
        'fenBefore': fenBefore,
        'san': san,
        'uci': uci,
        'color': color,
        'depth': 15,
        'isBest': false,
        'label': 'blunder',
        'bestSan': 'd4',
        'bestUci': 'd2d4',
        'bestEval': 0.0,
        'bestPv': const ['d2d4'],
        'backfilled': false,
      });

  @override
  MoveGrade backfillGrade(MoveGrade grade, List<EngineMove> childLines) =>
      MoveGrade({...grade.raw, 'backfilled': true});

  @override
  double winChance(double? evalPawns, int? mate) => 0;
  @override
  double whitePovWinChance(String color, double? evalPawns, int? mate) => 50;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records what the controller tried to collect as a practice puzzle, and
/// reports the same verdict the real controller would: the drop against the
/// real [kCollectMin] floor. It always "adds" (never a duplicate) — the
/// duplicate path is exercised against the real controller in
/// practice_collection_test, not here.
class FakePractice implements PracticeController {
  final List<Map<String, dynamic>> collected = [];

  @override
  Future<CollectOutcome> maybeCollect(Map<String, dynamic> storedMove,
      {String? setupUci, int minDepth = 8}) async {
    collected.add(storedMove);
    final drop = (storedMove['wcDrop'] as num?)?.toDouble() ?? 0;
    final depth = (storedMove['depth'] as num?)?.toInt() ?? 0;
    return (drop < kCollectMin || depth < minDepth)
        ? CollectOutcome.notEligible
        : CollectOutcome.added;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fresh settings with the players assigned. Both null (the default) is
/// analysis mode. Exposed separately from [makeGame] for tests that must
/// control exactly WHEN the controller is built — a controller starts a bot
/// turn in its constructor, and a fake-clock test needs that inside the clock.
Future<SettingsStore> loadSettings({String? white, String? black}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.load();
  settings.setPlayers(white: white, black: black);
  return settings;
}

/// A GameController wired to the fakes, in analysis mode (both sides human) so
/// [GameController.playerMove] works for either colour and no engine is needed.
/// [fromFen] starts it on an arbitrary position.
Future<GameController> makeGame({String? fromFen}) async {
  final settings = await loadSettings(); // both null: analysis
  final game =
      GameController(FakeArbiter(), const FakeBot(), FakeGrading(), settings);
  if (fromFen != null) game.newGame(fromFen: fromFen);
  return game;
}

/// The standard starting position, for asserting a FEN game did NOT fall back
/// to it.
const kStandardStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// The harness's [FakeGrading] answers the whole-game calls out of
/// `noSuchMethod`, i.e. with null, which a non-nullable `labelCounts` rejects
/// — so it cannot reach the end of a save. These two are the difference
/// between a test that archives a game and one that dies in the accountancy.
class SavingGrading extends FakeGrading {
  @override
  double? gameAccuracy(List<Map<String, dynamic>> storedMoves, String color) =>
      null;

  @override
  Map<String, dynamic> labelCounts(
          List<Map<String, dynamic>> storedMoves, String color) =>
      const {'blunder': 0, 'mistake': 0, 'inaccuracy': 0};
}
