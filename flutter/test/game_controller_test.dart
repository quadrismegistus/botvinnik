// GameController: the FEN gate behind the New Game sheet, and the state
// machine (undo, redo, browse, start-from-FEN) that undo/browse/FEN bugs live
// in. The state-machine tests run against fake engine deps — see
// support/game_harness.dart.
//
//   cd flutter && flutter test test/game_controller_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/game_controller.dart';

import 'support/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // A K+P vs K endgame: three pieces, so a fall-back to the 32-piece standard
  // start is unmistakable. Kings on the back ranks so the e-pawn is free to
  // move (with the king on e3 it would be blocked — a legal FEN, illegal e2e4).
  const kpk = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';

  group('start from a FEN', () {
    test('newGame(fromFen:) loads the position, not the standard start',
        () async {
      final g = await makeGame(fromFen: kpk);
      expect(g.moves, isEmpty);
      expect(g.position.fen, isNot(kStandardStartFen));
    });

    test('undo after a move returns to the FEN, not the standard start',
        () async {
      final g = await makeGame(fromFen: kpk);
      final start = g.position.fen;
      g.playUci('e2e4');
      expect(g.moves, hasLength(1));
      g.undo();
      expect(g.moves, isEmpty);
      expect(g.position.fen, start);
      expect(g.position.fen, isNot(kStandardStartFen));
    });

    test('browse to the start shows the FEN, not the standard start', () async {
      final g = await makeGame(fromFen: kpk);
      final start = g.position.fen;
      g.playUci('e2e4');
      g.browseTo(0);
      expect(g.browseFen, start);
      expect(g.browseFen, isNot(kStandardStartFen));
    });
  });

  group('undo / redo / browse on a normal game', () {
    test('undo steps back one ply and redo replays it', () async {
      final g = await makeGame();
      final start = g.position.fen;
      g.playUci('e2e4');
      final after1 = g.position.fen;
      g.playUci('e7e5');
      final after2 = g.position.fen;

      g.undo();
      expect(g.position.fen, after1);
      g.undo();
      expect(g.position.fen, start);

      g.redo();
      expect(g.position.fen, after1);
      g.redo();
      expect(g.position.fen, after2);
    });

    test('browse to the start, then back to live', () async {
      final g = await makeGame();
      final start = g.position.fen;
      g.playUci('e2e4');

      g.browseTo(0);
      expect(g.browsing, isTrue);
      expect(g.browseFen, start);

      g.browseLive();
      expect(g.browsing, isFalse);
    });
  });
}
