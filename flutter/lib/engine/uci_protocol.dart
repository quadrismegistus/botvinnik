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
  bool _optionsDirty = false;

  /// Writes one command to the engine (no trailing newline needed).
  void send(String command);

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
    assert(_search == null, 'search while busy — arbiter bug');
    _byMultipv.clear();
    _onUpdate = onUpdate;
    _lastStreamedDepth = 0;
    final completer = Completer<List<EngineMove>>();
    _search = completer;
    if (_optionsDirty && extraOptions.isEmpty) {
      send('setoption name UCI_LimitStrength value false');
      send('setoption name Skill Level value 20');
      _optionsDirty = false;
    }
    for (final opt in extraOptions) {
      send('setoption name ${opt[0]} value ${opt[1]}');
      if (opt[0] != 'MultiPV') _optionsDirty = true;
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
