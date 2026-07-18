// Perft with no file I/O, so it runs in a browser as well as natively:
//
//   dart test test/web_perft_test.dart              # native (64-bit int)
//   dart test -p chrome test/web_perft_test.dart    # web (32-bit halves)
//
// Move generation is the one place where correctness is decidable rather than
// argued: these node counts are published and exact. If the web SquareSet has
// a single wrong bit — a shift across the 32-bit boundary, a borrow, a
// popcount — the totals diverge immediately and by a lot.
//
// The positions are the standard set (CPW "Perft Results"): startpos,
// Kiwipete, and positions 3-6, chosen between them to exercise castling,
// en passant, promotion, discovered check and pins.

import 'package:dartchess/dartchess.dart';
import 'package:test/test.dart';

void main() {
  group('perft — identical on native and web', () {
    void check(String name, String fen, List<int> counts) {
      test(name, () {
        final pos = Chess.fromSetup(Setup.parseFen(fen));
        for (var depth = 1; depth < counts.length; depth++) {
          expect(perft(pos, depth), counts[depth],
              reason: '$name at depth $depth');
        }
      });
    }

    // index == depth; index 0 is unused
    check('startpos', Chess.initial.fen, [0, 20, 400, 8902, 197281]);

    check(
        'kiwipete — castling, pins, checks',
        'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
        [0, 48, 2039, 97862, 4085603]);

    check('position 3 — pawn races and rook endings',
        '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
        [0, 14, 191, 2812, 43238, 674624]);

    check(
        'position 4 — promotion and discovered check',
        'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
        [0, 6, 264, 9467, 422333]);

    check('position 5 — dense middlegame',
        'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
        [0, 44, 1486, 62379, 2103487]);

    check('position 6 — quiet, wide branching',
        'r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
        [0, 46, 2079, 89890, 3894594]);
  });

  group('the bit-level operations the web halves have to get right', () {
    test('squares survive a round trip across the 32-bit boundary', () {
      for (var i = 0; i < 64; i++) {
        final s = SquareSet.fromSquare(Square(i));
        expect(s.size, 1, reason: 'square $i should be a single bit');
        expect(s.first, Square(i));
        expect(s.last, Square(i));
        expect(s.has(Square(i)), isTrue);
        // the neighbours of the boundary are where a bad shift shows up
        expect(s.has(Square((i + 1) % 64)), isFalse);
      }
    });

    test('shifts move bits across the boundary in both directions', () {
      // a1 shifted left 32 lands on a5; shifted back returns
      final a1 = SquareSet.fromSquare(Square(0));
      expect(a1.shl(32).first, Square(32));
      expect(a1.shl(32).shr(32).first, Square(0));
      expect(a1.shl(63).first, Square(63));
      expect(a1.shl(64), SquareSet.empty);
      final h8 = SquareSet.fromSquare(Square(63));
      expect(h8.shr(32).first, Square(31));
      expect(h8.shr(63).first, Square(0));
      expect(h8.shr(64), SquareSet.empty);
      // a shift of 31/33 exercises the non-aligned cross-boundary path
      expect(a1.shl(31).first, Square(31));
      expect(a1.shl(33).first, Square(33));
    });

    test('full set: size, complement and difference', () {
      expect(SquareSet.full.size, 64);
      expect(SquareSet.empty.complement(), SquareSet.full);
      expect(SquareSet.full.complement(), SquareSet.empty);
      expect(SquareSet.full.diff(SquareSet.full), SquareSet.empty);
      expect(SquareSet.lightSquares.size, 32);
      expect(SquareSet.darkSquares.size, 32);
      expect(SquareSet.lightSquares & SquareSet.darkSquares, SquareSet.empty);
      expect(SquareSet.lightSquares | SquareSet.darkSquares, SquareSet.full);
    });

    test('minus borrows across the halves', () {
      // 1 subtracted from the low half of a set whose low half is empty has
      // to borrow from the high half
      final hiOnly = SquareSet.fromSquare(Square(32));
      expect(hiOnly.minus(SquareSet.fromSquare(Square(0))).size, 32);
      expect(SquareSet.full.minus(SquareSet.full), SquareSet.empty);
    });

    test('flips and mirrors are their own inverses', () {
      for (final s in [
        SquareSet.diagonal,
        SquareSet.antidiagonal,
        SquareSet.corners,
        SquareSet.center,
        SquareSet.aFile,
        SquareSet.backranks,
      ]) {
        expect(s.flipVertical().flipVertical(), s);
        expect(s.mirrorHorizontal().mirrorHorizontal(), s);
        expect(s.flipVertical().size, s.size);
      }
      expect(SquareSet.firstRank.flipVertical(), SquareSet.eighthRank);
      expect(SquareSet.aFile.mirrorHorizontal(), SquareSet.hFile);
    });

    test('iteration yields every square once, in order', () {
      expect(SquareSet.full.squares.length, 64);
      expect(SquareSet.full.squares.toList(), List.generate(64, Square.new));
      expect(SquareSet.full.squaresReversed.first, Square(63));
      expect(SquareSet.empty.squares, isEmpty);
      expect(SquareSet.empty.first, isNull);
      expect(SquareSet.empty.last, isNull);
    });
  });
}
