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

  group('the whitelist is built from capabilities, not from this host', () {
    // CI is ubuntu-latest, where every `supported` getter is false. A test
    // phrased against those getters cannot tell a correct whitelist from one
    // with a family deleted — both answer the same on Linux — so the previous
    // version of this file passed on CI with the bug it exists to catch.
    // familiesFor takes the capabilities as arguments, which makes the claim
    // checkable on any machine.
    test('ORT brings both onnxruntime families and nothing else', () {
      final with_ = familiesFor(ort: true, retro: false, garbo: false, process: false);
      final without =
          familiesFor(ort: false, retro: false, garbo: false, process: false);
      expect(with_.difference(without), {'maia', 'chessgpt'});
      expect(without, isNot(contains('chessgpt')),
          reason: 'deleting the chessgpt clause is the whole bug, restored');
    });

    test('the always-on families never depend on a capability', () {
      final none =
          familiesFor(ort: false, retro: false, garbo: false, process: false);
      expect(none, {'squarefish', 'stockfish', 'horizon'});
    });

    test('a process engine brings custom and its styled siblings', () {
      final p = familiesFor(ort: false, retro: false, garbo: false, process: true)
          .difference(
              familiesFor(ort: false, retro: false, garbo: false, process: false));
      expect(p, {'custom', 'rodent', 'brainlearn'});
    });

    test('the real whitelist is that function, applied to this platform', () {
      // Ties the pure function to what actually ships, so the two cannot
      // drift. Host-independent: both sides move together.
      debugPlayableFamilies = null;
      expect(
          playableFamilies,
          familiesFor(
            ort: ChessGptEngine.supported,
            retro: playableFamilies.contains('retro'),
            garbo: playableFamilies.contains('garbo'),
            process: playableFamilies.contains('custom'),
          ));
    });
  });

  group('the roster is requested for the runtime, not always the web one', () {
    // The whole bug in two assertions. `availablePersonas(false)` returns the
    // web roster on every platform, so a native-only family is unreachable
    // even where it runs — and because the pickers are tested against a fake
    // roster, everything downstream stays green while the app offers nothing.
    //
    // Driven through debugPlayableFamilies rather than through the platform,
    // because wantsNativeRoster now derives from the same set. That is what
    // makes these two die on Linux, where the old assertion could not.
    test('asks for the native roster when a native-only family is playable',
        () async {
      debugPlayableFamilies = {'squarefish', 'chessgpt'};
      final game =
          await _game({'squarefish-1200': _p('squarefish-1200', 'squarefish')});
      game.rosterPersonas;

      expect(FakeBot.lastNativeRequest, isTrue,
          reason: 'a hardcoded false here makes ChessGPT unreachable');
    });

    test('and does not when none is', () async {
      // Asking for personas we would only filter out again is a wider door
      // than it needs to be.
      debugPlayableFamilies = {'squarefish'};
      final game =
          await _game({'squarefish-1200': _p('squarefish-1200', 'squarefish')});
      game.rosterPersonas;

      expect(FakeBot.lastNativeRequest, isFalse);
    });
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
