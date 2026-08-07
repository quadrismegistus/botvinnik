// The tactics card's Maia sweep (#268): cache discipline, the wipe-epoch
// guard, live-game manners, and the peer mean's refusal to average a partial
// set. All through the .test seams — no bridge, no ONNX; what is under test
// is the STORE's bookkeeping, not Maia's arithmetic.
//
//   cd flutter && flutter test test/vm/maia_tactics_sweep_test.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/stores/maia_tactics_sweep.dart';

import '../support/memory_db.dart';
import '../support/practice_harness.dart';

const _kvKey = 'botvinnik-maia-tactics-v1';
const _ladder = [1500, 1600];

/// A selector answer with [keys] as blitz positions, one occurrence each.
/// The fen doubles as the SAN seed so [_decoderFor] can hand each position
/// its own probabilities.
Map<String, dynamic> _tactics(List<String> keys) => {
      'positions': [
        for (final k in keys)
          {'key': k, 'fen': 'fen-$k', 'bestUci': 'a1a2', 'bestSan': 'Ra2', 'cls': 'blitz', 'found': true},
      ],
      'byClass': {
        'blitz': {'n': keys.length, 'found': keys.length},
        'rapid': {'n': 0, 'found': 0},
        'classical': {'n': 0, 'found': 0},
      },
      'games': {'considered': 1, 'humanless': 0, 'offClass': 0, 'noTopMoves': 0},
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

  test('keys whose games left the archive are pruned from the document',
      () async {
    final db = MemoryDb();
    await db.kvPut(
        _kvKey,
        jsonEncode({
          'v': MaiaTacticsSweep.kDocVersion,
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
