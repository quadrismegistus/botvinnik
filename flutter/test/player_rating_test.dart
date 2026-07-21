// The player's rating, against the real brain.
//
// The point of this file is the REFUSALS. `estimatePlayerElo` drops games
// whose opponent was substituted (`botFallback`) and games the human took back
// (`botUndos > 0`), and a rating that quietly counted either would look
// exactly like a working one: no error, no crash, a plausible number that is
// simply wrong. Both flags are recent and both have already shipped bugs, so
// nothing here trusts that they arrive — the archive fixtures carry them in
// the shape GameController._saveGame actually writes, and the assertions run
// through the shipped bundle.
//
// Every test that claims an exclusion is paired with the same archive
// UNFLAGGED, so a green result cannot mean "the fixture never reached the
// code": if the flags were being dropped in transit, the flagged and unflagged
// runs would agree, and the pair fails.
//
//   cd flutter && flutter test test/player_rating_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/rating_api.dart';
import 'package:botvinnik_mobile/stores/player_rating_store.dart';

import 'support/fake_db.dart';
import 'support/node_brain.dart';

/// A record in the shape GameController._saveGame writes: every field it sets,
/// including the move list, which the store strips before the fit. Optional
/// flags are OMITTED rather than written false, exactly as the save path does
/// ("absent and false mean the same thing" — see the comments there), so a
/// clean game here is byte-for-byte the clean game the app archives.
Map<String, dynamic> _game({
  required String id,
  required String result,
  String? persona = 'squarefish-1200',
  String botColor = 'b',
  bool fallback = false,
  int undos = 0,
  bool bothSides = false,
  String endedAt = '2026-07-20T10:00:00.000',
}) =>
    {
      'id': id,
      'endedAt': endedAt,
      'result': result,
      'pgn': '1. e4 e5 *',
      'botElo': persona == null ? null : 1440,
      'botPersona': ?persona,
      if (fallback) 'botFallback': true,
      if (undos > 0) 'botUndos': undos,
      if (persona != null) 'botHintsUsed': false,
      if (bothSides) 'botBothSides': true,
      'botColor': persona == null ? null : botColor,
      'moveCount': 2,
      'whiteAccuracy': 82.4,
      'blackAccuracy': 71.0,
      'labelCounts': {
        'w': {'best': 1},
        'b': {'inaccuracy': 1}
      },
      'labelVersion': 1,
      // Present and non-trivial on purpose: the store drops `moves` before the
      // fit, and a projection that dropped the wrong thing would show up here.
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          'fenAfter': 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
          'evalPawns': 0.3,
          'mate': null,
          'pctBest': 100,
          'wcDrop': 0.0,
          'label': 'best',
        },
      ],
    };

/// Newest first, the order [FakeDb.listGames] and the real one return.
Future<PlayerRatingStore> _store(List<Map<String, dynamic>> newestFirst,
    {NodeBrainBridge? bridge}) async {
  // FakeDb reverses what it holds, so hand it oldest-first.
  final db = FakeDb(newestFirst.reversed.toList());
  final store =
      PlayerRatingStore(db, RatingApi(bridge ?? NodeBrainBridge()));
  await store.refresh();
  return store;
}

/// Four wins over Square 1200 — a clean record that fits well above the
/// opponent, so anything mixed into it moves the number visibly.
List<Map<String, dynamic>> _fourWins() => [
      for (var i = 0; i < 4; i++)
        _game(id: 'win-$i', result: '1-0', endedAt: '2026-07-1${i}T10:00:00.000'),
    ];

/// A plausible run of play: mixed results across four Squares. Newest first.
List<Map<String, dynamic>> _mixed() => [
      _game(id: 'm5', result: '1-0', persona: 'squarefish-1200'),
      _game(id: 'm4', result: '0-1', persona: 'squarefish-1400'),
      _game(id: 'm3', result: '1/2-1/2', persona: 'squarefish-1200'),
      _game(id: 'm2', result: '1-0', persona: 'squarefish-1100'),
      _game(id: 'm1', result: '0-1', persona: 'squarefish-1200'),
      _game(id: 'm0', result: '1-0', persona: 'squarefish-1000'),
    ];

void main() {
  test('a substituted opponent and a takeback are both refused by the fit',
      () async {
    // The newest two games are losses. If either counted, four wins would
    // become four wins and a loss or two — a different number and a different
    // count.
    final archive = [
      _game(id: 'undone', result: '0-1', undos: 2),
      _game(id: 'stood-in', result: '0-1', fallback: true),
      ..._fourWins(),
    ];
    final store = await _store(archive);

    expect(store.rating, isNotNull);
    expect(store.rating!.games, 4,
        reason: 'six games archived, four on the ruler — the substituted game '
            'and the taken-back one are off it');

    // And prove the flags are what did it. Same six games, same results, same
    // order — only the two flags removed. If they were never reaching the
    // brain, this fit would be identical to the one above and this test would
    // be measuring nothing.
    final unflagged = [
      _game(id: 'undone', result: '0-1'),
      _game(id: 'stood-in', result: '0-1'),
      ..._fourWins(),
    ];
    final loose = await _store(unflagged);
    expect(loose.rating!.games, 6);
    expect(loose.rating!.elo, lessThan(store.rating!.elo),
        reason: 'two extra losses can only pull the estimate down; if the two '
            'fits agree, the flags never crossed the bridge');
  });

  test('the flags cross the bridge on the record, not stripped with the moves',
      () async {
    final bridge = NodeBrainBridge();
    await _store([
      _game(id: 'undone', result: '0-1', undos: 2),
      _game(id: 'stood-in', result: '0-1', fallback: true),
      ..._fourWins(),
    ], bridge: bridge);

    final sent = bridge.exprs.first;
    expect(sent, contains('"botFallback":true'));
    expect(sent, contains('"botUndos":2'));
    // The reason the flags are worth asserting on the wire: the store trims
    // the record, and a trim that listed what to KEEP is how they would go
    // missing. This one lists what to drop.
    expect(sent, isNot(contains('"fenBefore"')),
        reason: 'the move list is not part of the fit and is 99% of the bytes');
    expect(sent, contains('"labelCounts"'),
        reason: 'everything except the moves survives — the projection is '
            'subtractive, so a field added to the record later still arrives');
  });

  test('a game the estimator refused is reported as not counting', () async {
    final store = await _store([
      _game(id: 'undone', result: '1-0', undos: 1),
      ..._fourWins(),
    ]);

    expect(store.rating!.games, 4);
    expect(store.lastGameRefused, isTrue);
    expect(store.refusedReason, 'you took a move back');
    expect(store.delta, isNull,
        reason: 'a refused game moved nothing, so there is no change to show');
  });

  test('a substituted game is reported with its own reason', () async {
    final store = await _store([
      _game(id: 'stood-in', result: '1-0', fallback: true),
      ..._fourWins(),
    ]);
    expect(store.lastGameRefused, isTrue);
    expect(store.refusedReason, 'your opponent was substituted part-way through');
  });

  test('a clean newest game counts, and its effect on the number is shown',
      () async {
    final store = await _store([
      _game(id: 'loss', result: '0-1'),
      ..._fourWins(),
    ]);

    expect(store.rating!.games, 5);
    expect(store.lastGameRefused, isFalse);
    expect(store.refusedReason, isNull);
    expect(store.delta, isNotNull);
    expect(store.delta, lessThan(0),
        reason: 'the newest game is a loss against a weaker opponent');
  });

  test('bot-vs-bot never enters the fit', () async {
    // Nobody played this one. The brain refuses it — gameStore declares
    // botBothSides and playerElo drops it beside botFallback and botUndos — so
    // this test reddens when that line goes, not when any Dart filter does.
    // (It DID live in the store for one commit, while the field was
    // Flutter-only; a93ab5e moved it where the other two are.)
    final store = await _store([
      _game(id: 'bots', result: '1-0', bothSides: true),
      ..._fourWins(),
    ]);
    expect(store.rating!.games, 4);
    expect(store.lastGameRefused, isTrue);
    expect(store.refusedReason, 'both sides were bots');
  });

  test('analysis and abandoned games are refused too', () async {
    final analysis = await _store([
      _game(id: 'analysis', result: '1-0', persona: null),
      ..._fourWins(),
    ]);
    expect(analysis.rating!.games, 4);
    expect(analysis.refusedReason, 'there was no bot opponent');

    final abandoned = await _store([
      _game(id: 'quit', result: '*'),
      ..._fourWins(),
    ]);
    expect(abandoned.rating!.games, 4);
    expect(abandoned.refusedReason, 'it has no result');
  });

  test('an empty archive has no rating at all', () async {
    final store = await _store([]);
    expect(store.rating, isNull);
    expect(store.confident, isFalse);
    expect(store.lastGameRefused, isFalse,
        reason: 'there is no last game to refuse');
  });

  test('an archive of nothing but refused games has no rating', () async {
    final store = await _store([
      _game(id: 'undone', result: '1-0', undos: 3),
      _game(id: 'stood-in', result: '1-0', fallback: true),
    ]);
    expect(store.rating, isNull,
        reason: 'two games archived, none of them on the ruler');
  });

  test('one game fits but is not confident enough to print', () async {
    final one = await _store([_game(id: 'a', result: '1-0')]);
    expect(one.rating!.games, 1);
    expect(one.rating!.se, greaterThan(kMaxUsefulSe));
    expect(one.confident, isFalse,
        reason: 'the fit exists; it just cannot be told apart from any other');
  });

  test('a spread of results over a spread of opponents becomes confident',
      () async {
    final store = await _store(_mixed());
    expect(store.rating!.games, 6);
    expect(store.rating!.se, lessThanOrEqualTo(kMaxUsefulSe));
    expect(store.confident, isTrue);
  });

  test('a run of wins over one bot prints, but marked provisional', () async {
    // The fit sits where the player wins nine in ten, so each win adds almost
    // nothing and the error bar stays wide. That is worth SAYING — it is not a
    // reason to withhold the number, which is what an se-only gate did.
    final store = await _store(_fourWins());
    expect(store.rating!.games, 4);
    expect(store.rating!.se, greaterThan(kMaxUsefulSe));
    expect(store.confident, isTrue, reason: 'four counted games is a number');
    expect(store.provisional, isTrue, reason: 'and a wide one');
  });

  test('winning well never takes the number away again', () async {
    // The bug an se-only gate had: standard error is not monotonic. Beating a
    // much stronger bot widens the plausible range, so a good win could push se
    // past the bar and replace a printed rating with "not enough games yet" —
    // in the recap for that very game. Measured against the shipped bundle:
    // three mixed games gave se 183 and printed; adding a win over
    // Stockfish 2000 gave se 233.
    final before = await _store(_mixed().take(3).toList());
    expect(before.confident, isTrue, reason: 'precondition: it was printing');

    final after = await _store([
      ..._mixed().take(3),
      // the player, as White, beats a much stronger bot
      _game(id: 'big-win', result: '1-0', persona: 'stockfish-2000'),
    ]);
    expect(after.rating!.se, greaterThan(before.rating!.se!),
        reason: 'the error bar really does widen — that is the whole trap');
    expect(after.confident, isTrue,
        reason: 'and the number must still be there');
  });

  test('the fit waits for a game that is still being archived', () async {
    // GameController archives asynchronously and, after a checkmate, only once
    // the grade wait times out. Refitting once at game over would print the
    // rating from BEFORE the game the recap is about.
    final db = FakeDb(_fourWins().reversed.toList());
    final store = PlayerRatingStore(db, RatingApi(NodeBrainBridge()),
        pollInterval: const Duration(milliseconds: 20),
        pollDeadline: const Duration(seconds: 5));

    final done = store.refresh(expectNewGame: true);
    // lands while the store is polling
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await db.saveGame(_game(
        id: 'late', result: '0-1', endedAt: '2026-07-20T23:00:00.000'));
    await done;

    expect(store.scoring, isFalse);
    expect(store.rating!.games, 5, reason: 'the late arrival is in the fit');
    expect(store.delta, isNotNull);
  });

  test('a later refresh supersedes a poll still running from an earlier one',
      () async {
    // The store outlives the card: abandon a finished game (new game, or just
    // walk away) and the poll from that game keeps running. Whatever it does
    // afterwards must not land on top of a newer fit, and it must not leave
    // the card saying "Adding this game..." with nothing coming.
    final db = FakeDb(_fourWins().reversed.toList());
    final store = PlayerRatingStore(db, RatingApi(NodeBrainBridge()),
        pollInterval: const Duration(milliseconds: 20),
        pollDeadline: const Duration(seconds: 3));

    final abandoned = store.refresh(expectNewGame: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(store.scoring, isTrue);

    await store.refresh();
    expect(store.scoring, isFalse,
        reason: 'the newer fit owns the state now');

    final waited = Stopwatch()..start();
    await abandoned;
    waited.stop();
    expect(store.scoring, isFalse);
    // The deadline is three seconds. Returning well inside it is the only
    // observable difference between "stopped" and "ran to the end and happened
    // to leave the same state behind", so the guard is asserted on the clock.
    expect(waited.elapsedMilliseconds, lessThan(1000),
        reason: 'the abandoned poll kept going instead of standing down');
  });

  test('waiting gives up rather than hanging when nothing is archived',
      () async {
    final db = FakeDb(_fourWins().reversed.toList());
    final store = PlayerRatingStore(db, RatingApi(NodeBrainBridge()),
        pollInterval: const Duration(milliseconds: 10),
        pollDeadline: const Duration(milliseconds: 80));

    await store.refresh(expectNewGame: true);
    expect(store.scoring, isFalse);
    expect(store.rating!.games, 4);
  });
}
