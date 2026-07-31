// Native Stockfish via FFI (stockfish package): the mobile transport.
// One instance per process (package limit) — all scheduling, priorities and
// preemption live in arbiter.dart; the UCI dialogue lives in uci_protocol.dart.
// This class knows only how to move bytes to and from the embedded engine.
//
// The stockfish package supports iOS/Android only. Desktop uses
// process_engine.dart instead; engine_factory.dart picks between them.
//
// NOTE (calibration): this bundles Stockfish 18 full-NNUE, not the WASM
// lite-single the labels were calibrated on — `package:stockfish` 1.8.1,
// whose `misc.cpp` reads `constexpr std::string_view version = "18"`. Three
// places in this repo said 16 until 2026-07-31; they were M1-era comments
// left behind when 1.8.0 moved to 18, and the native grid has since been
// re-measured against this build (brain/bot.ts, SHAPED_KNOTS_SCAN.native).

import 'dart:async';

import 'package:stockfish/stockfish.dart';

import 'uci_protocol.dart';

export 'uci_protocol.dart' show UciSearcher;

class SearchEngine extends UciProtocol {
  final Stockfish _sf;
  late final StreamSubscription<String> _sub;

  SearchEngine._(this._sf) {
    _sub = _sf.stdout.listen(handleLine);
  }

  /// Boots the engine and waits for readiness. Only one instance may exist —
  /// and it does not survive Dart hot restarts (cold-start after engine work).
  static Future<SearchEngine> start() async {
    final sf = Stockfish();
    while (sf.state.value == StockfishState.starting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (sf.state.value != StockfishState.ready) {
      throw StateError('Stockfish failed to start: ${sf.state.value}');
    }
    final engine = SearchEngine._(sf);
    engine.send('uci');
    engine.send('setoption name Threads value 1');
    engine.send('isready');
    return engine;
  }

  @override
  void send(String command) => _sf.stdin = command;

  @override
  void dispose() {
    _sub.cancel();
    _sf.dispose();
  }
}
