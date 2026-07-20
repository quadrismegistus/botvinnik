// Retro through a REAL spawned binary on macOS.
//
// A unit test can't reach this: it needs Process.start, a built morlock
// binary bundled inside the sandboxed .app, and the actual UCI round-trip.
// And the failure mode is silent — every error path in RetroEngine returns
// null and the bot falls back to Stockfish — so a broken native retro still
// plays, as somebody else. Only watching a real move come back proves it.
//
// The macOS app is sandboxed, so it can only spawn a binary from inside its
// own bundle. That is exactly what this exercises: the binaries are copied to
// Contents/Resources/retro/ by the "Bundle chess engine" build phase, and
// RetroEngine resolves that bundled path — no external directory, because the
// sandbox would deny it.
//
//   cd flutter && ./stage-macos-engines.sh   # build the binaries once
//   flutter test integration_test/retro_native_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/engine/retro_engine.dart';

/// Every legal move from the initial position, in UCI.
const _opening = {
  'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4', 'd2d3', 'd2d4', //
  'e2e3', 'e2e4', 'f2f3', 'f2f4', 'g2g3', 'g2g4', 'h2h3', 'h2h4', //
  'b1a3', 'b1c3', 'g1f3', 'g1h3',
};
const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('retro is supported here — so the roster picker offers it', () {
    // supported gates on a binary actually being resolvable, so this failing
    // means stage-macos-engines.sh was not run before the build (the binaries
    // never reached Contents/Resources/retro).
    expect(RetroEngine.supported, isTrue,
        reason: 'no retro binary in the bundle — run stage-macos-engines.sh '
            'before the macOS build');
  });

  // engine + its roster ply. One shared binary family; a missing build fails
  // the support check above, a broken one fails here.
  const engines = [
    ('turochamp', 1),
    ('bernstein', 2),
    ('sargon', 1),
  ];

  for (final (engine, ply) in engines) {
    test('$engine plays a legal move through a spawned process', () async {
      final e = RetroEngine(engine, ply);
      final uci = await e.move(_start, movetimeMs: 800);
      e.dispose();
      expect(uci, isNotNull, reason: '$engine returned no move');
      expect(_opening, contains(uci), reason: '$engine played "$uci"');
    });
  }

  test('a second move on the same engine still answers (process reused)',
      () async {
    // The bot plays many moves down one game off one long-lived process; a
    // move after the first must work without a respawn.
    final e = RetroEngine('turochamp', 1);
    final first = await e.move(_start, movetimeMs: 800);
    const afterE4 =
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
    final second = await e.move(afterE4, movetimeMs: 800);
    e.dispose();
    expect(first, isNotNull);
    expect(second, isNotNull, reason: 'second move on a reused process failed');
    expect(second, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
  });

  test('a missing engine binary fails to null (→ Stockfish fallback)',
      () async {
    // The contract every caller relies on: any failure is a null move, which
    // game_controller turns into a Stockfish stand-in — never an exception
    // that wedges the bot's turn. The retro dir resolves, but this engine is
    // not in it.
    final e = RetroEngine('nonesuch', 1);
    expect(await e.move(_start), isNull);
    e.dispose();
  });
}
