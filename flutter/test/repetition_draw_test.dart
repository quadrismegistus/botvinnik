// Rule-forced draws a stateless Position cannot see (#186): threefold
// repetition and the 50-move rule. Both auto-enforced so a bot game does not
// shuffle forever.
//
//   cd flutter && flutter test test/repetition_draw_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'support/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('threefold repetition ends the game as a draw', () async {
    final g = await makeGame(); // analysis: the harness moves both sides
    // Knights out and back, twice: the start position recurs a third time.
    const shuffle = [
      'g1f3', 'g8f6', 'f3g1', 'f6g8', // start position, 2nd time
      'g1f3', 'g8f6', 'f3g1', 'f6g8', // start position, 3rd time
    ];
    for (final uci in shuffle) {
      expect(g.gameOver, isFalse, reason: 'not a draw before the third repeat');
      g.playUci(uci);
    }
    expect(g.gameOver, isTrue);
    expect(g.statusLine, 'Draw by repetition');
    g.dispose();
  });

  test('the 50-move rule ends the game as a draw', () async {
    // 99 half-moves already; one more non-pawn, non-capture move reaches 100.
    // A rook keeps material SUFFICIENT (K+N vs K would already be an
    // insufficient-material draw, which is a different rule).
    final g = await makeGame(fromFen: '4k3/8/8/8/8/8/R7/N3K3 w - - 99 60');
    expect(g.gameOver, isFalse);
    g.playUci('a1b3'); // a knight move — not a repeat; halfmove clock -> 100
    expect(g.gameOver, isTrue);
    expect(g.statusLine, 'Draw — 50-move rule');
    g.dispose();
  });
}
