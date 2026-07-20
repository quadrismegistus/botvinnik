// Maia through the REAL native path on macOS: package:onnxruntime over FFI,
// the weights pulled from HuggingFace to Application Support, and the encode/
// decode running in an embedded JavaScriptCore.
//
// A unit test cannot reach any of that, and every failure path in MaiaEngine
// returns null — so a broken native Maia still plays, as Stockfish wearing the
// persona's name. Only watching real moves come back proves it.
//
// The moves below are the NODE reference (ort-web + the same brain/maia/
// sources), emitted by `npx tsx scripts/emit-maia-parity.mts`. They are the
// point of the test: asserting merely that the move is legal would pass on an
// encoding that flipped the board, read the wrong band, or dropped the history
// planes. They are inlined rather than shipped as an asset because they are
// twelve lines that change only when a net does, and because an asset would
// have to be loaded through the very bundle path under test.
//
//   cd flutter && flutter test integration_test/maia_native_test.dart -d macos
//
// First run downloads ~10MB (three bands). Later runs are cached.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:botvinnik_mobile/engine/maia_engine.dart';
import 'package:botvinnik_mobile/engine/maia_progress.dart';

/// (band, fenHistory, the move the web plays).
const _parity = <(int, List<String>, String)>[
  (1100, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'], 'e2e4'), // start
  (1100, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'], 'e7e5'), // after 1.e4, with history
  (1100, ['r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 5 4'], 'g8f6'), // italian, no history
  (1100, ['r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P1b1/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 6 8'], 'a7a6'), // black to move, midgame
  (1500, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'], 'e2e4'), // start
  (1500, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'], 'e7e5'), // after 1.e4, with history
  (1500, ['r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 5 4'], 'g8f6'), // italian, no history
  (1500, ['r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P1b1/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 6 8'], 'c6d4'), // black to move, midgame
  (1900, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'], 'e2e4'), // start
  (1900, ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'], 'c7c5'), // after 1.e4, with history
  (1900, ['r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 5 4'], 'g8f6'), // italian, no history
  (1900, ['r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P1b1/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 6 8'], 'a7a6'), // black to move, midgame
];

/// Checkmate: no legal move, so no inference and no download.
const _mated = '7k/5KQ1/8/8/8/8/8/8 b - - 0 1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MaiaEngine maia;
  setUpAll(() => maia = MaiaEngine());
  tearDownAll(() => maia.dispose());

  test('is offered on this platform', () {
    expect(MaiaEngine.supported, isTrue);
  });

  for (final (band, history, expected) in _parity) {
    test('maia-$band matches the web on ${history.last}', () async {
      expect(await maia.move(history, band: band), expected);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('a mated position asks the net nothing', () async {
    expect(await maia.move([_mated], band: 1100), isNull);
  });

  test('sampling stays inside the legal moves', () async {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    const legal = {
      'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4', 'd2d3', 'd2d4', //
      'e2e3', 'e2e4', 'f2f3', 'f2f4', 'g2g3', 'g2g4', 'h2h3', 'h2h4',
      'b1a3', 'b1c3', 'g1f3', 'g1h3',
    };
    for (var i = 0; i < 5; i++) {
      final uci = await maia.move([start], band: 1100, temperature: 1);
      expect(legal, contains(uci));
    }
  });

  test('a request cancelled before it starts resolves null', () async {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final abandoned = maia.move([start], band: 1100);
    maia.cancelPending();
    expect(await abandoned, isNull);
  });

  // The one above never gets past the generation check, so it says nothing
  // about work already running. This is the case that matters: a download in
  // flight, cancelled — the move must resolve null, the weights must still
  // land (they are cached per band, so finishing is right), and the progress
  // line must keep reporting for whoever is waiting next rather than going
  // blank because the generation that started it is stale.
  test('a cancel mid-download still lands the weights, and keeps reporting',
      () async {
    const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final dir = await getApplicationSupportDirectory();
    final cached = File('${dir.path}/maia/maia-1500.onnx');
    if (await cached.exists()) await cached.delete();

    final seen = <MaiaProgress>[];
    final fresh = MaiaEngine(onProgress: (p) {
      if (p != null) seen.add(p);
    });
    final abandoned = fresh.move([start], band: 1500);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    fresh.cancelPending();

    expect(await abandoned, isNull, reason: 'cancelled requests answer null');
    expect(seen.any((p) => p.phase == 'fetching'), isTrue,
        reason: 'the download reported while someone was waiting');
    expect(await fresh.move([start], band: 1500), 'e2e4',
        reason: 'the abandoned download still cached its weights');
    fresh.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
