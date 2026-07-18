// Native Stockfish via FFI (stockfish package): the MultiPV-12 search that
// feeds the shaping layer — same role the WASM lite-single engine plays on
// the web. Spike-grade UCI line parsing, mirroring squarefish-uci.mts.
//
// NOTE (calibration): this bundles Stockfish 16 full-NNUE, not the WASM
// lite-single the labels were calibrated on. Fine for a spike; a real port
// re-runs the gym curve against this build before trusting labels.

import 'dart:async';

import 'package:stockfish/stockfish.dart';

class SearchEngine {
  final Stockfish _sf;
  final Map<int, Map<String, dynamic>> _byMultipv = {};
  Completer<List<Map<String, dynamic>>>? _search;
  late final StreamSubscription<String> _sub;

  SearchEngine._(this._sf) {
    _sub = _sf.stdout.listen(_onLine);
  }

  /// Boots the engine and waits for readiness. Only one instance may exist.
  static Future<SearchEngine> start() async {
    final sf = Stockfish();
    // the package exposes state as a ValueListenable; poll until ready
    while (sf.state.value == StockfishState.starting) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (sf.state.value != StockfishState.ready) {
      throw StateError('Stockfish failed to start: ${sf.state.value}');
    }
    final engine = SearchEngine._(sf);
    sf.stdin = 'uci';
    sf.stdin = 'setoption name Threads value 1';
    sf.stdin = 'setoption name MultiPV value 12';
    sf.stdin = 'isready';
    return engine;
  }

  void _onLine(String line) {
    if (line.startsWith('info ') && line.contains(' pv ')) {
      final depth =
          int.tryParse(RegExp(r' depth (\d+)').firstMatch(line)?.group(1) ?? '') ?? 0;
      final multipv =
          int.tryParse(RegExp(r' multipv (\d+)').firstMatch(line)?.group(1) ?? '') ?? 1;
      final cp = RegExp(r' score cp (-?\d+)').firstMatch(line)?.group(1);
      final mate = RegExp(r' score mate (-?\d+)').firstMatch(line)?.group(1);
      final pv = line.split(' pv ').last.trim().split(' ');
      if (pv.isNotEmpty && pv.first.isNotEmpty) {
        _byMultipv[multipv] = {
          'pv': pv,
          'score': cp != null ? int.parse(cp) / 100.0 : 0.0,
          'mate': mate != null ? int.parse(mate) : null,
          'depth': depth,
          'multipv': multipv,
        };
      }
    } else if (line.startsWith('bestmove')) {
      final moves = _byMultipv.values.toList()
        ..sort((a, b) => (a['multipv'] as int).compareTo(b['multipv'] as int));
      _search?.complete(moves);
      _search = null;
    }
  }

  /// MultiPV search at [depth]; resolves on bestmove with all lines.
  Future<List<Map<String, dynamic>>> search(String fen, int depth) {
    _byMultipv.clear();
    final completer = Completer<List<Map<String, dynamic>>>();
    _search = completer;
    _sf.stdin = 'position fen $fen';
    _sf.stdin = 'go depth $depth';
    return completer.future.timeout(const Duration(seconds: 30));
  }

  void dispose() {
    _sub.cancel();
    _sf.dispose();
  }
}
