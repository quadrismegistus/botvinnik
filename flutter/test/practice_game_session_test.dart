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
