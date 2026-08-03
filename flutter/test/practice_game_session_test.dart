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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a game session draws only the scoped positions', () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession({_fenA, _fenC});

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

    h.practice.startGameSession({_fenA});
    expect(h.practice.current?['id'], _fenA,
        reason: "you picked the game, so its own mistake is drilled regardless "
            'of the queue threshold');
  });

  test('a motif tap mid-session walks the game forward under its rules', () {
    // setMotifFilter was the one live path that answered "what does this
    // session draw from" differently from _serveNextInGame (#289) — it drew
    // the whole scope, ignoring _gameServed. Now it routes through the walk,
    // exactly as nextPuzzle and remove do: the scope holds, low drops still
    // serve (all-drops is the default), and a served item does not come back.
    final h = makePractice([
      practiceItem(_fenA, motifs: const ['fork']),
      practiceItem(_fenB, motifs: const ['fork']), // out of scope
      practiceItem(_fenC, motifs: const ['fork'], drop: 8), // sub-threshold
    ]);

    h.practice.startGameSession({_fenA, _fenC});
    final first = h.practice.current!['id'] as String;
    h.bridge.nextItemArgs.clear();
    h.practice.setMotifFilter('fork');

    expect(h.practice.inGameSession, isTrue, reason: 'the scope holds');
    expect(h.practice.motifFilter, isNull,
        reason: 'no control on screen shows or clears a mid-session filter '
            '(the picker is hidden), so the backstop must not set one');
    // Which of the two scoped items comes first is the scheduler's pick (the
    // real brain draws overdue-weighted RANDOM; the fake is deterministic),
    // so assert against `first`, not a named fen.
    expect(lastPoolIds(h.bridge), {_fenA, _fenC}.difference({first}),
        reason: 'the walk serves the unserved scoped item — not the already '
            'served one, not the out-of-game one — and still reaches below '
            'the serve threshold');
    expect(h.practice.current?['id'], isNot(first));
    expect({_fenA, _fenC}, contains(h.practice.current?['id']));
  });

  test('clearing the filter mid-session obeys the walk too', () {
    // The backstop is for ANY filter change, not just setting one: null is a
    // first-class input ("All puzzles", both "Show all puzzles" buttons). No
    // UI path reaches here with a filter set today — startGameSession clears
    // it and the picker is hidden — so this pins the guard against the future
    // caller that would make it live (motifFilter is a public field). Without
    // it, a mutant guarding only `motif != null` re-opens every #289 state on
    // the clear direction and the whole suite stays green.
    final h = makePractice([practiceItem(_fenA, motifs: const ['fork'])]);

    h.practice.startGameSession({_fenA});
    h.practice.nextPuzzle();
    expect(h.practice.gameDoneNote, isNotNull, reason: 'precondition: walked');

    h.practice.motifFilter = 'fork'; // a future caller's direct write
    h.practice.setMotifFilter(null);

    expect(h.practice.current, isNull,
        reason: 'the clear direction must not re-open a finished walk');
    expect(h.practice.gameDoneNote, isNotNull, reason: 'or wipe its note');
  });

  test('a motif tap honours the drop bar the session banner advertises', () async {
    // Issue #289's first repro: bar on at 20, items at drop 6 and 25 in scope.
    // The walk serves only the 25; a motif tap then put the drop-6 item on
    // screen — the one the bar exists to withhold — while the banner still
    // read "over the bar".
    final h = makePractice([
      practiceItem(_fenA, drop: 25, motifs: const ['fork']),
      practiceItem(_fenB, drop: 6, motifs: const ['fork']),
    ]);
    h.practice.settings = await _settings({
      'botvinnik-collect-threshold': '20',
      'botvinnik-game-session-all': '0',
    });

    h.practice.startGameSession({_fenA, _fenB});
    expect(h.practice.current?['id'], _fenA,
        reason: 'precondition: the bar withholds the drop-6 item');

    h.practice.setMotifFilter('fork');
    expect(h.practice.current, isNull,
        reason: 'the drop-6 item stays withheld — the walk ends instead of '
            'escaping the bar');
    // The note must not claim the withheld item was drilled: "all 2 mistakes"
    // after serving one was a lie the bar's own end state told.
    expect(h.practice.gameDoneNote, contains('1 mistake over the bar'));
    expect(h.practice.gameDoneNote, contains('1 more below it'));
    expect(h.practice.gameDoneNote, isNot(contains('all')));
  });

  test('a session whose every mistake is under the bar says so, not "0 over"',
      () async {
    // Reachable state: the bar on, and nothing in the scope clears it — the
    // session opens straight onto the browser with the note. "You've been
    // through the 0 mistakes over the bar" is truthful and not a sentence.
    final h = makePractice([
      practiceItem(_fenA, drop: 6),
      practiceItem(_fenB, drop: 8),
    ]);
    h.practice.settings = await _settings({
      'botvinnik-collect-threshold': '20',
      'botvinnik-game-session-all': '0',
    });

    h.practice.startGameSession({_fenA, _fenB});
    expect(h.practice.current, isNull, reason: 'nothing clears the bar');
    expect(h.practice.gameDoneNote,
        'All 2 mistakes from this game are below the bar.');
    expect(h.practice.gameDoneNote, isNot(contains('0')));
  });

  test('a motif tap after every mistake was served ends the walk', () {
    // Issue #289's second repro: a 2-mistake session, both served; a motif tap
    // re-served the first WITHOUT marking it, so the walk served it a third
    // time. Total served in a 2-mistake game: 3, under a note saying "all 2".
    final h = makePractice([
      practiceItem(_fenA, motifs: const ['fork']),
      practiceItem(_fenB, motifs: const ['fork']),
    ]);

    h.practice.startGameSession({_fenA, _fenB});
    final served = <String>{h.practice.current!['id'] as String};
    h.practice.nextPuzzle();
    served.add(h.practice.current!['id'] as String);
    expect(served, {_fenA, _fenB}, reason: 'precondition: both served once');

    h.practice.setMotifFilter('fork');
    expect(h.practice.current, isNull,
        reason: 'nothing unserved remains — a third serve was the bug');
    expect(h.practice.gameDoneNote, contains('2 mistakes'));
  });

  test('the done note counts serves, so a mid-session remove cannot inflate it',
      () async {
    // The issue's "related" case: the old note reported the start-of-session
    // figure, so removing a not-yet-served item mid-walk left it claiming
    // "all 2" after one. Counting what the walk actually served fixes the bar
    // case and this one with the same number.
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession({_fenA, _fenB});
    final firstServed = h.practice.current!['id'] as String;
    final other = firstServed == _fenA ? _fenB : _fenA;
    await h.practice.remove(other); // never served, deleted mid-session

    h.practice.nextPuzzle();
    expect(h.practice.current, isNull, reason: 'nothing left to walk');
    expect(h.practice.gameDoneNote, contains('all 1 mistake'),
        reason: 'one item was drilled; the deleted one must not be counted');
    expect(h.practice.gameDoneNote, isNot(contains('2')));
  });

  test('a motif tap cannot restart a finished game session', () {
    // Issue #289's third repro: after the walk exhausted (current null, note
    // set), a motif tap re-served a walked item and wiped the note.
    final h = makePractice([practiceItem(_fenA, motifs: const ['fork'])]);

    h.practice.startGameSession({_fenA});
    h.practice.nextPuzzle();
    expect(h.practice.current, isNull, reason: 'precondition: walked out');
    expect(h.practice.gameDoneNote, isNotNull, reason: 'precondition');

    h.practice.setMotifFilter('fork');
    expect(h.practice.current, isNull,
        reason: 'a walked item must not come back');
    expect(h.practice.gameDoneNote, contains('1 mistake'),
        reason: 'the session stays finished, note intact');
    expect(h.practice.inGameSession, isTrue);
  });

  test('a second game session starts its walk over', () {
    // `_gameServed` is cleared on both entering and leaving a session, and only
    // the leaving half was covered: no test had ever started a SECOND one.
    // Without the clear, practising game B after game A skips every position
    // they share — worst case the new session opens already finished.
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession({_fenA, _fenB});
    h.practice.nextPuzzle();
    h.practice.nextPuzzle();
    expect(h.practice.current, isNull, reason: 'precondition: walked out');

    h.practice.startGameSession({_fenA, _fenB});
    expect(h.practice.current, isNotNull,
        reason: 'a new session serves its first mistake, not nothing');
  });

  test('countForGame counts collection items on the given fens', () {
    final h = makePractice([
      practiceItem(_fenA, drop: 8), // sub-threshold, still collected & counted
      practiceItem(_fenB),
    ]);

    expect(h.practice.countForGame({_fenA, _fenB, _fenC}), 2);
    expect(h.practice.countForGame({_fenC}), 0,
        reason: 'a position never blundered has no collected item');
  });

  test('nextPuzzle stays inside the scope and never leaks a third position',
      () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession({_fenA, _fenB});
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

    h.practice.startGameSession({_fenA, _fenB});
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

    h.practice.startGameSession({_fenA});
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

    h.practice.startGameSession({_fenA, _fenB, _fenC});
    h.practice.nextPuzzle(); // exhausts the one real mistake

    expect(h.practice.gameDoneNote, contains('1 mistake'),
        reason: 'a quiet scoped position must not be miscounted as a mistake');
    expect(h.practice.gameDoneNote, isNot(contains('3')));
  });

  test('exiting a finished game session clears the done note', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession({_fenA});
    h.practice.nextPuzzle(); // exhausts the single-item scope
    expect(h.practice.gameDoneNote, isNotNull);

    h.practice.exitGameSession();
    expect(h.practice.gameDoneNote, isNull);
    expect(h.practice.inGameSession, isFalse);
    expect(h.practice.current?['id'], anyOf(_fenA, _fenB));
  });

  test('picking a puzzle from the browser leaves the game session', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession({_fenA});
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
    h.practice.startGameSession({_fenA});
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

    h.practice.startGameSession({_fenA});
    expect(h.practice.gameSessionSerial, greaterThan(before));
  });

  test('exiting the game session returns to the full queue', () {
    final h = makePractice([
      practiceItem(_fenA),
      practiceItem(_fenB),
      practiceItem(_fenC),
    ]);

    h.practice.startGameSession({_fenA});
    expect(h.practice.inGameSession, isTrue);

    h.practice.exitGameSession();
    expect(h.practice.inGameSession, isFalse);
    expect(lastPoolIds(h.bridge), {_fenA, _fenB, _fenC},
        reason: 'the full servable collection is back in the pool');
  });

  test('a fresh general session drops any leftover game scope', () {
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);

    h.practice.startGameSession({_fenA});
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

    h.practice.startGameSession({_fenA, _fenB});
    expect(h.practice.motifFilter, isNull,
        reason: 'a game scope stacked under a leftover motif could serve '
            'nothing over a game that has plenty');
    expect(lastPoolIds(h.bridge), {_fenA, _fenB});
  });
}
