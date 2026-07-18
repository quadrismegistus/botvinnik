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

  Map<String, dynamic>? nextItem(List<Map<String, dynamic>> items,
      {String? excludeId, bool easyFirst = false}) {
    // now/motif/rand omitted so the brain's defaults (Date.now, Math.random)
    // engage — a JSON null would poison the date math
    final r = _bridge.call('nextItem', args: [
      items,
      excludeId,
      JsBridge.omit,
      JsBridge.omit,
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
