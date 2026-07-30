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

  group('castling reaches the engine as king-two-squares', () {
    // The regression that made this group necessary: dartchess offers the king
    // BOTH g1 and h1 (includeAlternateCastlingMoves), chessground fires
    // whichever square you drop on, and MoveRecord stores it verbatim. morlock
    // generates castling only as e1g1, compares by from/to, and RETURNS from
    // its driver on an unmatched move — ending the engine and handing the game
    // to a Stockfish stand-in for good.
    //
    // The earlier version of this file hand-fed `e1g1`, the one spelling that
    // works, and so asserted the bug away.

    const mid =
        'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';

    test('the board really does offer the king-takes-rook square', () async {
      // Precondition. If dartchess ever stops offering h1, this whole group is
      // guarding something unreachable and should say so out loud.
      final g = await makeGame(fromFen: mid);
      expect(g.position.isLegal(NormalMove.fromUci('e1h1')), isTrue,
          reason: 'dropping the king on its rook is a supported gesture');
    });

    test('dragging the king onto the rook still sends e1g1', () async {
      final g = await makeGame(fromFen: mid);
      g.playerMove(NormalMove.fromUci('e1h1'), 'O-O');

      expect(g.moves.last.uci, 'e1h1',
          reason: 'precondition: the record keeps what was dragged');
      expect(g.retroPositionFor(g.position.fen).moves, ['e1g1'],
          reason: 'but the ENGINE must be told the spelling it generates');
    });

    test('queenside too', () async {
      const q = 'r3kbnr/pppq1ppp/2npb3/4p3/4P3/2NPB3/PPPQ1PPP/R3KBNR w KQkq - 6 6';
      final g = await makeGame(fromFen: q);
      g.playerMove(NormalMove.fromUci('e1a1'), 'O-O-O');
      expect(g.retroPositionFor(g.position.fen).moves, ['e1c1']);
    });

    test('an ordinary king move is left alone', () async {
      // The normaliser keys on "was this a castle", not on "did the king move
      // somewhere suggestive" — a king stepping to a square that happens to be
      // adjacent must not be rewritten.
      const k = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
      final g = await makeGame(fromFen: k);
      g.playerMove(NormalMove.fromUci('e1f1'), 'Kf1');
      expect(g.retroPositionFor(g.position.fen).moves, ['e1f1']);
    });
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
