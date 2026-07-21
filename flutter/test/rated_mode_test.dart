// Rated mode (#168): the one kind of game that moves the player's rating.
//
// The decision is "rated = blind, no hints, no takebacks", and the reason it
// is a MODE rather than those three conditions read back off the settings is
// that all four of the relevant switches default to help ON — so inferring it
// rates no game a default install ever plays, and no archived game at all.
// The argument in full is beside the exclusion in `brain/playerElo.ts`.
//
// Three layers, and they are tested separately on purpose:
//
//   the SHEET turns blind on and the overlays off, and asks for a rated game;
//   the CONTROLLER records that choice on the archived record;
//   the BRAIN counts exactly those, which is proved over source in
//     brain/playerElo.test.ts — this file cannot, because the Dart tests run
//     the committed bundle and the rule is not in it until it is rebuilt.
//
// The store group below therefore fakes the bridge: what it asserts is the
// PROSE for a refused game, which is display-only by the store's own account,
// and never which games get refused.
//
//   cd flutter && flutter test test/rated_mode_test.dart

import 'dart:async';
import 'dart:io' as io;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/rating_api.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/player_rating_store.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/new_game_sheet.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// Black king boxed in by its own pawns, White rook on a1: 1.Ra8 is mate, and
/// 1.Ra7 is a legal quiet move from the same position. The same fixture
/// game_help_test uses, and for the same reason — the game ends on the HUMAN's
/// move, so no bot reply is due and nothing parks in `botThinking`.
const _mateIn1 = '6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1';

void _mate(GameController g) =>
    g.playerMove(NormalMove.fromUci('a1a8'), 'Ra8#');

/// An arbiter whose analysis RESOLVES EMPTY, so the grade pipeline aborts at
/// "no pre-lines" and the save's grade wait is over immediately.
FakeArbiter _noLines() => FakeArbiter(analysisLines: const []);

Future<(GameController, SettingsStore, FakeDb)> _botGame() async {
  final settings = await loadSettings(black: kTestBotId);
  final db = FakeDb();
  final game = GameController(_noLines(), const FakeBot({kTestBotId: testBotPersona}),
      SavingGrading(), settings, db);
  return (game, settings, db);
}

/// The settings a rated game starts under, as the sheet leaves them.
void _asRated(SettingsStore s) {
  s.blind = true;
  s.showArrows = false;
  s.showThreats = false;
  s.showControl = false;
}

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    // `as io`: dartchess exports its own File (the a-h kind).
    final f = io.File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// A bridge that answers every fit with the SAME estimate, so the store's
/// "did the newest game count?" comparison — current.games == previous.games
/// + 1 — can never be satisfied and every game comes back refused.
///
/// That is the point: this group is about the SENTENCE, not the rule. Which
/// games are refused is `estimatePlayerElo`'s call and is asserted against the
/// real bundle in player_rating_test.dart and over source in
/// brain/playerElo.test.ts.
class _AlwaysRefusingBridge implements JsBridge {
  @override
  dynamic call(String fn,
          {List<Object?> args = const [], bool isProperty = false}) =>
      const {'elo': 1200, 'se': 150, 'games': 4};

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<PlayerRatingStore> _storeOver(Map<String, dynamic> newest) async {
  final db = FakeDb([newest]);
  final store = PlayerRatingStore(db, RatingApi(_AlwaysRefusingBridge()));
  await store.refresh();
  return store;
}

Map<String, dynamic> _record({
  bool? rated = true,
  bool hints = false,
  int undos = 0,
  String? persona = 'squarefish-1200',
  String result = '1-0',
}) =>
    {
      'id': 'g-1',
      'endedAt': '2026-07-21T10:00:00.000',
      'result': result,
      'botElo': 1440,
      'botPersona': ?persona,
      if (persona != null) 'botHintsUsed': hints,
      if (rated == true) 'rated': true,
      if (undos > 0) 'botUndos': undos,
      'botColor': persona == null ? null : 'b',
      'moveCount': 2,
      'labelCounts': {'w': {}, 'b': {}},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  group('the controller records the choice', () {
    test('a rated game archives rated:true; a casual one omits it', () async {
      final (g, s, db) = await _botGame();
      _asRated(s);
      g.newGame(fromFen: _mateIn1, rated: true);
      _mate(g);
      await pumpEventQueue();

      final rec = db.saved.single;
      expect(rec['rated'], isTrue);
      expect(rec['botHintsUsed'], isFalse,
          reason: 'blind is on, so nothing was on the board');

      final (g2, _, db2) = await _botGame();
      g2.newGame(fromFen: _mateIn1); // the default: not rated
      _mate(g2);
      await pumpEventQueue();
      expect(db2.saved.single.containsKey('rated'), isFalse,
          reason: 'playerElo gates on `rated !== true`, so absence is false '
              'and every pre-#168 record already says it');
    });

    test('help taken in a rated game is recorded alongside the intent',
        () async {
      // The deliberate half of the design. Turning an overlay back on does NOT
      // silently un-rate the game: the record says both true things — the
      // player meant to be on the record, and then took help — and the brain
      // refuses it on `botHintsUsed`. Un-rating here would lose the fact that
      // they had opted in, and would make the two flags disagree about the
      // same game.
      final (g, s, db) = await _botGame();
      _asRated(s);
      g.newGame(fromFen: _mateIn1, rated: true);
      // Both halves, because either alone puts nothing on the board:
      // _hintsOnBoard is `!blind && (arrows || threats || control)`, and the
      // rated mode turned all four the other way.
      s.blind = false;
      s.showArrows = true;
      _mate(g);
      await pumpEventQueue();

      final rec = db.saved.single;
      expect(rec['rated'], isTrue, reason: 'the intent stands');
      expect(rec['botHintsUsed'], isTrue, reason: 'and so does what happened');
    });

    test('a takeback needs no rated machinery of its own', () async {
      // The simpler answer was already true: botUndos > 0 has excluded a game
      // since the rating shipped, and it excludes a rated one the same way. So
      // "no takebacks" costs no code here — only the assertion that a rated
      // game still counts them.
      final (g, s, db) = await _botGame();
      _asRated(s);
      g.newGame(fromFen: _mateIn1, rated: true);
      _mate(g);
      g.undo();
      _mate(g);
      await pumpEventQueue();

      final rec = db.saved.last;
      expect(rec['rated'], isTrue);
      expect(rec['botUndos'], 1);
    });

    test('a new game clears it, including the one an opponent change forces',
        () async {
      final (g, s, _) = await _botGame();
      g.newGame(rated: true);
      expect(g.rated, isTrue);
      g.newGame();
      expect(g.rated, isFalse, reason: 'the default is a casual game');

      g.newGame(rated: true);
      // The controller listens to the settings and restarts on an opponent
      // change. That restart is a different game against a different bot and
      // must not inherit the record.
      //
      // This is the FIRST such change on this controller, which is the case
      // that was broken: `_lastSettingsSig` was a `late` field, so the
      // comparison in _onSettings initialised it from the settings as they
      // already were and found nothing had changed. Measured before the fix —
      // moves survived a swapped opponent, and `rated` with them. A test that
      // changed the opponent twice would have passed against that.
      s.setPlayers(white: null, black: kSquareBotId);
      expect(g.rated, isFalse);
    });

    testWidgets('a casual game started during the grade wait cannot un-rate '
        'the game being archived', (tester) async {
      // The #117 shape, for the third time. The save snapshots the finished
      // game and then waits up to 16s for in-flight grading, and what a player
      // does after a checkmate is start the next game. Reading `_rated` live
      // below the wait would archive the fresh casual game's flag against the
      // finished rated game's result — and the failure is silent: the rating
      // simply never moves, for a game the player played blind on purpose.
      final settings = await loadSettings(black: kTestBotId);
      _asRated(settings);
      final db = FakeDb();
      final g = GameController(
          FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
          const FakeBot({kTestBotId: testBotPersona}),
          SavingGrading(),
          settings,
          db,
          _ParkingPractice());
      g.newGame(fromFen: _mateIn1, rated: true);

      _mate(g);
      expect(db.saved, isEmpty, reason: 'the save must still be in the wait');

      g.newGame(); // the next game, casual, while the old one is being written
      expect(g.rated, isFalse, reason: 'the LIVE flag is the new game now');

      await tester.pump(const Duration(seconds: kSaveGradeWaitSeconds + 1));

      final rec = db.saved.single;
      expect(rec['result'], '1-0');
      expect(rec['rated'], isTrue,
          reason: 'reading the live flag here would archive the fresh casual '
              'game against the finished rated game\'s result');

      settings.setPlayers(white: null, black: null);
      g.newGame();
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('the New Game sheet is where a rated game starts', () {
    Future<(GameController, SettingsStore)> pumpSheet(WidgetTester tester,
        {String? white,
        String? black = kTestBotId,
        double width = 375,
        FakeArbiter? arbiter}) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final settings = await loadSettings(white: white, black: black);
      final game = GameController(arbiter ?? _noLines(),
          const FakeBot({kTestBotId: testBotPersona}), FakeGrading(), settings);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<GameController>.value(value: game),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNewGameSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (game, settings);
    }

    testWidgets('ticking it lands the game blind with the overlays off',
        (tester) async {
      final (game, settings) = await pumpSheet(tester);
      expect(settings.blind, isFalse,
          reason: 'the shipped defaults: every hint on, blind off — which is '
              'why the rule cannot be inferred from them');
      expect(settings.showArrows, isTrue);

      await tester.tap(find.text('Rated game'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(settings.blind, isTrue);
      expect(settings.showArrows, isFalse);
      expect(settings.showThreats, isFalse);
      expect(settings.showControl, isFalse);
      expect(game.rated, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starting without ticking it changes nothing', (tester) async {
      final (game, settings) = await pumpSheet(tester);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(game.rated, isFalse);
      expect(settings.blind, isFalse, reason: 'a casual game is the default '
          'and must not quietly take the board away');
      expect(settings.showArrows, isTrue);
    });

    // Analysis has no result to rate and bot-vs-bot has no human in it. The
    // brain refuses both anyway, so offering the tick here would be a promise
    // the archive does not keep. One test each rather than two sheets in one:
    // the first modal is still up when the second would open, and the tap that
    // opens it silently misses.
    testWidgets('it is not offered on the analysis board', (tester) async {
      await pumpSheet(tester, black: null);
      expect(find.text('You', skipOffstage: false), findsNWidgets(2),
          reason: 'both sides are the human — the sheet under test');
      expect(find.text('Rated game'), findsNothing);
    });

    testWidgets('it is not offered for bot vs bot', (tester) async {
      // White is a bot, so the controller starts a turn in its constructor.
      // Streamed depth-15 partials are the only way out of that turn's opening
      // wait under a widget test — the wait's other exit is 1500ms of
      // DateTime.now(), and pump advances fake timers, not the wall clock. The
      // turn then parks in the never-resolving search, leaving no timer behind
      // for the binding to fail on.
      await pumpSheet(tester,
          white: kTestBotId,
          black: kTestBotId,
          arbiter:
              FakeArbiter(analysisLines: kFakeLines, streamPartials: true));
      expect(find.text('Rated game'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    for (final width in [375.0, 320.0]) {
      testWidgets('the sheet does not overflow at ${width.toInt()}px',
          (tester) async {
        // A RenderFlex overflow is a runtime error the analyzer and a green
        // suite both miss, and the rated row is two lines of prose beside a
        // checkbox. Roboto is loaded in setUpAll because the default test font
        // is Ahem, whose uniform square glyphs measure nothing a player sees.
        await pumpSheet(tester, width: width);
        expect(find.text('Rated game'), findsOneWidget,
            reason: 'the row must be on screen, or this proves nothing');
        await tester.tap(find.text('Rated game'));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'the sheet overflowed at ${width.toInt()}px');
      });
    }
  });

  group('the rating card says why a game did not count', () {
    test('a casual game is refused as one', () async {
      final store = await _storeOver(_record(rated: null));
      expect(store.lastGameRefused, isTrue);
      expect(store.refusedReason, 'it was not a rated game');
    });

    test('and that reason comes before what the player did in it', () async {
      // "You took a move back" about a casual game implies it would have
      // counted otherwise, which since #168 is false of every casual game.
      final store = await _storeOver(_record(rated: null, undos: 2));
      expect(store.refusedReason, 'it was not a rated game');
    });

    test('a rated game with the overlays on says so', () async {
      final store = await _storeOver(_record(hints: true));
      expect(store.refusedReason, 'the hint overlays were on the board');
    });

    test('a rated takeback still reads as a takeback', () async {
      final store = await _storeOver(_record(undos: 1));
      expect(store.refusedReason, 'you took a move back');
    });

    test('no bot at all outranks the mode', () async {
      // An analysis game is not rated either, but "there was no bot opponent"
      // is the thing that is actually wrong with it.
      final store = await _storeOver(_record(rated: null, persona: null));
      expect(store.refusedReason, 'there was no bot opponent');
    });
  });
}

/// A practice controller whose collect NEVER returns, which parks the grading
/// pipeline and so holds the save's grade-wait window open. A bare Completer,
/// not a delay: a pending TIMER at the end of a widget test fails it for a
/// reason that has nothing to do with what was being checked.
class _ParkingPractice implements PracticeController {
  @override
  Future<void> maybeCollect(Map<String, dynamic> storedMove,
          {String? setupUci, int minDepth = 8}) =>
      Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
