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
  FakeArbiter({this.analysisLines});

  @override
  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      analysisLines == null
          ? Completer<List<EngineMove>?>().future
          : Future<List<EngineMove>?>.value(analysisLines);

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
  }) =>
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

/// A stand-in persona for tests that need a bot on the board. Only the fields
/// the controller reads before it picks a move matter — it never gets that far
/// in these tests, because the fake arbiter's search never resolves.
const kTestBotId = 'testbot';
const testBotPersona = Persona({
  'id': kTestBotId,
  'name': 'Test Bot',
  'elo': 1500,
  'family': 'square',
  'blurb': '',
});

class FakeBot implements BotApi {
  final Map<String, Persona> byId;
  const FakeBot([this.byId = const {}]);
  @override
  List<Persona> personas() => byId.values.toList(growable: false);
  @override
  Persona? personaById(String id) => byId[id];
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

/// Records what the controller tried to collect as a practice puzzle.
class FakePractice implements PracticeController {
  final List<Map<String, dynamic>> collected = [];

  @override
  Future<void> maybeCollect(Map<String, dynamic> storedMove,
      {String? setupUci, int minDepth = 8}) async {
    collected.add(storedMove);
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
