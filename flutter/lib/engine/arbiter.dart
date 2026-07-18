// The search arbiter: one native engine, many clients. Strictly one search
// in flight; requests queue by priority (botMove > practiceCheck > analysis).
// A higher-priority arrival preempts the running search via UCI `stop` — the
// preempted request goes back in the queue and re-runs from scratch (the
// engine's transposition table makes the re-search cheap), so every caller
// sees exactly one future that resolves with a full-budget result or null
// when the request went stale (generation bumped by new-game/undo).
//
// Budgets mirror the web (stockfish.ts): analysis = depth 22 OR 3000 ms,
// whichever first, MultiPV 5. Bot moves = shapedSearchDepth(label) at
// MultiPV 12, no time cap (depths 4-12 finish in well under a second).

import 'dart:async';
import 'dart:collection';

import '../brain/types.dart';
import 'search_engine.dart';

enum SearchPriority { botMove, practiceCheck, analysis }

/// Web-app analysis budget (stockfish.ts DEFAULT_BUDGET + MULTIPV).
const int kAnalysisDepth = 22;
const int kAnalysisMovetimeMs = 3000;
const int kAnalysisMultiPv = 5;
const int kBotMultiPv = 12;

class _Request {
  final String fen;
  final int depth; // 0 = movetime-only search (no depth target)
  final int multiPv;
  final int? movetimeMs;
  final List<List<String>> extraOptions;
  final SearchPriority priority;
  final int generation;
  final void Function(List<EngineMove>)? onUpdate; // streamed partials
  final Completer<List<EngineMove>?> completer = Completer();
  bool cancelled = false; // resolve with partials, don't re-run

  _Request({
    required this.fen,
    required this.depth,
    required this.multiPv,
    required this.movetimeMs,
    this.extraOptions = const [],
    required this.priority,
    required this.generation,
    this.onUpdate,
  });

  String get goCommand =>
      depth > 0 ? 'depth $depth' : 'movetime ${movetimeMs ?? 1000}';
}

class SearchArbiter {
  final SearchEngine _engine;
  final Queue<_Request> _queue = Queue();
  _Request? _running;
  Timer? _budgetTimer;
  bool _preempting = false;
  int _generation = 0;
  int _runningStreamDepth = 0;
  // a cancelled analysis is allowed to reach this depth before stopping, so
  // the move it would have labeled still gets its backfill
  static const int _kMinUsefulDepth = 12;
  int? _stopAtDepth;

  SearchArbiter(this._engine);

  /// The board moved on: analyses of positions other than [exceptFen] are
  /// history. Queued ones resolve null; a running one is stopped as soon as
  /// it has streamed enough to be useful (depth 12), resolving with its
  /// partial lines. This is the web's only-analyze-the-current-position
  /// semantic — without it a fast game builds a 3s-per-ply backlog.
  void cancelAnalyses({required String exceptFen}) {
    final keep = <_Request>[];
    for (final r in _queue) {
      if (r.priority == SearchPriority.analysis && r.fen != exceptFen) {
        if (!r.completer.isCompleted) r.completer.complete(null);
      } else {
        keep.add(r);
      }
    }
    _queue
      ..clear()
      ..addAll(keep);
    final running = _running;
    if (running != null &&
        running.priority == SearchPriority.analysis &&
        running.fen != exceptFen &&
        !running.cancelled) {
      running.cancelled = true;
      if (_runningStreamDepth >= _kMinUsefulDepth) {
        _engine.stop();
      } else {
        _stopAtDepth = _kMinUsefulDepth; // stop once it gets there
      }
    }
  }

  int get generation => _generation;

  /// Invalidate all queued and in-flight work (new game, undo, mode switch).
  void bumpGeneration() {
    _generation++;
    for (final r in _queue) {
      r.completer.complete(null);
    }
    _queue.clear();
    if (_running != null) _engine.stop();
  }

  /// Enqueue a search. Resolves null if the request goes stale before or
  /// while running. Callers treat null as "forget this ply".
  Future<List<EngineMove>?> search({
    required String fen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) {
    final req = _Request(
      fen: fen,
      depth: depth,
      multiPv: multiPv,
      movetimeMs: movetimeMs,
      extraOptions: extraOptions,
      priority: priority,
      generation: _generation,
      onUpdate: onUpdate,
    );
    _enqueue(req);
    _pump();
    return req.completer.future;
  }

  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      search(
        fen: fen,
        depth: kAnalysisDepth,
        multiPv: kAnalysisMultiPv,
        movetimeMs: kAnalysisMovetimeMs,
        priority: SearchPriority.analysis,
        onUpdate: onUpdate,
      );

  void _enqueue(_Request req) {
    // stable insert: after the last request of equal-or-higher priority
    final list = _queue.toList();
    var i = list.length;
    while (i > 0 && list[i - 1].priority.index > req.priority.index) {
      i--;
    }
    list.insert(i, req);
    _queue
      ..clear()
      ..addAll(list);
    // preempt a running lower-priority search; it re-queues itself in _run
    final running = _running;
    if (running != null &&
        !_preempting &&
        req.priority.index < running.priority.index) {
      _preempting = true;
      _engine.stop();
    }
  }

  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    final req = _queue.removeFirst();
    if (req.generation != _generation) {
      if (!req.completer.isCompleted) req.completer.complete(null);
      _pump();
      return;
    }
    _running = req;
    _run(req);
  }

  Future<void> _run(_Request req) async {
    // movetime with a depth target = budget cap enforced Dart-side;
    // movetime with depth 0 = the engine's own movetime go
    if (req.movetimeMs != null && req.depth > 0) {
      _budgetTimer = Timer(Duration(milliseconds: req.movetimeMs!), _engine.stop);
    }
    _runningStreamDepth = 0;
    _stopAtDepth = null;
    void onStream(List<EngineMove> lines) {
      _runningStreamDepth = lines.isEmpty ? 0 : lines.first.depth;
      if (_stopAtDepth != null && _runningStreamDepth >= _stopAtDepth!) {
        _stopAtDepth = null;
        _engine.stop();
      }
      if (req.generation == _generation) req.onUpdate?.call(lines);
    }

    List<EngineMove> lines;
    try {
      lines = await _engine.search(
        req.fen,
        go: req.goCommand,
        multiPv: req.multiPv,
        extraOptions: req.extraOptions,
        onUpdate: onStream,
      );
    } catch (e) {
      _budgetTimer?.cancel();
      _running = null;
      if (!req.completer.isCompleted) req.completer.completeError(e);
      _pump();
      return;
    }
    _budgetTimer?.cancel();
    _budgetTimer = null;
    final wasPreempted = _preempting;
    _preempting = false;
    _running = null;

    final reachedTarget =
        lines.isNotEmpty && lines.first.depth >= req.depth;
    if (req.generation != _generation) {
      if (!req.completer.isCompleted) req.completer.complete(null);
    } else if (req.cancelled) {
      // the board moved on — partial lines are all this position gets
      req.completer.complete(lines);
    } else if (wasPreempted && !reachedTarget) {
      // interrupted by a higher-priority request before reaching its budget:
      // run again later from scratch (warm TT makes this cheap), same future
      _enqueue(req);
    } else {
      req.completer.complete(lines);
    }
    _pump();
  }

  void dispose() {
    _budgetTimer?.cancel();
    bumpGeneration();
    _engine.dispose();
  }
}
