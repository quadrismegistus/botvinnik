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

  test('a PGN with no clock comments carries no times at all', () {
    final moves = movesOf('[Result "*"]\n\n1. e4 e5 2. Nf3 Nc6 *');
    for (final m in moves) {
      expect(m.containsKey('thinkMs'), isFalse,
          reason: 'absent, not zero — a game with no clock knows nothing');
    }
  });

  test('an unreadable clock value is skipped, not guessed', () {
    final moves = movesOf('[Result "*"]\n\n'
        '1. e4 {[%emt banana]} e5 {[%emt 0:00:04]} *');
    expect(moves[0].containsKey('thinkMs'), isFalse);
    expect(moves[1]['thinkMs'], 4000);
  });

  test('reads the bare-seconds form of %emt', () {
    final moves = movesOf('[Result "*"]\n\n1. e4 {[%emt 3.25]} *');
    expect(moves[0]['thinkMs'], 3250);
  });

  test('ignores a TimeControl header it cannot read', () {
    // "40/7200:3600" describes periods; treating the 3600 as an increment
    // would add an hour to every move
    final moves = movesOf('[Result "*"]\n[TimeControl "40/7200:3600"]\n\n'
        '1. e4 {[%clk 1:00:00]} e5 {[%clk 1:00:00]} '
        '2. Nf3 {[%clk 0:59:30]} *');
    expect(moves[2]['thinkMs'], 30000);
  });
}
