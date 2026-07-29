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

  /// The last snapshot handed to [_onUpdate] — one complete iteration, by
  /// construction. Kept so [_resolvedLines] has something coherent to resolve
  /// with when the search is stopped part-way through the next one.
  List<EngineMove> _lastStreamedLines = const [];
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
        // Stream a snapshot once per COMPLETED depth. This comment has always
        // said that; until 2026-07-29 the condition below did not implement
        // it. `depth > _lastStreamedDepth` first becomes true on the multipv-1
        // line of a new iteration — the FIRST line of it — at which point
        // lines 2..N still hold the previous iteration's values. Every
        // streamed snapshot was therefore `[line1@D, lines2..N@D-1]`, and
        // stayed that way until the next depth opened, because the rest of
        // this depth's lines update the map without re-streaming.
        //
        // A mixed snapshot is not merely stale. Anything that SUBTRACTS two of
        // these lines is comparing different searches: refuse-blunders reads
        // `bestEval` off line 1 and the played move's eval off line 2..N (see
        // GameController._maybeRefuse), so one iteration of drift lands
        // directly on a human's move. Worst case is line 1 flipping to a mate
        // at depth D while the alternatives sit at D-1: a flat 100 against
        // whatever they say, which is a refusal manufactured out of the gap.
        //
        // The test is the invariant ITSELF — every line now at this depth —
        // rather than a proxy for it. An earlier version counted multipv
        // indices instead, learning the ceiling by watching (a position with
        // three legal moves never emits a line 5) and adding an escape hatch
        // so that a ceiling which never rose again could not stall the stream
        // forever. Both were wrong, and wrong in the direction that matters:
        // the ceiling was per-engine state needing a per-search reset that no
        // test covered, and the hatch fired on the FIRST line of a depth, so
        // the thing it emitted was a mixed snapshot — this bug, produced by
        // the code meant to prevent a different one. It also fired on a plain
        // skipped depth, where nothing was wrong at all.
        //
        // Checking uniformity directly needs no ceiling, no reset and no
        // hatch, and it holds however the engine orders or numbers its lines.
        //
        // KNOWN LIMITATION, accepted with eyes open: an engine that reports
        // five lines and then permanently four leaves the fifth entry stale,
        // so the map never becomes uniform again and the stream stops for the
        // rest of that search. No engine in the catalogue was shown to do
        // this. The failure is frozen-but-COHERENT — consumers keep the last
        // good snapshot, the depth floor rejects it as it ages, and nothing
        // downstream is fed two depths to subtract. That is strictly better
        // than the hatch, which stayed live by emitting exactly what this
        // file exists to stop emitting.
        //
        // The cost is not only staleness, and this is the part worth knowing
        // before anyone calls it harmless: [SearchArbiter]'s courtesy window
        // is consulted ONLY from the stream callback, so a stalled stream
        // never closes it. A cancelled analysis that would have yielded the
        // engine at [kMinUsefulDepth] instead runs its whole budget —
        // [kAnalysisMovetimeMs], or depth 22 — and nothing preempts it,
        // because analysis-versus-analysis is equal priority. That is the
        // per-ply backlog `cancelAnalyses` exists to prevent, at up to 10s a
        // ply rather than about 3. Same trigger: an engine whose per-iteration
        // line count permanently drops, which nothing in the catalogue does.
        // For a healthy engine the courtesy stop simply lands one iteration
        // later, and yields a real depth-12 snapshot instead of a mixed one.
        if (_onUpdate != null &&
            depth > _lastStreamedDepth &&
            _byMultipv.values.every((l) => l.depth == depth)) {
          _lastStreamedDepth = depth;
          _lastStreamedLines = _sorted();
          _onUpdate!(_lastStreamedLines);
        }
      }
    } else if (line.startsWith('bestmove')) {
      final moves = _resolvedLines();
      _onUpdate = null;
      _search?.complete(moves);
      _search = null;
    }
  }

  List<EngineMove> _sorted() => _byMultipv.values.toList()
    ..sort((a, b) => a.multipv.compareTo(b.multipv));

  /// What a search RESOLVES with, as opposed to what it streams.
  ///
  /// Streaming was fixed to emit only complete iterations; the resolution was
  /// not, and it is the half that reaches grading — a settled analysis is
  /// preferred over a partial precisely because it finished. But a search that
  /// ends on the movetime backstop ends mid-iteration, leaving `_byMultipv`
  /// holding line 1 at depth D beside the rest at D-1: the same mixed list,
  /// arriving by the other door. Observed shape, with a stop after line 1 of
  /// depth 4: depths `[4, 3, 3]`, scores `[9.0, 0.02, 0.03]` — a top line that
  /// looks nine pawns better than alternatives it was never compared against.
  ///
  /// So prefer the last complete iteration whenever the map is mid-iteration.
  /// It is one ply shallower and it is COMPARABLE, which is the trade anything
  /// that subtracts two of these lines needs. A single-line search (MultiPV 1,
  /// which is the bot's and the refusal check's own shape) has nothing to be
  /// incoherent with and keeps its deepest answer.
  List<EngineMove> _resolvedLines() {
    final all = _sorted();
    if (all.length < 2) return all;
    final depth = all.first.depth;
    if (all.every((l) => l.depth == depth)) return all;
    // ...but never at the cost of CANDIDATES. Before the first iteration
    // completes, the last streamed snapshot can be a single line while the map
    // already holds several — handing that back would collapse a bot's choice
    // set (MultiPV 12) to one move and make it play the top line every time.
    // Coherence is worth one ply of depth; it is not worth the alternatives.
    // What survives here incoherent is refused by the one caller that
    // subtracts these numbers — see GameController._oneIteration, which treats
    // lines it cannot compare as no lines at all.
    return _lastStreamedLines.length >= all.length ? _lastStreamedLines : all;
  }

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
    _lastStreamedLines = const [];
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
