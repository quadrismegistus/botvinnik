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
import 'package:botvinnik_mobile/stores/settings_store.dart';

/// A SearchArbiter whose searches never resolve, so the grading/analysis tail
/// downstream of a move never runs. Only the synchronous state ops are exercised.
class FakeArbiter implements SearchArbiter {
  @override
  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      Completer<List<EngineMove>?>().future;

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

class FakeBot implements BotApi {
  @override
  List<Persona> personas() => const [];
  @override
  Persona? personaById(String id) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeGrading implements GradingApi {
  @override
  double winChance(double? evalPawns, int? mate) => 0;
  @override
  double whitePovWinChance(String color, double? evalPawns, int? mate) => 50;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A GameController wired to the fakes, in analysis mode (both sides human) so
/// [GameController.playerMove] works for either colour and no engine is needed.
/// [fromFen] starts it on an arbitrary position.
Future<GameController> makeGame({String? fromFen}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await SettingsStore.load();
  settings.setPlayers(white: null, black: null); // analysis: both human
  final game = GameController(FakeArbiter(), FakeBot(), FakeGrading(), settings);
  if (fromFen != null) game.newGame(fromFen: fromFen);
  return game;
}

/// The standard starting position, for asserting a FEN game did NOT fall back
/// to it.
const kStandardStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
