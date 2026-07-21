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
        return 'medium';
      case 'puzzleSetupMove':
        return null;
      default:
        throw StateError('FakeBridge has no answer for brain.$fn');
    }
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

/// A practice item in the brain's shape. [fen] doubles as the id, as
/// `addItem` makes it. Defaults are due-now and above the 15% serve
/// threshold, so an item counts unless a test says otherwise.
Map<String, dynamic> practiceItem(
  String fen, {
  List<String> motifs = const [],
  double drop = 30,
  String bestUci = 'd2d4',
  String bestSan = 'd4',
  String playedSan = 'a3',
  DateTime? dueAt,
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
    'box': 0,
    'dueAt': due,
    'attempts': 0,
    'correct': 0,
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
