// Practice scheduling: the brain's pure Leitner/selection functions.
// Dart owns persistence (the kv table); every call passes the item array in
// and stores whatever comes back — the same whole-array-in/out contract the
// web has with localStorage.

import 'js_bridge.dart';

class PracticeApi {
  final JsBridge _bridge;
  const PracticeApi(this._bridge);

  /// StoredMove → item data (null when the move can't make a puzzle).
  Map<String, dynamic>? itemData(Map<String, dynamic> storedMove,
      [String? setupUci]) {
    final r = _bridge.call('itemDataFromStoredMove', args: [storedMove, setupUci]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  /// Returns the new items array, or null when the fen is already collected.
  List<Map<String, dynamic>>? addItem(
      List<Map<String, dynamic>> items, Map<String, dynamic> data) {
    final r = _bridge.call('addItem', args: [items, data]);
    return r == null ? null : _castItems(r);
  }

  List<Map<String, dynamic>> removeItem(
          List<Map<String, dynamic>> items, String id) =>
      _castItems(_bridge.call('removeItem', args: [items, id]));

  /// [motif] restricts the pool to items tagged with it (the brain's `motifs`
  /// list); null draws from everything.
  Map<String, dynamic>? nextItem(List<Map<String, dynamic>> items,
      {String? excludeId, String? motif, bool easyFirst = false}) {
    // now/rand omitted so the brain's defaults (Date.now, Math.random) engage
    // — a JSON null would poison the date math. Measured against the shipped
    // bundle (node, assets/brain.js): null for `rand` throws outright ("rand2
    // is not a function"), and null for `now` makes every
    // `Date.parse(dueAt) <= now` false, so nothing is ever due and it quietly
    // serves the soonest item instead of a weighted pick among the due ones.
    //
    // `motif` is the same slot discipline for a different reason. The brain
    // gates on `if (motif)`, so a null there is harmless TODAY — measured, 300
    // draws, same two-item spread as undefined. But `undefined` is what "no
    // argument" means at this boundary, the omission is what the parameter
    // default is written for, and the day that gate becomes `!== undefined` a
    // null would silently empty the queue. The guard for this is in
    // practice_motif_test, at the marshalling layer, because that is the only
    // layer where null and undefined differ.
    final r = _bridge.call('nextItem', args: [
      items,
      excludeId,
      JsBridge.omit,
      motif ?? JsBridge.omit,
      JsBridge.omit,
      easyFirst,
    ]);
    return r == null ? null : (r as Map).cast<String, dynamic>();
  }

  List<Map<String, dynamic>> recordResult(
          List<Map<String, dynamic>> items, String id, bool pass,
          {bool hinted = false}) =>
      _castItems(_bridge.call('recordResult', args: [items, id, pass, hinted]));

  int dueCount(List<Map<String, dynamic>> items) =>
      (_bridge.call('dueCount', args: [items]) as num).toInt();

  String? puzzleSetupMove(Map<String, dynamic> item) =>
      _bridge.call('puzzleSetupMove', args: [item]) as String?;

  String puzzleDifficulty(Map<String, dynamic> item) =>
      _bridge.call('puzzleDifficulty', args: [item]) as String;

  List<Map<String, dynamic>> _castItems(dynamic r) => (r as List)
      .map((i) => (i as Map).cast<String, dynamic>())
      .toList();
}
