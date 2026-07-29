// The order of the three UCI commands that ask a retro engine to move.
//
// Worth a test of its own because the failure it guards against is invisible
// from Dart: drop `ucinewgame` and morlock's driver ends the engine on the
// second identical position, after which the client simply never hears back
// and quietly plays a Stockfish stand-in for the rest of the game. Nothing
// throws, no test goes red, and the bot keeps making moves — as somebody else.
//
//   cd flutter && flutter test test/retro_commands_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/engine/retro_commands.dart';

void main() {
  const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  test('asks for a move with ucinewgame, position, go — in that order', () {
    expect(retroMoveCommands(fen, 500), [
      'ucinewgame',
      'position fen $fen',
      'go movetime 500',
    ]);
  });

  test('ucinewgame comes BEFORE the position, not after', () {
    // The whole point: it resets the driver's lastPosition, which only helps
    // if the driver sees it first. Reversed, the position line still takes the
    // continuation branch and an identical one still ends the engine.
    final cmds = retroMoveCommands(fen, 500);
    expect(cmds.indexOf('ucinewgame'),
        lessThan(cmds.indexWhere((c) => c.startsWith('position'))));
  });

  test('every request carries it, so a repeat cannot slip through', () {
    // The bug needed only two identical position lines. If any request omitted
    // ucinewgame, two of THOSE in a row would be enough.
    for (var i = 0; i < 3; i++) {
      expect(retroMoveCommands(fen, 500).first, 'ucinewgame');
    }
  });
}
