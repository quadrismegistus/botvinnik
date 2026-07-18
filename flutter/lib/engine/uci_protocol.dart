// The UCI dialogue, independent of how bytes reach the engine.
//
// Two transports implement it: the FFI-embedded Stockfish on iOS/Android
// (search_engine.dart) and a spawned engine process on desktop
// (process_engine.dart). Everything about *what* to say to an engine and how
// to read its answers lives here, so the two can never drift apart.

import 'dart:async';

import '../brain/types.dart';

/// The arbiter's view of an engine — real (either transport) or a test fake.
abstract interface class UciSearcher {
  bool get busy;
  Future<List<EngineMove>> search(
    String fen, {
    required String go,
    required int multiPv,
    List<List<String>> extraOptions,
    void Function(List<EngineMove>)? onUpdate,
  });
  void stop();
  void dispose();
}

/// Shared UCI protocol handling. Subclasses supply only [send] (write one
/// command to the engine) and [dispose], and feed received lines to
/// [handleLine].
abstract class UciProtocol implements UciSearcher {
  final Map<int, EngineMove> _byMultipv = {};
  Completer<List<EngineMove>>? _search;
  void Function(List<EngineMove>)? _onUpdate;
  int _lastStreamedDepth = 0;
  int _currentMultiPv = 0;

  /// Weakening options applied by the last search. Anything in here that the
  /// NEXT search doesn't set again has to be reset explicitly: two weakened
  /// searches in a row would otherwise union their options. Leaving
  /// UCI_LimitStrength on makes Skill Level inert in Stockfish, so a skill
  /// persona would silently play at the previous persona's Elo.
  final Set<String> _appliedOptions = {};
  static const Map<String, String> _optionDefaults = {
    'UCI_LimitStrength': 'false',
    'Skill Level': '20',
    'UCI_Elo': '1320',
  };

  /// Writes one command to the engine (no trailing newline needed).
  void send(String command);

  /// Fail the in-flight search. Transports call this when the engine dies:
  /// without it the completer is never resolved, the arbiter's `_running`
  /// never clears, and every later search queues behind a ghost forever.
  /// The arbiter catches the error, drops the request and pumps the next.
  /// For transports only.
  void failSearch(Object error) {
    final pending = _search;
    _search = null;
    _onUpdate = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  /// Feed every line the engine emits to this.
  void handleLine(String line) {
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
        // stream a snapshot once per completed depth (the last multipv line
        // of a depth is the highest index we asked for, or multipv 1 when
        // the position has fewer legal moves)
        if (_onUpdate != null && depth > _lastStreamedDepth) {
          _lastStreamedDepth = depth;
          _onUpdate!(_sorted());
        }
      }
    } else if (line.startsWith('bestmove')) {
      final moves = _sorted();
      _onUpdate = null;
      _search?.complete(moves);
      _search = null;
    }
  }

  List<EngineMove> _sorted() => _byMultipv.values.toList()
    ..sort((a, b) => a.multipv.compareTo(b.multipv));

  @override
  bool get busy => _search != null;

  /// One MultiPV search. Resolves on bestmove — including after [stop], with
  /// whatever depth was reached. The arbiter guarantees no overlap.
  ///
  /// [go] is the raw go command tail ('depth 22' or 'movetime 1200' — the
  /// recipe decides). [extraOptions] are weakening options (Skill Level,
  /// UCI_Elo…); they are automatically reset before the next plain search.
  @override
  Future<List<EngineMove>> search(
    String fen, {
    required String go,
    required int multiPv,
    List<List<String>> extraOptions = const [],
    void Function(List<EngineMove>)? onUpdate,
  }) {
    // in release an assert is stripped, and overwriting _search would orphan
    // the previous completer — a silent, permanent arbiter deadlock. Fail it.
    if (_search != null) {
      failSearch(StateError('search while busy — arbiter bug'));
    }
    _byMultipv.clear();
    _onUpdate = onUpdate;
    _lastStreamedDepth = 0;
    final completer = Completer<List<EngineMove>>();
    _search = completer;
    final incoming = {
      for (final opt in extraOptions)
        if (opt[0] != 'MultiPV') opt[0]
    };
    for (final stale in _appliedOptions.difference(incoming)) {
      send('setoption name $stale value ${_optionDefaults[stale] ?? "0"}');
    }
    _appliedOptions
      ..clear()
      ..addAll(incoming);
    for (final opt in extraOptions) {
      send('setoption name ${opt[0]} value ${opt[1]}');
      // MultiPV via extraOptions would desync the cache below
      if (opt[0] == 'MultiPV') _currentMultiPv = int.tryParse(opt[1]) ?? -1;
    }
    if (multiPv != _currentMultiPv) {
      send('setoption name MultiPV value $multiPv');
      _currentMultiPv = multiPv;
    }
    send('position fen $fen');
    send('go $go');
    return completer.future;
  }

  /// Ends the running search early; its future still resolves on bestmove.
  @override
  void stop() {
    if (_search != null) send('stop');
  }
}
