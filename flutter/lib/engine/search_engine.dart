// Native Stockfish via FFI (stockfish package): the raw UCI transport.
// One instance per process (package limit) — all scheduling, priorities and
// preemption live in arbiter.dart; this class knows only how to run one
// search and parse its lines.
//
// NOTE (calibration): this bundles Stockfish 16 full-NNUE, not the WASM
// lite-single the labels were calibrated on. Accepted for M1; the M4
// calibration pass re-measures the gym curve against this build.

import 'dart:async';

import 'package:stockfish/stockfish.dart';

import '../brain/types.dart';

class SearchEngine {
  final Stockfish _sf;
  final Map<int, EngineMove> _byMultipv = {};
  Completer<List<EngineMove>>? _search;
  late final StreamSubscription<String> _sub;
  int _currentMultiPv = 0;

  SearchEngine._(this._sf) {
    _sub = _sf.stdout.listen(_onLine);
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
    sf.stdin = 'uci';
    sf.stdin = 'setoption name Threads value 1';
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
        _byMultipv[multipv] = EngineMove(
          pv: pv,
          score: cp != null ? int.parse(cp) / 100.0 : 0.0,
          mate: mate != null ? int.parse(mate) : null,
          depth: depth,
          multipv: multipv,
        );
      }
    } else if (line.startsWith('bestmove')) {
      final moves = _byMultipv.values.toList()
        ..sort((a, b) => a.multipv.compareTo(b.multipv));
      _search?.complete(moves);
      _search = null;
    }
  }

  bool get busy => _search != null;
  bool _optionsDirty = false;

  /// One MultiPV search. Resolves on bestmove — including after [stop], with
  /// whatever depth was reached. The arbiter guarantees no overlap.
  ///
  /// [go] is the raw go command tail ('depth 22' or 'movetime 1200' — the
  /// recipe decides). [extraOptions] are weakening options (Skill Level,
  /// UCI_Elo…); they are automatically reset before the next plain search.
  Future<List<EngineMove>> search(
    String fen, {
    required String go,
    required int multiPv,
    List<List<String>> extraOptions = const [],
  }) {
    assert(_search == null, 'search while busy — arbiter bug');
    _byMultipv.clear();
    final completer = Completer<List<EngineMove>>();
    _search = completer;
    if (_optionsDirty && extraOptions.isEmpty) {
      _sf.stdin = 'setoption name UCI_LimitStrength value false';
      _sf.stdin = 'setoption name Skill Level value 20';
      _optionsDirty = false;
    }
    for (final opt in extraOptions) {
      _sf.stdin = 'setoption name ${opt[0]} value ${opt[1]}';
      if (opt[0] != 'MultiPV') _optionsDirty = true;
    }
    if (multiPv != _currentMultiPv) {
      _sf.stdin = 'setoption name MultiPV value $multiPv';
      _currentMultiPv = multiPv;
    }
    _sf.stdin = 'position fen $fen';
    _sf.stdin = 'go $go';
    return completer.future;
  }

  /// Ends the running search early; its future still resolves on bestmove.
  void stop() {
    if (_search != null) _sf.stdin = 'stop';
  }

  void dispose() {
    _sub.cancel();
    _sf.dispose();
  }
}
