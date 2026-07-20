// The FEN gate behind the New Game sheet's "start from a position" field:
// what counts as a position we can drop onto an analysis board.
//
//   cd flutter && flutter test test/game_controller_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';

void main() {
  group('isPlayableFen', () {
    test('accepts the standard start and a legal midgame position', () {
      expect(
          GameController.isPlayableFen(
              'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
          isTrue);
      // a bare K+P vs K endgame — unmistakably not the start
      expect(GameController.isPlayableFen('8/8/8/4k3/8/4K3/4P3/8 w - - 0 1'),
          isTrue);
    });

    test('trims surrounding whitespace off a pasted FEN', () {
      expect(
          GameController.isPlayableFen('  8/8/8/4k3/8/4K3/4P3/8 w - - 0 1\n'),
          isTrue);
    });

    test('rejects empty, garbage, and structurally broken input', () {
      expect(GameController.isPlayableFen(''), isFalse);
      expect(GameController.isPlayableFen('not a fen'), isFalse);
      // right shape, impossible board (nine files on a rank)
      expect(
          GameController.isPlayableFen(
              'rnbqkbnrx/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
          isFalse);
    });
  });
}
