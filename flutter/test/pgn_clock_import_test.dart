// Per-move time out of a PGN (#267).
//
// Two annotations, two meanings: %emt is the elapsed time, %clk is the time
// remaining. lichess and chess.com write %clk, so most real imports go through
// the differencing path — which is the one that can go wrong.
//
//   cd flutter && flutter test test/pgn_clock_import_test.dart

import 'package:botvinnik_mobile/stores/pgn_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1);

  List<Map<String, dynamic>> movesOf(String pgn) {
    final game = gameFromPgn(pgn, now: now);
    expect(game, isNotNull, reason: 'the PGN itself must parse');
    return (game!['moves'] as List).cast<Map<String, dynamic>>();
  }

  test('reads %emt as the elapsed time it is', () {
    final moves = movesOf('[Result "*"]\n\n1. e4 {[%emt 0:00:12.5]} e5 {[%emt 0:00:03]} *');
    expect(moves[0]['thinkMs'], 12500);
    expect(moves[1]['thinkMs'], 3000);
  });

  test('differences %clk, which is a remaining time and not an elapsed one', () {
    // 5:00 -> 4:50 is ten seconds spent, not "four minutes fifty"
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {[%clk 0:04:50]} Nc6 {[%clk 0:04:45]} *');
    expect(moves[0]['thinkMs'], isNull, reason: 'nothing to difference against');
    expect(moves[1]['thinkMs'], isNull);
    expect(moves[2]['thinkMs'], 10000);
    expect(moves[3]['thinkMs'], 15000);
  });

  test('adds back the increment, which the clock has already paid out', () {
    // 600+5: a move that leaves the clock unchanged took five seconds
    final moves = movesOf('[Result "*"]\n[TimeControl "600+5"]\n\n'
        '1. e4 {[%clk 0:10:00]} e5 {[%clk 0:10:00]} '
        '2. Nf3 {[%clk 0:10:00]} Nc6 {[%clk 0:09:57]} *');
    expect(moves[2]['thinkMs'], 5000);
    expect(moves[3]['thinkMs'], 8000);
  });

  test('drops a reading where the clock went up', () {
    // a stitched or corrected PGN; better to say nothing than to say -20s
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {[%clk 0:05:20]} Nc6 {[%clk 0:04:00]} *');
    expect(moves[2]['thinkMs'], isNull);
    expect(moves[3]['thinkMs'], 60000, reason: 'the other side is unaffected');
  });

  test('%emt wins over %clk when a move carries both', () {
    // %emt is the answer; %clk only implies one
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {[%clk 0:04:00][%emt 0:00:07]} *');
    expect(moves[2]['thinkMs'], 7000);
  });

  test('an %emt move breaks the %clk chain rather than poisoning it', () {
    // The %emt branch used to return without touching the baseline, so the
    // NEXT %clk differenced against a stale reading: 4:50 -> 4:30 is 20s and
    // it reported 30s, silently, into the archive.
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {[%clk 0:04:50][%emt 0:00:10]} Nc6 {[%clk 0:04:40]} '
        '3. d4 {[%clk 0:04:30]} exd4 {[%clk 0:04:30]} *');
    expect(moves[2]['thinkMs'], 10000, reason: '%emt is taken as read');
    expect(moves[4].containsKey('thinkMs'), isFalse,
        reason: 'the chain restarts; 30000 was the bug');
  });

  test('an unreadable %clk breaks the chain rather than being skipped over', () {
    // 0:0:1:2 matches the regex and fails the parser. Merely skipping it left
    // the stale 5:00 as the baseline, so the NEXT reading differenced against
    // a clock two moves old.
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {[%clk 0:0:1:2]} Nc6 {[%clk 0:04:50]} '
        '3. d4 {[%clk 0:04:40]} *');
    expect(moves[2].containsKey('thinkMs'), isFalse);
    expect(moves[4].containsKey('thinkMs'), isFalse,
        reason: 'the baseline is gone; 20000 against the stale 5:00 was the bug');
  });

  test('a four-field clock is refused', () {
    // under the one-day ceiling, so only the field count can refuse it
    expect(movesOf('[Result "*"]\n\n1. e4 {[%emt 0:0:1:2]} *')[0]
        .containsKey('thinkMs'), isFalse);
  });

  test('a note before the clock does not hide it', () {
    // the %clk loop, which the %emt case above cannot reach
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {a note} {[%clk 0:05:00]} e5 {[%clk 0:05:00]} '
        '2. Nf3 {a note} {[%clk 0:04:45]} *');
    expect(moves[2]['thinkMs'], 15000);
  });

  test('two comments on one move are both examined', () {
    // dartchess hands the annotations back as a LIST, and stopping at the
    // first one that is not a clock loses the one that is
    final moves = movesOf('[Result "*"]\n\n1. e4 {a note} {[%emt 4]} *');
    expect(moves[0]['thinkMs'], 4000);
  });

  test('a PGN with no clock comments carries no times at all', () {
    final moves = movesOf('[Result "*"]\n\n1. e4 e5 2. Nf3 Nc6 *');
    for (final m in moves) {
      expect(m.containsKey('thinkMs'), isFalse,
          reason: 'absent, not zero — a game with no clock knows nothing');
    }
  });

  test('a comment that is not a clock at all is ignored', () {
    // "banana" fails the REGEX, so this exercises the match and never reaches
    // the parser — which is a different guard, tested below
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%emt banana]} e5 {[%emt 0:00:04]} *');
    expect(moves[0].containsKey('thinkMs'), isFalse);
    expect(moves[1]['thinkMs'], 4000);
  });

  test('a clock value that matches but does not parse is skipped, not guessed', () {
    // four colon-separated fields: passes [0-9:.]+ and fails the parser
    final moves = movesOf('[Result "*"]\n\n1. e4 {[%emt 1:2:3:4]} *');
    expect(moves[0].containsKey('thinkMs'), isFalse);
  });

  test('an absurd value is refused rather than stored', () {
    // 999...9 (400 digits) overflowed a double and threw "Infinity or NaN
    // toInt" out of gameFromPgn — which could not throw at all before this
    // existed, leaving the import dialog spinning with no error
    final huge = '[Result "*"]\n\n1. e4 {[%emt ${'9' * 400}]} *';
    expect(() => gameFromPgn(huge, now: now), returnsNormally);
    expect(movesOf(huge)[0].containsKey('thinkMs'), isFalse);
    // and a merely large one stored a NEGATIVE time by int64 wraparound
    final big = movesOf('[Result "*"]\n\n1. e4 {[%emt 1000000000000000000000]} *');
    expect(big[0].containsKey('thinkMs'), isFalse);
  });

  test('a day is the ceiling on one move', () {
    expect(movesOf('[Result "*"]\n\n1. e4 {[%emt 86401]} *')[0].containsKey('thinkMs'),
        isFalse);
    expect(movesOf('[Result "*"]\n\n1. e4 {[%emt 86399]} *')[0]['thinkMs'], 86399000);
  });

  test('reads the bare-seconds form of %emt', () {
    final moves = movesOf('[Result "*"]\n\n1. e4 {[%emt 3.25]} *');
    expect(moves[0]['thinkMs'], 3250);
  });

  test('refuses %clk entirely under a header it cannot account for', () {
    // "40/7200:3600" grants time per period that differencing cannot see.
    // Reading the 3600 as an increment would add an hour to every move; the
    // anchors are the only thing stopping that, so this pins them.
    final moves = movesOf('[Result "*"]\n[TimeControl "40/7200:3600"]\n\n'
        '1. e4 {[%clk 1:00:00]} e5 {[%clk 1:00:00]} '
        '2. Nf3 {[%clk 0:59:30]} *');
    expect(moves[2].containsKey('thinkMs'), isFalse);
  });

  test('an inner "+" does not make a multi-period header readable', () {
    // "40/7200+30:3600" contains a real increment AND periods; an unanchored
    // match would find the 30 and add it to every move
    final moves = movesOf('[Result "*"]\n[TimeControl "40/7200+30:3600"]\n\n'
        '1. e4 {[%clk 1:00:00]} e5 {[%clk 1:00:00]} '
        '2. Nf3 {[%clk 0:59:30]} *');
    expect(moves[2].containsKey('thinkMs'), isFalse);
  });

  test('refuses %clk on a correspondence game', () {
    // chess.com daily: three days a move, granted per move and invisible to
    // differencing. Measured on a real one: half nulls, and the surviving
    // half wrong by up to four and a half hours.
    final moves = movesOf('[Result "*"]\n[TimeControl "1/259200"]\n\n'
        '1. e4 {[%clk 0:57:27]} e5 {[%clk 1:00:00]} '
        '2. Nf3 {[%clk 0:02:04]} *');
    for (final m in moves) {
      expect(m.containsKey('thinkMs'), isFalse);
    }
  });

  test('a plain seconds header means no increment, not an unreadable one', () {
    final moves = movesOf('[Result "*"]\n[TimeControl "600"]\n\n'
        '1. e4 {[%clk 0:10:00]} e5 {[%clk 0:10:00]} '
        '2. Nf3 {[%clk 0:09:50]} *');
    expect(moves[2]['thinkMs'], 10000);
  });
}
