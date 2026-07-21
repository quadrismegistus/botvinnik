// The LinesTree graph: a game-long exploration map. The played path runs
// through the middle; the engine's alternatives branch off every position
// visited, colored by how good they were. A position's analysis REPLACES its
// previous suggestion churn (anchor pruning) and past positions keep only
// their first branching move — the roads not taken stay, their deep
// continuations don't. Direct port of LinesTree.svelte's mergeAndLayout.

import 'dart:math';

import '../brain/chess_api.dart';
import '../brain/types.dart';

class TreeNode {
  final String id;
  final int depth;
  final String san;
  final String color; // 'w' | 'b'
  double x = 0, y = 0;
  TreeNode(this.id, this.depth, this.san, this.color);
}

class TreeLink {
  final String source;
  final String target;
  double cp; // White-perspective pawns
  double pctBest; // 0..100 vs the position's best move
  String? uci; // set on first moves out of their anchor
  String anchor;
  TreeLink(this.source, this.target,
      {required this.cp,
      required this.pctBest,
      this.uci,
      required this.anchor});
}

// phone-scaled geometry (web: 104/62/24)
const double kPlyW = 88;
const double kNodeW = 56;
const double kNodeH = 22;
const double kPadTop = 12;
const double kPadBottom = 12;
const double kPadLeft = 24;
const String kRoot = '(root)';

class LinesTreeModel {
  final ChessApi _chess;
  LinesTreeModel(this._chess);

  final Map<String, TreeNode> nodes = {};
  final Map<String, TreeLink> links = {};
  Set<String> liveKeys = {};
  Set<String> pathKeys = {};
  String? bestNodeId;
  String anchorId = kRoot;
  int _lastPathLen = 0;
  int version = 0;

  // ---- blind mode ----
  //
  // One place, because the tree gives the engine away three separate ways: the
  // links out of the current position, the green ring on the best node, and the
  // nodes themselves. Gating them independently in the painter is how the first
  // attempt shipped with the links hidden and the nodes still drawn.

  /// A link that is the engine's opinion about the CURRENT position, rather
  /// than part of the game's own history.
  bool isLiveHint(String key) {
    final l = links[key];
    return l != null &&
        liveKeys.contains(key) &&
        !pathKeys.contains(key) &&
        l.anchor == anchorId;
  }

  /// The node to ring green, or null while blind — the best move is the single
  /// most valuable thing blind mode exists to withhold.
  String? visibleBestNodeId({required bool blind}) => blind ? null : bestNodeId;

  /// Which nodes may be drawn.
  ///
  /// Hiding only the LINKS is not enough: a node IS its move name, so an
  /// engine suggestion left on screen without a curve attached is still the
  /// suggestion. Blind keeps exactly the nodes some surviving link references,
  /// which is the played path and any earlier exploration — not the live fan
  /// out of the position in front of the player.
  Set<String> visibleNodeIds({required bool blind}) {
    if (!blind) return nodes.keys.toSet();
    final keep = <String>{kRoot};
    for (final key in links.keys) {
      if (isLiveHint(key)) continue;
      final l = links[key]!;
      keep.add(l.source);
      keep.add(l.target);
    }
    return keep.intersection(nodes.keys.toSet());
  }

  // getSanLine goes through the JS bridge — memoize per fen+pv prefix
  final Map<String, List<Map<String, dynamic>>> _sanCache = {};

  static const int _topN = 5;
  static const int _depthLimit = 12;

  double get width =>
      kPadLeft + kNodeW + _maxDepth() * kPlyW + kPadLeft;

  int _maxDepth() =>
      nodes.values.fold(1, (m, n) => max(m, n.depth));

  double _xForDepth(int d) => kPadLeft + kNodeW / 2 + d * kPlyW;

  static double _stmCp(EngineMove l) {
    if (l.mate != null) return l.mate! > 0 ? 9999 : -9999;
    return l.score * 100;
  }

  void ingest({
    required List<EngineMove> lines,
    required String fen,
    required List<String> playedSans,
    required double height,
  }) {
    final innerLo = kPadTop + kNodeH / 2;
    final innerHi = height - kPadBottom - kNodeH / 2;
    final midY = (innerLo + innerHi) / 2;

    // new game → wipe the exploration map
    if (playedSans.isEmpty && _lastPathLen > 0) {
      nodes.clear();
      links.clear();
      bestNodeId = null;
      _sanCache.clear();
    }
    _lastPathLen = playedSans.length;

    nodes.putIfAbsent(kRoot, () => TreeNode(kRoot, 0, '·', 'w')
      ..x = _xForDepth(0)
      ..y = midY);

    // played path
    pathKeys = {};
    var parent = kRoot;
    for (var i = 0; i < playedSans.length; i++) {
      final san = playedSans[i];
      final id = '${i + 1}:$san';
      nodes.putIfAbsent(
          id,
          () => TreeNode(id, i + 1, san, i.isEven ? 'w' : 'b')
            ..x = _xForDepth(i + 1)
            ..y = midY);
      final key = '$parent->$id';
      links.putIfAbsent(key,
          () => TreeLink(parent, id, cp: 0, pctBest: 0, anchor: '(path)'));
      pathKeys.add(key);
      parent = id;
    }
    anchorId = parent;
    liveKeys = {...pathKeys};

    // replace this position's previous analysis; truncate past positions'
    // lines to their first branching move
    links.removeWhere((key, l) {
      if (pathKeys.contains(key)) return false;
      return l.anchor == anchorId || l.source != l.anchor;
    });

    // current engine lines → softmax confidence over side-to-move cp (τ=100)
    final shown = [...lines]..sort((a, b) => a.multipv.compareTo(b.multipv));
    final top = shown.take(_topN).toList();
    final cps = top.map(_stmCp).toList();
    final maxCp = cps.isEmpty ? 0.0 : cps.reduce(max);
    final exps = cps.map((c) => exp((c - maxCp) / 100)).toList();
    final denom = exps.isEmpty ? 1.0 : exps.reduce((a, b) => a + b);
    final confs = exps.map((e) => e / denom * 100).toList();
    final bestConf = confs.isEmpty ? 0.0 : confs.reduce(max);
    final whiteTurn = fen.split(' ')[1] != 'b';
    final baseDepth = playedSans.length;

    bestNodeId = null;
    for (var li = 0; li < top.length; li++) {
      final line = top[li];
      final pctBest = bestConf > 0 ? confs[li] / bestConf * 100 : 0.0;
      final cpPawns =
          ((whiteTurn ? cps[li] : -cps[li]) / 100).clamp(-99.0, 99.0);
      final pv = line.pv.take(_depthLimit).toList();
      final cacheKey = '$fen|${pv.join()}';
      final steps = _sanCache.putIfAbsent(
          cacheKey, () => _chess.sanSteps(fen, pv));
      var par = anchorId;
      for (var i = 0; i < steps.length; i++) {
        final st = steps[i];
        final d = baseDepth + 1 + i;
        final id = '$d:${st['san']}';
        nodes.putIfAbsent(
            id,
            () => TreeNode(id, d, st['san'] as String, st['color'] as String)
              ..x = _xForDepth(d)
              ..y = midY);
        links['$par->$id'] = TreeLink(par, id,
            cp: cpPawns,
            pctBest: pctBest,
            uci: i == 0 ? st['uci'] as String? : null,
            anchor: anchorId);
        liveKeys.add('$par->$id');
        if (i == 0 && line.multipv == 1) bestNodeId = id;
        par = id;
      }
    }

    // drop unreferenced nodes
    final referenced = <String>{kRoot};
    for (final l in links.values) {
      referenced.add(l.source);
      referenced.add(l.target);
    }
    nodes.removeWhere((id, _) => !referenced.contains(id));

    // vertical layout: live nodes positioned by pctBest, others keep place
    final byDepth = <int, Map<String, double>>{};
    for (final n in nodes.values) {
      if (n.id == kRoot) continue;
      var desired = n.y;
      var bestVal = -1.0;
      for (final key in liveKeys) {
        final l = links[key];
        if (l == null || l.target != n.id) continue;
        if (l.pctBest > bestVal) bestVal = l.pctBest;
      }
      if (bestVal >= 0) {
        desired = innerLo + (innerHi - innerLo) * (1 - bestVal / 100);
      }
      byDepth.putIfAbsent(n.depth, () => {})[n.id] = desired;
    }
    for (final col in byDepth.values) {
      _separateColumn(col, kNodeH + 8, innerLo, innerHi);
    }
    for (final n in nodes.values) {
      if (n.id == kRoot) continue;
      n.x = _xForDepth(n.depth);
      n.y = byDepth[n.depth]?[n.id] ?? n.y;
    }

    version++;
  }

  static void _separateColumn(
      Map<String, double> desired, double minGap, double lo, double hi) {
    final entries = desired.entries.map((e) => [e.key, e.value]).toList()
      ..sort((a, b) => (a[1] as double).compareTo(b[1] as double));
    if (entries.isEmpty) return;
    final gap = min(
        minGap,
        entries.length > 1
            ? (hi - lo) / (entries.length - 1)
            : minGap);
    for (var i = 1; i < entries.length; i++) {
      final prev = entries[i - 1][1] as double;
      if ((entries[i][1] as double) - prev < gap) entries[i][1] = prev + gap;
    }
    final overflow = (entries.last[1] as double) - hi;
    if (overflow > 0) {
      for (final e in entries) {
        e[1] = (e[1] as double) - overflow;
      }
      for (var i = entries.length - 2; i >= 0; i--) {
        final next = entries[i + 1][1] as double;
        if (next - (entries[i][1] as double) < gap) entries[i][1] = next - gap;
      }
    }
    for (final e in entries) {
      desired[e[0] as String] =
          (e[1] as double).clamp(lo, hi);
    }
  }

  /// First moves out of the current position → their uci (tap targets).
  Map<String, String> playableUci() {
    final out = <String, String>{};
    for (final key in liveKeys) {
      final l = links[key];
      if (l?.uci != null && l!.source == anchorId) out[l.target] = l.uci!;
    }
    return out;
  }
}
