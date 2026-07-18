import 'package:dartchess/dartchess.dart';
import 'package:test/test.dart';

void main() {
  test('implements hashCode/==', () {
    expect(Board.empty, Board.empty);
    expect(Board.standard, Board.standard);
    expect(Board.empty, isNot(Board.standard));
    expect(Board.standard, isNot(Board.empty));
    expect(Board.parseFen(kInitialBoardFEN), Board.standard);
  });

  test('empty board', () {
    expect(Board.empty.pieces.isEmpty, true);
    expect(Board.empty.pieceAt(Square.a1), null);
  });

  test('standard board', () {
    expect(Board.standard.pieces.length, 32);
  });

  test('setPieceAt', () {
    const piece = Piece.whiteKing;
    final board = Board.empty.setPieceAt(Square.a1, piece);
    expect(board.occupied, const SquareSet.fromHiLo(0x00000000, 0x00000001));
    expect(board.pieces.length, 1);
    expect(board.pieceAt(Square.a1), piece);

    final board2 = Board.standard.setPieceAt(Square.e8, piece);
    expect(board2.pieceAt(Square.e8), piece);
    expect(board2.white, const SquareSet.fromHiLo(0x10000000, 0x0000ffff));

    expect(board2.black, const SquareSet.fromHiLo(0xefff0000, 0x00000000));
    expect(board2.pawns, const SquareSet.fromHiLo(0x00ff0000, 0x0000ff00));
    expect(board2.knights, const SquareSet.fromHiLo(0x42000000, 0x00000042));
    expect(board2.bishops, const SquareSet.fromHiLo(0x24000000, 0x00000024));
    expect(board2.rooks, SquareSet.corners);
    expect(board2.queens, const SquareSet.fromHiLo(0x08000000, 0x00000008));
    expect(board2.kings, const SquareSet.fromHiLo(0x10000000, 0x00000010));
  });

  test('removePieceAt', () {
    final board = Board.empty.setPieceAt(Square.c2, Piece.whiteKing);
    expect(board.removePieceAt(Square.c2), Board.empty);
  });

  test('parse board fen', () {
    final board = Board.parseFen(kInitialBoardFEN);
    expect(board, Board.standard);
  });

  test('parse board fen, promoted piece', () {
    final board =
        Board.parseFen('rQ~q1kb1r/pp2pppp/2p5/8/3P1Bb1/4PN2/PPP3PP/R2QKB1R');
    expect(board.promoted.squares.length, 1);
  });

  test('invalid board fen', () {
    expect(
        () => Board.parseFen('4k2r/8/8/8/8/RR2K2R'),
        throwsA(predicate(
            (e) => e is FenException && e.cause == IllegalFenCause.board)));

    expect(() => Board.parseFen('lol'),
        throwsA(const TypeMatcher<FenException>()));
  });

  test('make board fen', () {
    expect(Board.empty.fen, kEmptyBoardFEN);
    expect(Board.standard.fen, kInitialBoardFEN);
  });
}
