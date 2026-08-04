// A PracticeController with fake persistence and a fake JS host, so the
// practice tests run in pure Dart — no device, no embedded runtime.
//
// The bridge fake does two jobs. It ANSWERS like the brain (faithfully enough
// for the selection questions these tests ask), and it RECORDS the argument
// list, which is the only place the null-vs-undefined distinction survives:
// both real hosts hand that list to `buildBrainExpr`, so a test can rebuild
// the exact JavaScript the app would have evaluated.

import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/js_bridge_shared.dart';
import 'package:botvinnik_mobile/brain/practice_api.dart';
import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'game_harness.dart';

typedef BrainCall = ({String fn, List<Object?> args});

/// Stands in for the JS host. `implements` rather than extends because the
/// real JsBridge owns a runtime handle; noSuchMethod covers the rest of its
/// surface (including the private field the two transports keep).
class FakeBridge implements JsBridge {
  final List<BrainCall> calls = [];

  /// Difficulty per item id, for the tests that care which badge a row gets.
  final Map<Object?, String> difficulties = {};

  /// What 'migratePracticeItems' answers. Null (the default) is the brain's
  /// "already in shape"; a test exercising the load-time adoption sets a
  /// replacement list here.
  List<Map<String, dynamic>>? migrateResult;

  /// Makes 'migratePracticeItems' throw the way a real bridge call does on a
  /// JS error — the poisoned-item boot hazard load() must survive.
  bool migrateThrows = false;

  /// Every `nextItem` argument list, in order.
  List<List<Object?>> get nextItemArgs =>
      calls.where((c) => c.fn == 'nextItem').map((c) => c.args).toList();

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    calls.add((fn: fn, args: args));
    switch (fn) {
      case 'nextItem':
        return _nextItem(args);
      case 'removeItem':
        final id = args[1] as String;
        return _items(args[0])
            .where((i) => i['id'] != id)
            .toList(); // brain: items.filter(i => i.id !== id)
      case 'recordResult':
        return _recordResult(args);
      case 'dueCount':
        final now = DateTime.now();
        return _items(args[0]).where((i) => !_dueAt(i).isAfter(now)).length;
      case 'puzzleDifficulty':
        // Not the brain's rule — the brain decides difficulty from attempt
        // history and position features, and copying that here would be one
        // more place for it to drift. What a widget test needs is a per-item
        // answer it chose, so it can tell the badge is routing each row's own
        // item through the brain rather than printing a constant.
        return difficulties[(args[0] as Map)['id']] ?? 'medium';
      case 'masteryStats':
        // The brain's own classification, brain/practice.ts:201.
        var mastered = 0, learning = 0, fresh = 0;
        for (final i in _items(args[0])) {
          if ((i['attempts'] as num) == 0) {
            fresh++;
          } else if ((i['box'] as num) >= 3) {
            mastered++;
          } else {
            learning++;
          }
        }
        return {
          'mastered': mastered,
          'learning': learning,
          'fresh': fresh,
          'total': _items(args[0]).length,
        };
      case 'puzzleSetupMove':
        return null;
      case 'itemDataFromStoredMove':
        // The brain keys a puzzle by the position the move was played FROM;
        // that fen is both id and the dedup key addItem uses. Enough of the
        // stored shape to be a plausible item — the collection tests care about
        // whether it lands, not about the item's full contents.
        final sm = (args[0] as Map).cast<String, dynamic>();
        final fen = sm['fenBefore'] as String?;
        if (fen == null) return null;
        return {
          'id': fen,
          'fen': fen,
          'playedSan': sm['san'],
          'playedUci': sm['uci'],
          'bestSan': sm['bestSan'],
          'bestUci': sm['bestUci'],
          'drop': sm['wcDrop'],
          'depth': sm['depth'],
        };
      case 'addItem':
        // brain: one item per position, a repeat bumps seenCount (#286). The
        // fake keys by fen — identity epd, same divergence as 'epdKeys'.
        final items = _items(args[0]);
        final data = (args[1] as Map).cast<String, dynamic>();
        final at = items.indexWhere((i) => i['id'] == data['fen']);
        if (at < 0) return [...items, data];
        final next = [...items];
        next[at] = {
          ...next[at],
          'seenCount': ((next[at]['seenCount'] as num?) ?? 1) + 1,
        };
        return next;
      case 'addItems':
        return _addItems(args);
      case 'epdKeys':
        // Identity. The real key collapses move counters and dead en-passant
        // squares (brain/practice.ts epdKey, pinned in vitest); no two fixture
        // fens in these tests share a position, so the identity map is
        // faithful for the routing questions the Dart tests ask.
        return (args[0] as List).cast<String>();
      case 'migratePracticeItems':
        if (migrateThrows) {
          throw StateError('brain.migratePracticeItems failed: poisoned item');
        }
        return migrateResult;
      default:
        throw StateError('FakeBridge has no answer for brain.$fn');
    }
  }

  /// Mirrors the bulk form's repeat rules (brain/practice.ts addItems): one
  /// item per position, a repeat bumps seenCount, and a seenKey that already
  /// counted here (the grader's crash-redo) is a no-op. Null when nothing
  /// changed at all.
  List<Map<String, dynamic>>? _addItems(List<Object?> args) {
    var items = _items(args[0]);
    final dataList = (args[1] as List).cast<Map>();
    // The omitted-seenKeys form puts the omit sentinel at args[2], not a
    // list — treat anything that is not a list as "no keys", like the brain.
    final seenKeysArg = args.length > 2 ? args[2] : null;
    final seenKeys = seenKeysArg is List ? seenKeysArg : null;
    var changed = false;
    for (var n = 0; n < dataList.length; n++) {
      final data = dataList[n].cast<String, dynamic>();
      final seenKey = seenKeys == null ? null : seenKeys[n] as String?;
      final at = items.indexWhere((i) => i['id'] == data['fen']);
      if (at < 0) {
        // The real addItems stamps the schedule fields on a fresh item; a
        // fake item without them throws in _dueAt the first time a test
        // serves or counts due, instead of diverging silently.
        final now = DateTime.now().toUtc().toIso8601String();
        items = [
          ...items,
          {
            ...data,
            'createdAt': now,
            'box': 0,
            'dueAt': now,
            'attempts': 0,
            'correct': 0,
            if (seenKey != null) 'seenIn': [seenKey],
          },
        ];
        changed = true;
        continue;
      }
      final seenIn =
          ((items[at]['seenIn'] as List?) ?? const []).cast<String>();
      if (seenKey != null && seenIn.contains(seenKey)) continue;
      final next = [...items];
      next[at] = {
        ...next[at],
        'seenCount': ((next[at]['seenCount'] as num?) ?? 1) + 1,
        if (seenKey != null) 'seenIn': [...seenIn, seenKey],
      };
      items = next;
      changed = true;
    }
    return changed ? items : null;
  }

  /// Mirrors `nextItem` in brain/practice.ts, with one deliberate divergence:
  /// among the due items the brain makes an overdue-weighted random pick, and
  /// this returns the first. These tests are about which items are in the
  /// pool, not about the order they come out of it, and a random answer would
  /// make them flap.
  ///
  /// The motif gate is copied exactly, `if (motif)`: an omitted argument, a
  /// JSON null and an empty string are all falsy in JavaScript and all mean
  /// "no filter". Measured against the shipped bundle rather than assumed —
  /// which is why the marshalling test, not this fake, is what holds the
  /// omit-versus-null line.
  Map<String, dynamic>? _nextItem(List<Object?> args) {
    final items = _items(args[0]);
    final excludeId = args[1];
    final motif = args[3];
    var pool = items.where((i) => i['id'] != excludeId).toList();
    if (motif is String && motif.isNotEmpty) {
      pool = pool
          .where((i) =>
              ((i['motifs'] as List?)?.cast<String>() ?? const [])
                  .contains(motif))
          .toList();
    }
    if (pool.isEmpty) return null;
    final now = DateTime.now();
    final due = pool.where((i) => !_dueAt(i).isAfter(now)).toList();
    if (due.isEmpty) {
      return pool.reduce((a, b) => _dueAt(a).isAfter(_dueAt(b)) ? b : a);
    }
    return due.first;
  }

  /// The brain's Leitner update, with its INTERVAL_DAYS table: a hinted pass
  /// holds the box, a cold pass promotes, a failure resets to 0.
  List<Map<String, dynamic>> _recordResult(List<Object?> args) {
    const intervalDays = [0.007, 1.0, 3.0, 7.0, 21.0];
    final id = args[1] as String;
    final pass = args[2] as bool;
    final hinted = args[3] as bool;
    return _items(args[0]).map((i) {
      if (i['id'] != id) return i;
      final box = pass
          ? (hinted ? i['box'] as int : ((i['box'] as int) + 1).clamp(0, 4))
          : 0;
      return {
        ...i,
        'box': box,
        'dueAt': DateTime.now()
            .toUtc()
            .add(Duration(
                milliseconds: (intervalDays[box] * 86400000).round()))
            .toIso8601String(),
        'attempts': (i['attempts'] as int) + 1,
        'correct': (i['correct'] as int) + (pass ? 1 : 0),
        'lastResult': pass ? 'pass' : 'fail',
      };
    }).toList();
  }

  List<Map<String, dynamic>> _items(Object? raw) =>
      (raw as List).cast<Map<String, dynamic>>();

  DateTime _dueAt(Map<String, dynamic> i) =>
      DateTime.parse(i['dueAt'] as String);

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// In-memory kv, so `_persist` runs for real without sqflite.
class FakeDb implements AppDb {
  final Map<String, String> kv = {};

  @override
  Future<String?> kvGet(String key) async => kv[key];

  @override
  Future<void> kvPut(String key, String value) async => kv[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A practice item in the brain's shape. [fen] doubles as the id — the fake
/// bridge keys by fen where the brain keys by epdKey(fen); faithful here
/// because no two fixture fens share a position (the collapse itself is
/// pinned in brain/practice.test.ts). Defaults are due-now and above the 15%
/// serve threshold, so an item counts unless a test says otherwise.
Map<String, dynamic> practiceItem(
  String fen, {
  List<String> motifs = const [],
  double drop = 30,
  String bestUci = 'd2d4',
  String bestSan = 'd4',
  String playedSan = 'a3',
  DateTime? dueAt,
  int box = 0,
  int attempts = 0,
  int correct = 0,
  String? lastResult,
  int? seenCount,
}) {
  final due = (dueAt ?? DateTime.now().subtract(const Duration(minutes: 5)))
      .toUtc()
      .toIso8601String();
  return {
    'id': fen,
    'fen': fen,
    'playedSan': playedSan,
    'playedUci': 'a2a3',
    'bestSan': bestSan,
    'bestUci': bestUci,
    'bestPv': [bestUci],
    'motifs': motifs,
    'tagV': 4,
    'evalBestPawns': 0.4,
    'mateBest': null,
    'wcBest': 60.0,
    'drop': drop,
    'depth': 22,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'box': box,
    'dueAt': due,
    'attempts': attempts,
    'correct': correct,
    'lastResult': ?lastResult,
    'seenCount': ?seenCount,
  };
}

/// A controller holding [items], already loaded. By default the arbiter's
/// searches never resolve, so nothing reaches a verdict; pass one built with
/// `searchLines` to drive `checkAttempt` through to an attempt.
({PracticeController practice, FakeBridge bridge, FakeDb db}) makePractice(
    List<Map<String, dynamic>> items,
    {SearchArbiter? arbiter}) {
  final bridge = FakeBridge();
  final db = FakeDb();
  final practice = PracticeController(
      db, PracticeApi(bridge), FakeGrading(), arbiter ?? FakeArbiter());
  practice.items = items;
  practice.loaded = true;
  return (practice: practice, bridge: bridge, db: db);
}

/// The JavaScript the real hosts would have evaluated for a recorded call —
/// the same `buildBrainExpr` both js_bridge_io and js_bridge_web use, so an
/// assertion on this string is an assertion about what the brain receives.
String brainExprFor(BrainCall call) =>
    buildBrainExpr(call.fn, call.args, false);
