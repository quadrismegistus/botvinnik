// The material maths behind the board plates, ported from the Svelte
// MaterialBar — ports drift, so pin what "captured" and "+N" mean.
//
//   cd flutter && flutter test test/player_plate_test.dart

import 'package:dartchess/dartchess.dart' show Role;
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/ui/player_plate.dart';

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  test('the start position is level and nothing is captured', () {
    for (final side in ['w', 'b']) {
      final m = PlayerPlate.materialFor(_start, side);
      expect(m.advantage, 0);
      expect(m.captured, isEmpty);
    }
  });

  test('a side up a queen shows +9 and the captured queen', () {
    // black is missing its queen (d8 empty)
    const fen = 'rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final white = PlayerPlate.materialFor(fen, 'w');
    expect(white.advantage, 9);
    expect(white.captured[Role.queen], 1);
    // the other side is behind, so it reports no advantage (not -9)
    final black = PlayerPlate.materialFor(fen, 'b');
    expect(black.advantage, 0);
    expect(black.captured, isEmpty);
  });

  test('rooks are worth five, and multiple captures count', () {
    // white is missing both rooks (a1, h1 empty); black is whole
    const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NBQKBN1 w kq - 0 1';
    final black = PlayerPlate.materialFor(fen, 'b');
    expect(black.advantage, 10); // two rooks
    expect(black.captured[Role.rook], 2);
  });

  test('a pawn-for-knight trade is a net −2 for the side down the knight', () {
    // white missing a knight (b1), black missing a pawn (a7)
    const fen = 'rnbqkbnr/1ppppppp/8/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1';
    // white took a pawn (+1), black took a knight (+3): white is −2, black +2
    expect(PlayerPlate.materialFor(fen, 'w').advantage, 0);
    final black = PlayerPlate.materialFor(fen, 'b');
    expect(black.advantage, 2);
    expect(black.captured[Role.knight], 1);
    expect(PlayerPlate.materialFor(fen, 'w').captured[Role.pawn], 1);
  });
}
