// The tactics card's Maia sweep (#268): cache discipline, the wipe-epoch
// guard, live-game manners, and the peer mean's refusal to average a partial
// set. All through the .test seams — no bridge, no ONNX; what is under test
// is the STORE's bookkeeping, not Maia's arithmetic.
//
//   cd flutter && flutter test test/vm/maia_tactics_sweep_test.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/stores/maia_tactics_sweep.dart';

import '../support/memory_db.dart';
import '../support/practice_harness.dart';

const _kvKey = 'botvinnik-maia-tactics-v1';
const _ladder = [1500, 1600];

/// A selector answer with [keys] as blitz positions, one occurrence each —
/// shape-faithful to brain/reportTactics.ts's return.
Map<String, dynamic> _tactics(List<String> keys) => {
      'positions': [
        for (final k in keys)
          {'key': k, 'fen': 'fen-$k', 'bestUci': 'a1a2', 'bestSan': 'Ra2', 'cls': 'blitz', 'found': true},
      ],
      'byClass': {
        'blitz': {'n': keys.length, 'found': keys.length, 'noTopGames': 0, 'assistedGames': 0},
        'rapid': {'n': 0, 'found': 0, 'noTopGames': 0, 'assistedGames': 0},
        'classical': {'n': 0, 'found': 0, 'noTopGames': 0, 'assistedGames': 0},
      },
      'games': {
        'considered': 1,
        'humanless': 0,
        'offClass': 0,
        'assisted': 0,
        'noTopMoves': 0
      },
    };

/// The raw is a token — the fake decode never reads it.
final _raw = Maia3Raw(elos: _ladder, policyByElo: const [[]], wdlByElo: const [[]]);

Maia3MoveCurves _curves(Map<String, double> byRung) => Maia3MoveCurves(
      perElo: [
        for (final e in _ladder) Maia3RungCurve(e, {'Ra2': byRung['$e'] ?? 0.5}),
      ],
      wdlByElo: const [],
    );

MaiaTacticsSweep _sweep(
  MemoryDb db, {
  required List<String> keys,
  Future<Maia3Raw?> Function(String fen, List<int> elos)? analyze,
  double p = 0.4,
  bool Function()? isLiveGameActive,
  Listenable? liveGame,
}) {
  final s = MaiaTacticsSweep.test(db,
      isLiveGameActive: isLiveGameActive, liveGame: liveGame)
    ..debugLadder = _ladder
    ..debugTactics = ((_) => _tactics(keys))
    ..debugDecode = ((fen, raw) => _curves({'1500': p, '1600': p}))
    ..debugAnalyze = (analyze ?? (fen, elos) async => _raw);
  return s;
}

void main() {
  test('sweeps every position, caches the curve, persists the document',
      () async {
    final db = MemoryDb();
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1', 'k2'], analyze: (fen, elos) async {
      asked.add(fen);
      expect(elos, _ladder, reason: 'the whole ladder in one batch');
      return _raw;
    });
    await sweep.ensureStarted();

    expect(asked, ['fen-k1', 'fen-k2']);
    expect(sweep.curveFor('k1'), [0.4, 0.4]);
    expect(sweep.coveredOf(['k1', 'k2']), 2);

    final doc = jsonDecode((await db.kvGet(_kvKey))!) as Map;
    expect(doc['v'], MaiaTacticsSweep.kDocVersion);
    expect((doc['curves'] as Map).keys.toSet(), {'k1', 'k2'});
  });

  test('a cached position is never re-inferred — across restarts too',
      () async {
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
          'ladder': _ladder,
          'curves': {
            'k1': [0.9, 0.9]
          },
        }));
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1', 'k2'], analyze: (fen, elos) async {
      asked.add(fen);
      return _raw;
    });
    await sweep.ensureStarted();

    expect(asked, ['fen-k2'], reason: 'k1 came from the persisted document');
    expect(sweep.curveFor('k1'), [0.9, 0.9],
        reason: 'the cached curve is the answer, not a fresh inference');
  });

  test('a document from other weights is discarded whole', () async {
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion + 1,
          'ladder': _ladder,
          'curves': {
            'k1': [0.9, 0.9]
          },
        }));
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1'], analyze: (fen, elos) async {
      asked.add(fen);
      return _raw;
    });
    await sweep.ensureStarted();
    expect(asked, ['fen-k1'],
        reason: 'probabilities are facts about ONE set of weights');
    expect(sweep.curveFor('k1'), [0.4, 0.4]);
  });

  test('a document from another LADDER is discarded whole', () async {
    // The cached arrays are positional per rung; under a changed ladder the
    // same bytes answer a different question — "analysing N of N forever"
    // was the visible symptom, a wrong rung's number under the right label
    // the invisible one (#294 review, both proven).
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
          'ladder': [1400, 1500, 1600],
          'curves': {
            'k1': [0.1, 0.5, 0.9]
          },
        }));
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1'], analyze: (fen, elos) async {
      asked.add(fen);
      return _raw;
    });
    await sweep.ensureStarted();
    expect(asked, ['fen-k1'], reason: 'the old rungs cannot answer the new ones');
    expect(sweep.curveFor('k1'), [0.4, 0.4]);
    final doc = jsonDecode((await db.kvGet(_kvKey))!) as Map;
    expect(doc['ladder'], _ladder, reason: 'the rewritten doc names its rungs');
  });

  test('the reply is looked up by rung, never by position', () async {
    // A transport reply in reversed rung order must not invert the curve
    // (#294 review: bare positional arrays cached 2600's number as 600's).
    final db = MemoryDb();
    final sweep = MaiaTacticsSweep.test(db)
      ..debugLadder = _ladder
      ..debugTactics = ((_) => _tactics(['k1']))
      ..debugAnalyze = ((fen, elos) async => _raw)
      ..debugDecode = ((fen, raw) => Maia3MoveCurves(
            perElo: [
              // reversed: 1600 first
              Maia3RungCurve(1600, const {'Ra2': 0.9}),
              Maia3RungCurve(1500, const {'Ra2': 0.1}),
            ],
            wdlByElo: const [],
          ));
    await sweep.ensureStarted();
    expect(sweep.curveFor('k1'), [0.1, 0.9],
        reason: 'ladder order, whatever order the reply came in');
  });

  test('keys whose games left the archive are pruned from the document',
      () async {
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
          'ladder': _ladder,
          'curves': {
            'gone': [0.9, 0.9],
            'k1': [0.8, 0.8]
          },
        }));
    final sweep = _sweep(db, keys: ['k1']);
    await sweep.ensureStarted();

    expect(sweep.curveFor('gone'), isNull);
    final doc = jsonDecode((await db.kvGet(_kvKey))!) as Map;
    expect((doc['curves'] as Map).keys.toSet(), {'k1'});
  });

  test('a failed cache read aborts the pass and never clobbers the document',
      () async {
    // _loaded latching before a throwing kvGet meant: cache discarded for
    // the process, whole archive re-inferred, and the first checkpoint then
    // OVERWROTE the still-valid document (#294 review, run-proven).
    final db = _FlakyKvDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
          'ladder': _ladder,
          'curves': {
            'k1': [0.9, 0.9]
          },
        }));
    db.failNextGet = true;
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1'], analyze: (fen, elos) async {
      asked.add(fen);
      return _raw;
    });
    await sweep.ensureStarted();
    expect(asked, isEmpty, reason: 'the pass aborts on the failed read');
    final doc = jsonDecode((await db.kvGet(_kvKey))!) as Map;
    expect((doc['curves'] as Map)['k1'], [0.9, 0.9],
        reason: 'the document survives untouched');

    await sweep.ensureStarted(); // the next pass rereads and answers from it
    expect(asked, isEmpty);
    expect(sweep.curveFor('k1'), [0.9, 0.9]);
  });

  test('a wipe mid-sweep stops the pass and writes NOTHING', () async {
    final db = MemoryDb();
    final asked = <String>[];
    late MaiaTacticsSweep sweep;
    sweep = _sweep(db, keys: ['k1', 'k2'], analyze: (fen, elos) async {
      asked.add(fen);
      // The user clears their games while the first inference is in flight —
      // the position list is now a claim about an archive that is gone.
      await db.deleteAllGames();
      return _raw;
    });
    await sweep.ensureStarted();

    expect(asked, ['fen-k1'], reason: 'the epoch check stops the second position');
    expect(await db.kvGet(_kvKey), isNull,
        reason: 'no write may survive the wipe — the resurrection rule (#293)');
  });

  test('a wipe during the LAST inference still blocks the final persist',
      () async {
    // The loop-top check and _persist's own check cover for each other: a
    // wipe during the first position is caught at the next loop top, but a
    // wipe during the last has no next iteration — only the write-time check
    // stands between it and the resurrection. Each guard needs the test the
    // other cannot pass for it.
    final db = MemoryDb();
    final asked = <String>[];
    final sweep = _sweep(db, keys: ['k1'], analyze: (fen, elos) async {
      asked.add(fen);
      await db.deleteAllGames();
      return _raw;
    });
    await sweep.ensureStarted();

    expect(asked, ['fen-k1']);
    expect(await db.kvGet(_kvKey), isNull,
        reason: 'the loop is over; only _persist\'s epoch check can refuse this write');
  });

  test('the pause checkpoints what it has before yielding the machine',
      () async {
    // The pause is for a game that may outlive this process (backgrounded,
    // OS kill) — an unwritten answer is a re-inferred answer (#294 review).
    final db = MemoryDb();
    var live = false;
    final sweep = _sweep(db, keys: ['k1', 'k2'],
        isLiveGameActive: () => live, analyze: (fen, elos) async {
      live = true; // a game starts while k1 runs
      return _raw;
    });
    await sweep.ensureStarted();
    final doc = jsonDecode((await db.kvGet(_kvKey))!) as Map;
    expect((doc['curves'] as Map).keys.toSet(), {'k1'},
        reason: 'k1 was answered and must survive a restart');
  });

  test('a kick during a running pass latches a rerun instead of vanishing',
      () async {
    // The running pass froze its work list at start; a game graded mid-pass
    // (an import, the background grader) must be swept by a follow-up, not
    // wait for the user to reopen the screen (#294 review).
    final db = MemoryDb();
    var keys = ['k1'];
    final started = Completer<void>();
    final gate = Completer<void>();
    final sweep = _sweep(db, keys: [], analyze: (fen, elos) async {
      if (!started.isCompleted) started.complete();
      await gate.future;
      return _raw;
    });
    sweep.debugTactics = (_) => _tactics(keys); // reads the LIVE key list
    final first = sweep.ensureStarted();
    await started.future; // pass 1 is mid-inference on k1
    keys = ['k1', 'k2'];
    unawaited(sweep.ensureStarted()); // the kick that used to be dropped
    gate.complete();
    await first;
    expect(sweep.coveredOf(['k1', 'k2']), 2,
        reason: 'the latched rerun swept the position that arrived mid-pass');
  });

  test('a live game pauses the sweep; its end resumes it', () async {
    final db = MemoryDb();
    final game = ValueNotifier(0); // stands in for the GameController
    var live = false;
    final asked = <String>[];
    final sweep = _sweep(db,
        keys: ['k1', 'k2'],
        isLiveGameActive: () => live,
        liveGame: game, analyze: (fen, elos) async {
      asked.add(fen);
      live = true; // a game starts while k1 runs
      return _raw;
    });
    await sweep.ensureStarted();
    expect(asked, ['fen-k1'],
        reason: 'k2 must wait — inference and a live search fight for CPU');
    expect(sweep.curveFor('k1'), isNotNull,
        reason: 'the finished answer is kept, the pause is not a rollback');

    live = false;
    game.value = 1; // game over — the listener refires the sweep
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(asked, ['fen-k1', 'fen-k2']);
    expect(sweep.coveredOf(['k1', 'k2']), 2);
  });

  test('a failed inference leaves the position uncached for the next sweep',
      () async {
    final db = MemoryDb();
    var attempt = 0;
    final sweep = _sweep(db, keys: ['k1'],
        analyze: (fen, elos) async => ++attempt == 1 ? null : _raw);
    await sweep.ensureStarted();
    expect(sweep.curveFor('k1'), isNull, reason: 'no answer, no cache entry');

    await sweep.ensureStarted();
    expect(sweep.curveFor('k1'), isNotNull, reason: 'the next sweep retries');
  });

  test('a SAN the decoder does not know is a bug surfaced as a gap, never a zero',
      () async {
    final db = MemoryDb();
    final sweep = MaiaTacticsSweep.test(db)
      ..debugLadder = _ladder
      ..debugTactics = ((_) => _tactics(['k1']))
      ..debugAnalyze = ((fen, elos) async => _raw)
      ..debugDecode = ((fen, raw) => Maia3MoveCurves(
            perElo: [
              for (final e in _ladder) Maia3RungCurve(e, const {'Qxf7#': 0.9}),
            ],
            wdlByElo: const [],
          )); // no 'Ra2' key anywhere
    await sweep.ensureStarted();
    expect(sweep.curveFor('k1'), isNull);
    expect(sweep.peerFoundRate(['k1'], 1500), isNull,
        reason: 'a missing move must never average in as "nobody plays it"');
  });

  test('a restart with a fully warm cache can still answer — the ladder must '
      'not depend on inference having run', () async {
    // Real ctor + FakeBridge: the sweep finds nothing to do (every position
    // cached from last session), returns before any inference — and the
    // ladder must resolve on demand in peerFoundRate, or the card sits on
    // "analysing 40 of 40" forever.
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
          'ladder': _ladder,
          'curves': {
            'k1': [0.9, 0.8]
          },
        }));
    final bridge = FakeBridge()
      ..skillReportTacticsResult = _tactics(['k1'])
      ..eloLadderResult = _ladder;
    final sweep = MaiaTacticsSweep(db, bridge, ValueNotifier(0), () => false)
      ..debugAnalyze = ((fen, elos) async => fail('nothing to infer'));
    await sweep.ensureStarted();
    expect(sweep.coveredOf(['k1']), 1);
    expect(sweep.peerFoundRate(['k1'], 1500), 0.9);
  });

  test('a wipe during the SELECTION walk publishes nothing', () async {
    // Selection is chunked across yields, so a wipe can land between games.
    // A half-merged archive published as "your found-rate" is a number about
    // nothing — the pass must abort unpublished and let the resume re-list.
    final db = MemoryDb();
    await db.saveGame({'id': 'g1', 'endedAt': '2026-08-07T00:00:01Z'});
    await db.saveGame({'id': 'g2', 'endedAt': '2026-08-07T00:00:02Z'});
    final bridge = _WipingBridge(db)
      ..skillReportTacticsResult = _tactics(['k1'])
      ..eloLadderResult = _ladder;
    final sweep = MaiaTacticsSweep(db, bridge, ValueNotifier(0), () => false)
      ..debugAnalyze = ((fen, elos) async => _raw);
    await sweep.ensureStarted();

    expect(sweep.tactics, isNull,
        reason: 'one game of two is not the archive');
    expect(sweep.coveredOf(['k1']), 0, reason: 'no inference on fiction');
  });

  test('a game starting during the SELECTION walk also publishes nothing',
      () async {
    // The pause branch is the wipe branch's sibling and needs its own test:
    // returning the half-merged report there survived every other one (#294
    // mutation re-run).
    final db = MemoryDb();
    await db.saveGame({'id': 'g1', 'endedAt': '2026-08-07T00:00:01Z'});
    await db.saveGame({'id': 'g2', 'endedAt': '2026-08-07T00:00:02Z'});
    var live = false;
    final bridge = _LiveFlippingBridge(() => live = true)
      ..skillReportTacticsResult = _tactics(['k1'])
      ..eloLadderResult = _ladder;
    final sweep =
        MaiaTacticsSweep(db, bridge, ValueNotifier(0), () => live)
          ..debugAnalyze = ((fen, elos) async => _raw);
    await sweep.ensureStarted();

    expect(sweep.tactics, isNull,
        reason: 'one game of two is not the archive, paused or wiped alike');
  });

  test('selection walks the archive one game per bridge call and merges',
      () async {
    // The whole-archive selector call was ~19s of synchronous UI freeze at
    // 500 games (#294 review, measured) — the sweep now pays it one game at
    // a time. FakeBridge answers per call, so two saved games must produce
    // two selector calls and a summed report.
    final db = MemoryDb();
    await db.saveGame({'id': 'g1', 'endedAt': '2026-08-07T00:00:01Z'});
    await db.saveGame({'id': 'g2', 'endedAt': '2026-08-07T00:00:02Z'});
    final bridge = FakeBridge()
      ..skillReportTacticsResult = _tactics(['k1'])
      ..eloLadderResult = _ladder;
    final sweep = MaiaTacticsSweep(db, bridge, ValueNotifier(0), () => false)
      ..debugAnalyze = ((fen, elos) async => _raw)
      ..debugDecode = ((fen, raw) => _curves(const {'1500': 0.4, '1600': 0.4}));
    await sweep.ensureStarted();

    final calls =
        bridge.calls.where((c) => c.fn == 'skillReportTactics').toList();
    expect(calls, hasLength(2), reason: 'one selector call per game');
    expect((calls.first.args[0] as List), hasLength(1),
        reason: 'each call carries ONE projected game');
    final tactics = sweep.tactics!;
    expect(tactics['byClass']['blitz']['n'], 2, reason: 'counters sum');
    expect(tactics['games']['considered'], 2);
    expect((tactics['positions'] as List), hasLength(2));
    expect(sweep.coveredOf(['k1']), 1, reason: 'same key: one inference');
  });

  group('peerFoundRate', () {
    test('averages the band rung over occurrences, duplicates included', () {
      final sweep = MaiaTacticsSweep.test(MemoryDb())
        ..debugLadder = _ladder
        ..debugSeed({
          'k1': [0.6, 0.7],
          'k2': [0.2, 0.3],
        });
      // k1 faced twice: (0.6 + 0.6 + 0.2) / 3 — the user side counts the
      // repeat, so the peer side must weight it identically.
      expect(sweep.peerFoundRate(['k1', 'k1', 'k2'], 1500),
          closeTo((0.6 + 0.6 + 0.2) / 3, 1e-9));
      expect(sweep.peerFoundRate(['k1', 'k2'], 1600),
          closeTo((0.7 + 0.3) / 2, 1e-9));
    });

    test('refuses a partial set — a mean over "whatever was swept first" lies',
        () {
      final sweep = MaiaTacticsSweep.test(MemoryDb())
        ..debugLadder = _ladder
        ..debugSeed({
          'k1': [0.6, 0.7]
        });
      expect(sweep.peerFoundRate(['k1', 'k2'], 1500), isNull);
    });

    test('clamps an off-ladder band to the nearest end', () {
      final sweep = MaiaTacticsSweep.test(MemoryDb())
        ..debugLadder = _ladder
        ..debugSeed({
          'k1': [0.6, 0.7]
        });
      expect(sweep.peerFoundRate(['k1'], 300), 0.6);
      expect(sweep.peerFoundRate(['k1'], 3000), 0.7);
    });
  });
}

/// Wipes the archive when the FIRST selector call lands — mid-selection,
/// exactly between two of the sweep's per-game chunks.
class _WipingBridge extends FakeBridge {
  final MemoryDb db;
  bool _wiped = false;
  _WipingBridge(this.db);

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final r = super.call(fn, args: args, isProperty: isProperty);
    if (fn == 'skillReportTactics' && !_wiped) {
      _wiped = true;
      db.wipeEpoch++; // deleteAllGames' synchronous half — the bump
      db.games.clear();
    }
    return r;
  }
}

/// kvGet throws once — sqflite's "database is locked", the web worker's bad
/// day — then recovers.
class _FlakyKvDb extends MemoryDb {
  bool failNextGet = false;

  @override
  Future<String?> kvGet(String key) async {
    if (failNextGet) {
      failNextGet = false;
      throw StateError('database is locked');
    }
    return super.kvGet(key);
  }
}

/// Flips the live-game flag when the FIRST selector call lands.
class _LiveFlippingBridge extends FakeBridge {
  final void Function() onFirstTactics;
  bool _flipped = false;
  _LiveFlippingBridge(this.onFirstTactics);

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final r = super.call(fn, args: args, isProperty: isProperty);
    if (fn == 'skillReportTactics' && !_flipped) {
      _flipped = true;
      onFirstTactics();
    }
    return r;
  }
}
