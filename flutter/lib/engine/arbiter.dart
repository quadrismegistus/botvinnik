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
import 'uci_protocol.dart';

// Ordered by urgency. threatProbe outranks analysis: it is a ~500ms search
// whose result is an overlay the player is waiting to see, while analysis is
// a 3s search that streams and backfills. Behind analysis it arrived seconds
// late; ahead of it, it preempts, runs, and analysis resumes where it left.
enum SearchPriority { botMove, practiceCheck, threatProbe, analysis }

/// Work that belongs to one board position, and is pointless once the board
/// moves on. Both kinds are dropped by [SearchArbiter.cancelAnalyses].
bool _positionScoped(SearchPriority p) =>
    p == SearchPriority.analysis || p == SearchPriority.threatProbe;

/// Web-app analysis budget (stockfish.ts DEFAULT_BUDGET + MULTIPV).
const int kAnalysisDepth = 22;

/// A BACKSTOP for pathological positions, not a routine truncator.
///
/// At 3000ms it was the latter. Measured in a real browser on the app's own
/// engine (SF18 lite-single, MultiPV 5), time to reach depth 22:
///
///   start position   3755ms      open middlegame  5954ms (7437ms to finish)
///   complex midgame  4180ms      pawn endgame     2010ms
///
/// So three of four positions were being cut off around depth 19-21 — the
/// arrows were never showing the depth they advertised. MultiPV 5 is what
/// costs this: five principal variations prune far less than one.
///
/// Raising it is nearly free HERE and would not be on the web. Flutter ranks
/// threatProbe and botMove ABOVE analysis and preempts, so a long analysis
/// yields the moment anything else needs the engine; the web's single-slot
/// queue runs its threat probe only after analysis settles, so the same change
/// there would delay every threat arrow by the same amount.
///
/// The remaining cost is CPU while you think — which is why this stays a cap.
/// Must remain comfortably under [kSaveGradeWaitSeconds]; see there.
const int kAnalysisMovetimeMs = 10000;
const int kAnalysisMultiPv = 5;
const int kBotMultiPv = 12;

class _Request {
  final String fen;

  /// The board position this request serves, when that differs from the fen
  /// being searched — the threat probe searches a null-move position, but is
  /// stale exactly when the REAL position it was asked about is gone.
  final String? ownerFen;
  String get scopeFen => ownerFen ?? fen;
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
    this.ownerFen,
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
  /// The engine, once it exists. Taken as a FUTURE so boot does not wait on
  /// it: on the web that is a 7MB WASM download plus a UCI handshake, and it
  /// used to sit on the critical path in front of the first frame — 17.3MB
  /// before anything was drawn, which is 16s on fast 4G. Now the board appears
  /// and searches queue here until the engine answers.
  ///
  /// [_ready] is the awaitable; [_engine] is the resolved value, null until
  /// then. Every synchronous `stop()` site uses the nullable one, which is
  /// safe: nothing can be running before the first search, and the first
  /// search cannot start before this resolves.
  final Future<UciSearcher> _ready;
  UciSearcher? _engine;
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

  SearchArbiter(this._ready) {
    // cache the resolved engine for the synchronous stop() paths. The error
    // arm is swallowed HERE only — a boot failure still surfaces where it can
    // be handled, at the `await _ready` in _run.
    _ready.then((e) {
      _engine = e;
    }, onError: (Object _) {});
  }

  /// The board moved on: analyses of positions other than [exceptFen] are
  /// history. Queued ones resolve null; a running one is stopped as soon as
  /// it has streamed enough to be useful (depth 12), resolving with its
  /// partial lines. This is the web's only-analyze-the-current-position
  /// semantic — without it a fast game builds a 3s-per-ply backlog.
  void cancelAnalyses({required String exceptFen}) {
    final keep = <_Request>[];
    for (final r in _queue) {
      if (_positionScoped(r.priority) && r.scopeFen != exceptFen) {
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
        _positionScoped(running.priority) &&
        running.scopeFen != exceptFen &&
        !running.cancelled) {
      running.cancelled = true;
      // the courtesy window exists so grading still gets usable lines; a
      // threat probe has nothing to salvage, so it just stops
      if (running.priority != SearchPriority.analysis ||
          _runningStreamDepth >= _kMinUsefulDepth) {
        _engine?.stop();
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
    if (_running != null) _engine?.stop();
  }

  /// Enqueue a search. Resolves null if the request goes stale before or
  /// while running. Callers treat null as "forget this ply".
  Future<List<EngineMove>?> search({
    required String fen,
    String? ownerFen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) {
    final req = _Request(
      fen: fen,
      ownerFen: ownerFen,
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

  void _enqueue(_Request req, {bool front = false}) {
    // stable insert: after the last request of equal-or-higher priority —
    // or, for a preempted re-run, BEFORE its class (it's the freshest work)
    final list = _queue.toList();
    var i = list.length;
    while (i > 0 &&
        (front
            ? list[i - 1].priority.index >= req.priority.index
            : list[i - 1].priority.index > req.priority.index)) {
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
      _engine?.stop();
    }
  }

  bool _waitingForEngine = false;
  Object? _engineError;

  /// The engine will never arrive. Resolve pending work as NULL, not as an
  /// error: null is the contract every caller already handles ("forget this
  /// ply"), and completing with an error instead turned a dead engine into
  /// unhandled async exceptions from five fire-and-forget call sites, plus a
  /// Practice tab wedged with `checking` stuck true. The failure is surfaced
  /// through [engineError] rather than thrown at people who cannot act on it.
  void _failAll() {
    final pending = _queue.toList();
    _queue.clear();
    for (final r in pending) {
      if (!r.completer.isCompleted) r.completer.complete(null);
    }
  }

  /// Why the engine never started, if it didn't. Null while it is still
  /// loading AND once it is up — callers show it rather than guess why every
  /// search comes back empty.
  Object? get engineError => _engineError;

  void _pump() {
    if (_running != null || _queue.isEmpty) return;
    // Requests may arrive before the engine finishes loading — boot no longer
    // waits for it. Hold them in the queue rather than marking one running:
    // that keeps "running implies a search is in flight", which every stop()
    // and preemption path depends on. Without it a higher-priority arrival
    // during the load window silently lost its preemption.
    if (_engine == null) {
      if (_engineError != null) return _failAll();
      if (!_waitingForEngine) {
        _waitingForEngine = true;
        _ready.then((_) {
          _waitingForEngine = false;
          _pump();
        }, onError: (Object e) {
          // Boot used to await the engine, so a failure showed the boot-error
          // screen. Now it does not — and swallowing this left every search
          // queued forever, which looks like a hung app rather than a broken
          // engine. Resolve them null and record why, so the UI can say so.
          _waitingForEngine = false;
          _engineError = e;
          _failAll();
        });
      }
      return;
    }
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
      _budgetTimer =
          Timer(Duration(milliseconds: req.movetimeMs!), () => _engine?.stop());
    }
    _runningStreamDepth = 0;
    _stopAtDepth = null;
    void onStream(List<EngineMove> lines) {
      _runningStreamDepth = lines.isEmpty ? 0 : lines.first.depth;
      if (_stopAtDepth != null && _runningStreamDepth >= _stopAtDepth!) {
        _stopAtDepth = null;
        _engine?.stop();
      }
      if (req.generation == _generation) req.onUpdate?.call(lines);
    }

    List<EngineMove> lines;
    try {
      lines = await _engine!.search(
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
      // run again from scratch (warm TT makes this cheap), same future,
      // ahead of anything else in its class
      _enqueue(req, front: true);
    } else {
      req.completer.complete(lines);
    }
    _pump();
  }

  void dispose() {
    _budgetTimer?.cancel();
    bumpGeneration();
    _engine?.dispose();
  }
}
