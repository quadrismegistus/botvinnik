// The arbiter's scheduling contract, tested against a fake engine whose
// timing the test controls. Every behavior here was load-bearing in a real
// bug at some point today: priority preemption, re-enqueue after early stop,
// generation staleness, and cancelAnalyses' depth-12 courtesy window.
//
//   cd flutter && flutter test

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/engine/uci_protocol.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart' show kSaveGradeWaitSeconds;

EngineMove line(String uci, {double score = 0.3, int depth = 12, int mpv = 1}) =>
    EngineMove(pv: [uci], score: score, mate: null, depth: depth, multipv: mpv);

/// One in-flight fake search, finished by the test.
class FakeSearch {
  final String fen;
  final String go;
  final void Function(List<EngineMove>)? onUpdate;
  final Completer<List<EngineMove>> completer = Completer();
  bool stopped = false;
  FakeSearch(this.fen, this.go, this.onUpdate);

  void stream(List<EngineMove> lines) => onUpdate?.call(lines);
  void finish(List<EngineMove> lines) => completer.complete(lines);
}

class FakeEngine implements UciSearcher {
  final List<FakeSearch> searches = [];
  FakeSearch get current => searches.last;

  @override
  bool get busy =>
      searches.isNotEmpty && !searches.last.completer.isCompleted;

  @override
  Future<List<EngineMove>> search(
    String fen, {
    required String go,
    required int multiPv,
    List<List<String>> extraOptions = const [],
    void Function(List<EngineMove>)? onUpdate,
  }) {
    final s = FakeSearch(fen, go, onUpdate);
    searches.add(s);
    return s.completer.future;
  }

  @override
  void stop() => current.stopped = true;

  @override
  void dispose() {}
}

Future<void> tick() => Future.delayed(Duration.zero);

void main() {
  _budgets();
  _lateEngine();
  late FakeEngine engine;
  late SearchArbiter arbiter;

  setUp(() {
    engine = FakeEngine();
    // the arbiter takes a FUTURE engine so boot need not wait on it; an
    // already-resolved one keeps these tests synchronous
    arbiter = SearchArbiter(Future.value(engine));
  });

  test('one search in flight; queue drains in priority order', () async {
    final a = arbiter.analysis('fenA');
    final b = arbiter.analysis('fenB');
    final bot = arbiter.search(
        fen: 'fenBot', depth: 6, multiPv: 12, priority: SearchPriority.botMove);
    await tick();

    // only A is running; the bot request preempted it (stop signal sent)
    expect(engine.searches.length, 1);
    expect(engine.current.stopped, isTrue);

    // A ends early at depth 5 → re-enqueued (didn't reach its target)
    engine.current.finish([line('e2e4', depth: 5)]);
    await tick();
    // bot runs next (highest priority)
    expect(engine.searches.length, 2);
    expect(engine.current.fen, 'fenBot');
    engine.current.finish([line('g8f6', depth: 6)]);
    final botLines = await bot;
    expect(botLines!.first.uci, 'g8f6');

    // then A re-runs (before B — it kept its place in the analysis class)
    await tick();
    expect(engine.current.fen, 'fenA');
    engine.current.finish([line('e2e4', depth: 22)]);
    expect((await a)!.first.depth, 22);

    await tick();
    expect(engine.current.fen, 'fenB');
    engine.current.finish([line('d2d4', depth: 22)]);
    expect((await b)!.first.uci, 'd2d4');
  });

  test('preempted search that already reached its target completes', () async {
    final a = arbiter.search(
        fen: 'fenA', depth: 10, multiPv: 5, priority: SearchPriority.analysis);
    await tick();
    arbiter.search(
        fen: 'fenBot', depth: 6, multiPv: 12, priority: SearchPriority.botMove);
    await tick();
    expect(engine.current.stopped, isTrue);
    // it got to depth 11 before the stop landed — no re-run needed
    engine.current.finish([line('e2e4', depth: 11)]);
    expect((await a)!.first.depth, 11);
  });

  test('bumpGeneration voids queued and running work', () async {
    final running = arbiter.analysis('fenA');
    final queued = arbiter.analysis('fenB');
    await tick();
    arbiter.bumpGeneration();
    expect(await queued, isNull); // queued: voided immediately
    engine.current.finish([line('e2e4', depth: 22)]);
    expect(await running, isNull); // running: result discarded
  });

  test('cancelAnalyses: queued die, running gets its depth-12 courtesy',
      () async {
    final running = arbiter.analysis('old1');
    final queued = arbiter.analysis('old2');
    final kept = arbiter.analysis('current');
    await tick();

    // running old1 has only streamed depth 8 — not yet stopped, marked
    engine.current.stream([line('e2e4', depth: 8)]);
    arbiter.cancelAnalyses(exceptFen: 'current');
    expect(await queued, isNull);
    expect(engine.current.stopped, isFalse); // below the courtesy depth

    // …the moment it streams depth 12, the arbiter stops it
    engine.current.stream([line('e2e4', depth: 12)]);
    expect(engine.current.stopped, isTrue);
    engine.current.finish([line('e2e4', depth: 12)]);
    // cancelled-but-ran resolves with its partial lines, no re-run
    expect((await running)!.first.depth, 12);

    // the kept fen still runs to completion
    await tick();
    expect(engine.current.fen, 'current');
    engine.current.finish([line('d2d4', depth: 22)]);
    expect((await kept)!.first.uci, 'd2d4');
  });

  test('threat probe preempts a running analysis, which then resumes',
      () async {
    final analysis = arbiter.analysis('fenA');
    await tick();
    expect(engine.current.fen, 'fenA');

    // the probe searches a null-move fen but belongs to the board position
    final threat = arbiter.search(
        fen: 'fenA-nullmove',
        ownerFen: 'fenA',
        depth: 14,
        multiPv: 1,
        movetimeMs: 500,
        priority: SearchPriority.threatProbe);
    await tick();
    expect(engine.current.stopped, isTrue); // analysis got out of the way

    engine.current.finish([line('e2e4', depth: 9)]);
    await tick();
    expect(engine.current.fen, 'fenA-nullmove'); // probe runs next
    engine.current.finish([line('d7d5', depth: 14)]);
    expect((await threat)!.first.uci, 'd7d5');

    // the preempted analysis re-runs rather than being lost
    await tick();
    expect(engine.current.fen, 'fenA');
    engine.current.finish([line('g1f3', depth: 22)]);
    expect((await analysis)!.first.uci, 'g1f3');
  });

  test('a queued threat probe is stale when its BOARD position is gone',
      () async {
    // a bot search holds the engine so both probes are genuinely queued
    final bot = arbiter.search(
        fen: 'fenBot', depth: 6, multiPv: 12, priority: SearchPriority.botMove);
    await tick();
    final threat = arbiter.search(
        fen: 'old-nullmove',
        ownerFen: 'old',
        depth: 14,
        multiPv: 1,
        priority: SearchPriority.threatProbe);
    final kept = arbiter.search(
        fen: 'current-nullmove',
        ownerFen: 'current',
        depth: 14,
        multiPv: 1,
        priority: SearchPriority.threatProbe);

    // matched on the position it serves, not the fen it searches
    arbiter.cancelAnalyses(exceptFen: 'current');
    expect(await threat, isNull);

    engine.current.finish([line('e2e4', depth: 6)]);
    expect((await bot)!.first.uci, 'e2e4');
    await tick();
    expect(engine.current.fen, 'current-nullmove'); // the fresh probe survived
    engine.current.finish([line('e7e5', depth: 14)]);
    expect((await kept)!.first.uci, 'e7e5');
  });

  test('streamed updates reach the caller; stale generations are muted',
      () async {
    final got = <int>[];
    arbiter.search(
      fen: 'fenA',
      depth: 22,
      multiPv: 5,
      priority: SearchPriority.analysis,
      onUpdate: (lines) => got.add(lines.first.depth),
    );
    await tick();
    engine.current.stream([line('e2e4', depth: 9)]);
    engine.current.stream([line('e2e4', depth: 10)]);
    arbiter.bumpGeneration();
    engine.current.stream([line('e2e4', depth: 11)]); // stale: dropped
    expect(got, [9, 10]);
  });
}

// Appended: budget invariants. These are constants rather than behaviour, but
// getting the relationship wrong fails SILENTLY — a game archives without its
// closing labels because a timeout fired, which no other test would notice.
// Boot no longer waits for the engine (main.dart passes startEngine() without
// awaiting), so requests can arrive before it exists. Getting this wrong is
// silent: the first attempt marked a request "running" during the load window,
// which crashed on a stop for a search that had never started; the second
// guarded the stop and thereby DROPPED the preemption instead.
void _lateEngine() {
  group('engine that is not ready yet', () {
    test('queues work, then runs it in priority order once it arrives',
        () async {
      final gate = Completer<UciSearcher>();
      final engine = FakeEngine();
      final arbiter = SearchArbiter(gate.future);

      arbiter.analysis('fenA');
      arbiter.search(
          fen: 'fenBot',
          depth: 6,
          multiPv: 12,
          priority: SearchPriority.botMove);
      await tick();

      // nothing may be in flight before the engine exists
      expect(engine.searches, isEmpty);

      gate.complete(engine);
      await tick();

      // the bot request outranks the analysis and must go first — the
      // preemption that arrived during the wait cannot be lost
      expect(engine.searches.length, 1);
      expect(engine.current.fen, 'fenBot');
    });

    test('an engine that never boots does not wedge the queue', () async {
      final gate = Completer<UciSearcher>();
      final arbiter = SearchArbiter(gate.future);
      // attach the expectation BEFORE the failure is delivered, or the error
      // is briefly unhandled and the zone fails the test for it
      final expectation =
          expectLater(arbiter.analysis('fenA'), throwsA(isA<StateError>()));
      await tick();
      gate.completeError(StateError('no engine'));
      // the failure surfaces to the caller rather than hanging forever
      await expectation;
    });
  });
}

void _budgets() {
  group('analysis budget', () {
    test('the save wait outlives the analysis it waits on', () {
      // a grade pipeline awaits the analysis of the position after its move,
      // so the slowest grade cannot land before the slowest analysis
      expect(kSaveGradeWaitSeconds * 1000, greaterThan(kAnalysisMovetimeMs),
          reason: 'finishing a game mid-search would drop its last labels');
      expect(kSaveGradeWaitSeconds * 1000 - kAnalysisMovetimeMs,
          greaterThanOrEqualTo(4000),
          reason: 'leave margin for the grade work either side of the search');
    });

    test('the movetime is a backstop, not the routine limit', () {
      // measured worst case to finish depth 22 at MultiPV 5 on the app engine
      // (SF18 lite-single, real browser): 7437ms. Under that and the cap is
      // truncating ordinary positions again, which is what it was doing at
      // 3000ms — the arrows never reached the depth they advertised.
      expect(kAnalysisMovetimeMs, greaterThanOrEqualTo(8000));
    });
  });
}
