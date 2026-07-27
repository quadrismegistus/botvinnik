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
import 'package:botvinnik_mobile/engine/custom_engine_runner.dart';
import 'package:botvinnik_mobile/engine/garbo_engine.dart';
import 'package:botvinnik_mobile/engine/maia_engine.dart';
import 'package:botvinnik_mobile/engine/retro_engine.dart';
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
    const off = <String, bool>{
      'maia': false,
      'chessgpt': false,
      'retro': false,
      'garbo': false,
      'process': false,
    };
    Set<String> only(String capability) => familiesFor(
          maia: capability == 'maia',
          chessgpt: capability == 'chessgpt',
          retro: capability == 'retro',
          garbo: capability == 'garbo',
          process: capability == 'process',
        );
    final none = familiesFor(
      maia: off['maia']!,
      chessgpt: off['chessgpt']!,
      retro: off['retro']!,
      garbo: off['garbo']!,
      process: off['process']!,
    );

    test('the always-on families never depend on a capability', () {
      expect(none, {'squarefish', 'stockfish', 'horizon'});
    });

    // One case per capability, and every family in the map appears in exactly
    // one of them. Without the retro and garbo rows, DELETING either family
    // from `_familyNeeds` was caught by nothing in either language — the Dart
    // suite stayed green and so did brain/familyParity.test.ts, while the
    // family vanished from both pickers on the platforms that can play it.
    for (final (capability, families) in [
      ('maia', {'maia'}),
      ('chessgpt', {'chessgpt'}),
      ('retro', {'retro'}),
      ('garbo', {'garbo'}),
      ('process', {'custom', 'rodent', 'brainlearn'}),
    ]) {
      test('$capability brings exactly $families', () {
        expect(only(capability).difference(none), families);
      });
    }

    test('every family the app knows is reachable by some capability', () {
      // The other direction, so a family added to the map with a capability
      // name nothing supplies — a typo, or a key renamed on one side — is not
      // silently unplayable everywhere.
      final all = familiesFor(
          maia: true, chessgpt: true, retro: true, garbo: true, process: true);
      expect(all.length, greaterThan(none.length));
      expect(
          all,
          {
            'squarefish', 'stockfish', 'horizon', 'maia', 'chessgpt',
            'retro', 'garbo', 'custom', 'rodent', 'brainlearn',
          },
          reason: 'a family here that no capability turns on can never be '
              'played, and nothing else would say so');
    });

    test('Maia and ChessGPT are INDEPENDENT capabilities', () {
      // They are the same onnxruntime on native, which is why they were one
      // `ort` flag — and that cost Maia the entire web build. On the web
      // MaiaEngine.supported is true (a wasm worker) while
      // ChessGptEngine.supported is hardcoded false, so `ort: maia && chessgpt`
      // was false and BOTH families dropped out of every picker on
      // botvinnik.app. Neither the macOS suite (both true) nor CI's Linux
      // (both false) could see it.
      expect(familiesFor(
              maia: true,
              chessgpt: false,
              retro: false,
              garbo: false,
              process: false),
          contains('maia'));
      expect(familiesFor(
              maia: false,
              chessgpt: true,
              retro: false,
              garbo: false,
              process: false),
          contains('chessgpt'));
    });

    test('the real whitelist is that function, applied to this platform', () {
      // Ties the pure function to what actually ships, so the two cannot
      // drift. Every argument is read from the ENGINE, not from the value
      // under test: three of the five used to be `playableFamilies.contains(…)`,
      // which made those legs tautologies. Hardcoding retro/garbo/process to
      // false in playable_families.dart then left all 812 tests green on
      // macOS, where that mutation deletes Garbo and every user-added engine
      // from the roster sheet.
      debugPlayableFamilies = null;
      expect(
          playableFamilies,
          familiesFor(
            maia: MaiaEngine.supported,
            chessgpt: ChessGptEngine.supported,
            retro: RetroEngine.supported,
            garbo: GarboEngine.supported,
            process: CustomEngineRunner.supported,
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
