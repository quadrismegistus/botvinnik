// Which personas reach a picker at all — the step before every other roster
// test, and the one nothing covered.
//
// ChessGPT shipped complete and UNREACHABLE: three published nets, an engine
// that played them, a move path in GameController, a native test proving all
// of it, and no way to choose one in the app. Two independent reasons, and
// neither had a test:
//
//   * BotApi.personas() hardcoded `availablePersonas(false)` — the WEB roster,
//     which drops every `nativeOnly` family. Right while Dala (native-only and
//     unimplemented) was the only such family; wrong the moment a native-only
//     family was implemented.
//   * The pickers filter by FAMILY, and nothing added 'chessgpt'.
//
// The picker tests could not have caught either: they inject a FakeBot with a
// fixed roster, so they never exercise the call that drops the personas. These
// assert on the seam itself.
//
//   cd flutter && flutter test test/roster_filter_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/chessgpt_engine.dart';
import 'package:botvinnik_mobile/engine/playable_families.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/game_harness.dart';

Persona _p(String id, String family, {int elo = 1200}) => Persona({
      'id': id,
      'name': id,
      'elo': elo,
      'family': family,
      'blurb': '',
    });

Future<GameController> _game(Map<String, Persona> roster) async {
  final settings = await loadSettings();
  final game = GameController(
      FakeArbiter(), FakeBot(roster), FakeGrading(), settings);
  addTearDown(game.dispose);
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugPlayableFamilies = null;
    FakeBot.lastNativeRequest = null;
  });

  test('the roster is requested for THIS runtime, not always the web one',
      () async {
    // The whole bug in one assertion. `availablePersonas(false)` returns the
    // web roster on every platform, so a native-only family is unreachable
    // even where it runs — and because the pickers are tested against a fake
    // roster, everything downstream stays green while the app offers nothing.
    final game = await _game({'squarefish-1200': _p('squarefish-1200', 'squarefish')});
    game.rosterPersonas; // ignore: unnecessary_statements — the call is the test

    expect(FakeBot.lastNativeRequest, isNotNull,
        reason: 'personas() was never called');
    expect(FakeBot.lastNativeRequest, wantsNativeRoster,
        reason: 'a constant here makes native-only families unreachable '
            'wherever it disagrees with the runtime');
  });

  test('wantsNativeRoster tracks whether a native-only family can actually run',
      () {
    // Not `Platform.isMacOS`: the flag should mean "there is a native-only
    // family worth asking for", so that asking is never a wider door than the
    // filter behind it.
    expect(wantsNativeRoster, ChessGptEngine.supported);
  });

  group('a family this runtime cannot play never reaches a picker', () {
    test('dala is dropped even though the brain offers it', () async {
      // Dala is `nativeOnly` AND unimplemented — it wants an lc0 sidecar
      // nobody built (#45). Asking for the native roster brings it back, so
      // the family filter is what keeps it out. Without this, three personas
      // appear in the New Game sheet that quietly play as a Stockfish
      // stand-in under Dala's name, which is the substitution the picker
      // exists to prevent (#117).
      debugPlayableFamilies = {'squarefish', 'chessgpt'};
      final game = await _game({
        'squarefish-1200': _p('squarefish-1200', 'squarefish'),
        'dala-900': _p('dala-900', 'dala'),
        'chessgpt-lichess': _p('chessgpt-lichess', 'chessgpt'),
      });

      final ids = game.rosterPersonas.map((p) => p.id).toList();
      expect(ids, contains('squarefish-1200'));
      expect(ids, contains('chessgpt-lichess'));
      expect(ids, isNot(contains('dala-900')));
    });

    test('and chessgpt is dropped where ORT does not run', () async {
      // The mirror image, and the reason the filter is per-family rather than
      // one native boolean: on a platform without the runtime, ChessGPT is in
      // exactly Dala's position.
      debugPlayableFamilies = {'squarefish'};
      final game = await _game({
        'squarefish-1200': _p('squarefish-1200', 'squarefish'),
        'chessgpt-lichess': _p('chessgpt-lichess', 'chessgpt'),
      });

      expect(game.rosterPersonas.map((p) => p.id), ['squarefish-1200']);
    });
  });
}
