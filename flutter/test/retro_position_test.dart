// What a retro engine is told about the position (#244).
//
// These engines read the move list — SARGON's Development term walks it, and
// without it scores every knight and bishop as undeveloped for the whole game.
// So the client sends `position fen <start> moves <line>` rather than a bare
// current FEN, which is also how the calibration gym drove them when it
// produced the ratings the roster advertises.
//
// The interesting case is not the happy path but the guard: `moves` is the
// line to the CURSOR, and a bot can be asked to move for a position that is
// not its end. Reconstructing from a mismatched line would describe a
// different game to the engine — confidently wrong, where the bare FEN was
// merely thin.
//
//   cd flutter && flutter test test/retro_position_test.dart

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/game_harness.dart';

void main() {
  test('a fresh game sends the start position and no moves', () async {
    final g = await makeGame();
    final p = g.retroPositionFor(g.position.fen);
    expect(p.moves, isEmpty);
    expect(p.fen, g.position.fen);
  });

  test('after some moves it sends the start position plus the whole line', () async {
    final g = await makeGame();
    final start = g.position.fen;
    g.playerMove(NormalMove.fromUci('e2e4'), 'e4');
    g.playerMove(NormalMove.fromUci('e7e5'), 'e5');
    g.playerMove(NormalMove.fromUci('g1f3'), 'Nf3');

    final p = g.retroPositionFor(g.position.fen);
    expect(p.fen, start, reason: 'the START position, not the current one');
    expect(p.moves, ['e2e4', 'e7e5', 'g1f3']);
  });

  test('a game started from a FEN keeps that FEN as the root', () async {
    // The root is whatever the game began from, not necessarily the initial
    // position — so the engine replays the line onto the right board.
    const mid = 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
    final g = await makeGame(fromFen: mid);
    g.playerMove(NormalMove.fromUci('e1g1'), 'O-O');

    final p = g.retroPositionFor(g.position.fen);
    expect(p.fen, mid);
    expect(p.moves, ['e1g1']);
  });

  test('a position that is NOT the end of the line falls back to the bare FEN',
      () async {
    // The guard. Ask about a position the recorded line does not reach — as a
    // review cursor parked mid-game, or a turn racing a takeback, would — and
    // it must describe that position alone rather than assert a history that
    // does not lead there.
    final g = await makeGame();
    g.playerMove(NormalMove.fromUci('e2e4'), 'e4');
    g.playerMove(NormalMove.fromUci('e7e5'), 'e5');

    const elsewhere =
        'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1';
    final p = g.retroPositionFor(elsewhere);
    expect(p.fen, elsewhere);
    expect(p.moves, isEmpty,
        reason: 'better thin than confidently describing another game');
  });
}
