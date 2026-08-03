// Practise this game's own mistakes (#197): a practice session scoped to one
// reviewed game's blunder positions. The scope is a filter over the LIVE
// collection, not a forked queue — so these pin that a game session draws only
// the scoped items, that it reaches BELOW the serve threshold the way a
// hand-picked drill does (you chose the game), and that entering and leaving
// the scope routes through the same nextItem the whole collection uses, so the
// spaced-repetition schedule is the real one throughout.
//
//   cd flutter && flutter test test/practice_game_session_test.dart

import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/practice_harness.dart';

// Three distinct legal positions, so each item has its own id.
const _fenA = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _fenB = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
const _fenC = 'rnbqkbnr/ppp1pppp/8/3p4/8/8/PPPPPPPP/RNBQKBNR w KQkq d6 0 2';

Future<SettingsStore> _settings([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SettingsStore.load();
}

/// The ids in the items array the LAST recorded nextItem drew from — args[0],
/// which the controller pre-filters to the active pool.
Set<String> lastPoolIds(FakeBridge bridge) => {
      for (final i in (bridge.nextItemArgs.last[0] as List))
        (i as Map)['id'] as String,
    };

/// A game scope: each position paired with the move played there. The harness's
/// items all record `a2a3`, so this is what "collected in this game" looks like.
Map<String, String> _scope(Set<String> fens) => {for (final f in fens) f: 'a2a3'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a game session draws only the scoped positions', () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession(_scope({_fenA, _fenC}));

    expect(h.practice.inGameSession, isTrue);
    expect(lastPoolIds(h.bridge), {_fenA, _fenC},
        reason: 'the pool nextItem sees must exclude the out-of-game position');
    expect(h.practice.current?['id'], anyOf(_fenA, _fenC));
  });

  test('the scope reaches below the serve threshold, unlike the normal queue',
      () async {
    // drop 8 is below the default 15% serve threshold: servable excludes it, so
    // a normal session would never serve it. A game session must, the way a
    // hand-picked drill serves a sub-threshold position.
    final h = makePractice([practiceItem(_fenA, drop: 8)]);
    h.practice.settings = await _settings();

    h.practice.startSession();
    expect(h.practice.current, isNull,
        reason: 'nothing is servable — 8% is under the 15% threshold');

    h.practice.startGameSession(_scope({_fenA}));
    expect(h.practice.current?['id'], _fenA,
        reason: "you picked the game, so its own mistake is drilled regardless "
            'of the queue threshold');
  });

  test('an item collected in ANOTHER game at the same position is not in scope',
      () {
    // An item's id IS its fen, and items are deduped on it across the whole
    // collection — so a position that occurs in two games has ONE item, owned
    // by whichever game collected it first. Opening positions collide
    // constantly. Pairing the position with the move played there is what
    // tells the two apart (#285).
    final h = makePractice([
      practiceItem(_fenA, playedUci: 'g1f3'), // some other game's mistake
      practiceItem(_fenB),
    ]);

    h.practice.startGameSession(_scope({_fenA, _fenB}));

    expect(lastPoolIds(h.bridge), {_fenB},
        reason: 'the position occurred here; the mistake was made elsewhere');
    expect(h.practice.countForGame(_scope({_fenA, _fenB})), 1);
  });

  test('the same position AND the same move is in scope', () {
    // the control: identical setup but for the move played, which is the only
    // thing the filter looks at
    final h = makePractice([
      practiceItem(_fenA, playedUci: 'a2a3'),
      practiceItem(_fenB),
    ]);

    h.practice.startGameSession(_scope({_fenA, _fenB}));

    expect(lastPoolIds(h.bridge), {_fenA, _fenB});
    expect(h.practice.countForGame(_scope({_fenA, _fenB})), 2);
  });

  test('a motif filter set DURING a session still draws from the scope only',
      () {
    // The one path that reaches _pool's game branch rather than
    // _serveNextInGame's own filter — two implementations of "what this
    // session draws from", and only one of them was covered.
    final h = makePractice([
      practiceItem(_fenA, motifs: const ['fork']),
      practiceItem(_fenB, motifs: const ['fork']),
    ]);

    h.practice.startGameSession(_scope({_fenA}));
    h.bridge.nextItemArgs.clear();
    h.practice.setMotifFilter('fork');

    expect(h.practice.inGameSession, isTrue, reason: 'precondition');
    expect(lastPoolIds(h.bridge), {_fenA},
        reason: 'the filter narrows the scope, it does not escape it');
  });

  test('countForGame counts collection items on the given fens', () {
    final h = makePractice([
      practiceItem(_fenA, drop: 8), // sub-threshold, still collected & counted
      practiceItem(_fenB),
    ]);

    expect(h.practice.countForGame(_scope({_fenA, _fenB, _fenC})), 2);
    expect(h.practice.countForGame(_scope({_fenC})), 0,
        reason: 'a position never blundered has no collected item');
  });

  test('nextPuzzle stays inside the scope and never leaks a third position',
      () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession(_scope({_fenA, _fenB}));
    final first = h.practice.current?['id'];
    h.practice.nextPuzzle();

    expect(lastPoolIds(h.bridge), isNot(contains(_fenC)),
        reason: 'stepping through the session must not leak the third position');
    expect(h.practice.current?['id'], anyOf(_fenA, _fenB));
    expect(h.practice.current?['id'], isNot(first),
        reason: 'a game session walks forward — Next serves a fresh mistake');
  });

  test('a game session is finite: it walks each mistake once, then ends', () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC), // out of scope
    ]);

    h.practice.startGameSession(_scope({_fenA, _fenB}));
    final served = <String>{h.practice.current!['id'] as String};

    h.practice.nextPuzzle();
    served.add(h.practice.current!['id'] as String);
    expect(served, {_fenA, _fenB},
        reason: 'both scoped mistakes are served before the session ends');

    // The third Next has nothing left in scope — the session ENDS rather than
    // cycling back to the first (the forever-loop / loop-of-one bug).
    h.practice.nextPuzzle();
    expect(h.practice.current, isNull);
    expect(h.practice.inGameSession, isTrue,
        reason: 'still scoped — the banner and "Practise all" way out stay');
    expect(h.practice.gameDoneNote, isNotNull);
    expect(h.practice.gameDoneNote, contains('2 mistakes'));
  });

  test('a single-mistake session ends after one Next, never re-serving it', () {
    final h = makePractice([practiceItem(_fenA)]);

    h.practice.startGameSession(_scope({_fenA}));
    expect(h.practice.current?['id'], _fenA);

    h.practice.nextPuzzle();
    expect(h.practice.current, isNull,
        reason: 'a lone mistake is not re-served forever');
    expect(h.practice.gameDoneNote, contains('1 mistake'));
    expect(h.practice.gameDoneNote, isNot(contains('mistakes')));
  });

  test('the done note counts collected mistakes, not every scoped ply', () {
    // Production hands startGameSession EVERY move-before fen of the game (all
    // ~30 plies), not just the collected mistakes — only fenA carries an item.
    final h = makePractice([practiceItem(_fenA)]);

    h.practice.startGameSession(_scope({_fenA, _fenB, _fenC}));
    h.practice.nextPuzzle(); // exhausts the one real mistake

    expect(h.practice.gameDoneNote, contains('1 mistake'),
        reason: 'a quiet scoped position must not be miscounted as a mistake');
    expect(h.practice.gameDoneNote, isNot(contains('3')));
  });

  test('exiting a finished game session clears the done note', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession(_scope({_fenA}));
    h.practice.nextPuzzle(); // exhausts the single-item scope
    expect(h.practice.gameDoneNote, isNotNull);

    h.practice.exitGameSession();
    expect(h.practice.gameDoneNote, isNull);
    expect(h.practice.inGameSession, isFalse);
    expect(h.practice.current?['id'], anyOf(_fenA, _fenB));
  });

  test('picking a puzzle from the browser leaves the game session', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession(_scope({_fenA}));
    expect(h.practice.inGameSession, isTrue);

    // The browser lists the whole collection, not just the scope; drilling an
    // out-of-scope item must drop the scope so the "this game" banner doesn't
    // sit over a puzzle that isn't one of the game's mistakes.
    h.practice.serveItem(_fenB);
    expect(h.practice.inGameSession, isFalse);
    expect(h.practice.gameDoneNote, isNull);
    expect(h.practice.current?['id'], _fenB);
  });

  test('serving after a finished session drops the stale done note via _serve',
      () {
    // Exhaust a session so gameDoneNote is genuinely SET, then serve by a path
    // that only clears it through _serve (not an explicit null) — the note must
    // not resurface over the next puzzle.
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);
    h.practice.startGameSession(_scope({_fenA}));
    h.practice.nextPuzzle();
    expect(h.practice.gameDoneNote, isNotNull, reason: 'precondition: note set');

    h.practice.serveItem(_fenB);
    expect(h.practice.gameDoneNote, isNull);
    expect(h.practice.current?['id'], _fenB);
  });

  test('each game session bumps the serial so the tab can drop the browser',
      () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);
    final before = h.practice.gameSessionSerial;

    h.practice.startGameSession(_scope({_fenA}));
    expect(h.practice.gameSessionSerial, greaterThan(before));
  });

  test('exiting the game session returns to the full queue', () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession(_scope({_fenA}));
    expect(h.practice.inGameSession, isTrue);

    h.practice.exitGameSession();
    expect(h.practice.inGameSession, isFalse);
    expect(lastPoolIds(h.bridge), {_fenA, _fenB, _fenC},
        reason: 'the full servable collection is back in the pool');
  });

  test('a fresh general session drops any leftover game scope', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession(_scope({_fenA}));
    h.practice.startSession();

    expect(h.practice.inGameSession, isFalse);
    expect(lastPoolIds(h.bridge), {_fenA, _fenB});
  });

  test('starting a game session clears a stale motif filter', () {
    final h = makePractice([
      practiceItem(_fenA, motifs: ['fork']),
      practiceItem(_fenB), // in scope but untagged
    ]);

    h.practice.setMotifFilter('fork');
    expect(h.practice.motifFilter, 'fork');

    h.practice.startGameSession(_scope({_fenA, _fenB}));
    expect(h.practice.motifFilter, isNull,
        reason: 'a game scope stacked under a leftover motif could serve '
            'nothing over a game that has plenty');
    expect(lastPoolIds(h.bridge), {_fenA, _fenB});
  });
}
