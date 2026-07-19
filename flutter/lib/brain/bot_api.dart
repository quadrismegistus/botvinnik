// Move selection + roster: the shaped bot (Squares), the numeric recipe
// (Fish), repetition avoidance, and the persona list.

import 'js_bridge.dart';
import 'types.dart';

class BotApi {
  final JsBridge _bridge;
  // Not const, unlike its sibling facades: this one memoises SCALE_OFFSET
  // below, and a class that caches is not a constant.
  BotApi(this._bridge);

  /// shapedBotMove — the Squares' miss-the-tactic picker (v4.1 scan model).
  /// Returns the UCI move or null (caller falls back to the top line).
  String? shapedMove({
    required List<EngineMove> lines,
    required int label,
    required String seed,
    required String fen,
    String? lastMoveTo,
  }) {
    return _bridge.call('shapedBotMove', args: [
      lines.map((l) => l.toJson()).toList(),
      label,
      {'scan': true},
      seed,
      fen,
      null,
      lastMoveTo,
    ]) as String?;
  }

  /// The calibrated search depth for a shaped label.
  int shapedSearchDepth(int label) =>
      (_bridge.call('shapedSearchDepth', args: [label]) as num).toInt();

  /// selectBotMove — the Fish personas' softmax sampler over engine lines.
  String? fishMove({
    required List<EngineMove> lines,
    required int internalElo,
    double? alpha,
  }) {
    return _bridge.call('selectBotMove', args: [
      lines.map((l) => l.toJson()).toList(),
      internalElo,
      alpha,
    ]) as String?;
  }

  /// The numeric recipe's mechanism for an internal elo:
  /// {kind: sampler|skill|ucielo, ...} — see botRecipe.ts BotSpec.
  Map<String, dynamic> botSpec(int internalElo) =>
      (_bridge.call('botSpec', args: [internalElo]) as Map).cast<String, dynamic>();

  /// Threefold-shuffle guard: swaps [uci] for a safe alternative if it repeats.
  String avoidRepetition(String uci, List<String> fenHistory, List<EngineMove> lines) {
    return _bridge.call('avoidRepetition', args: [
      uci,
      fenHistory,
      lines.map((l) => l.toJson()).toList(),
    ]) as String;
  }

  /// The Horizon personas' move — js-chess-engine, bundled into brain.js and
  /// run right here in the JS runtime, so this family needs no engine search
  /// at all. Synchronous and ~10ms at levels 1-2. Null means it had nothing
  /// legal (or threw), and the caller should fall back.
  String? horizonMove(String fen, int level) =>
      _bridge.call('horizonMove', args: [fen, level]) as String?;

  /// Display elo + this = the internal WASM scale. Read once: it is a
  /// constant, and the alternative — calling `personaInternalElo` — shipped a
  /// whole persona map across the bridge to read a single field, with a
  /// NaN-to-null failure mode if that field were ever missing.
  late final int _scaleOffset =
      (_bridge.call('SCALE_OFFSET', isProperty: true) as num).toInt();

  /// The persona's strength on the internal WASM scale. Defined for EVERY
  /// family, unlike `numericElo`, which only the fish family carries — so this
  /// is what a fallback search should use.
  int internalElo(Persona p) => p.elo + _scaleOffset;

  /// The roster available on this runtime (native=false: no lc0 sidecar).
  List<Persona> personas() {
    final list = _bridge.call('availablePersonas', args: [false]) as List;
    return list.map((p) => Persona((p as Map).cast<String, dynamic>())).toList();
  }

  Persona? personaById(String id) {
    final p = _bridge.call('personaById', args: [id]);
    return p == null ? null : Persona((p as Map).cast<String, dynamic>());
  }
}
