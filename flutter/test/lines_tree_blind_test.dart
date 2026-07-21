// Blind mode and the Lines tree.
//
// Blind mode withholds the engine's opinion about the CURRENT position. The
// tree is the panel most able to give it away: it draws the engine's live
// lines as boxes, rings the best one in green, and labels each with its
// evaluation. What it must keep drawing is the game's own history — blind
// hides what the engine thinks next, not where the game has been.
//
//   cd flutter && flutter test test/lines_tree_blind_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/chess_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/lines_tree_model.dart';

/// `sanSteps` is the only thing the model needs from the bridge. It hands back
/// one step per uci, naming the move after its uci so assertions can identify
/// a node by the move it represents.
class FakeChess implements ChessApi {
  @override
  List<Map<String, dynamic>> sanSteps(String fen, List<String> ucis) => [
        for (var i = 0; i < ucis.length; i++)
          {
            'san': ucis[i],
            'uci': ucis[i],
            'color': i.isEven ? 'w' : 'b',
            'piece': 'p',
          }
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

LinesTreeModel _treeWithEngineLines() {
  final tree = LinesTreeModel(FakeChess());
  tree.ingest(
    lines: const [
      EngineMove(pv: ['g1f3', 'b8c6'], score: 0.4, mate: null, depth: 18, multipv: 1),
      EngineMove(pv: ['e2e4', 'e7e5'], score: 0.2, mate: null, depth: 18, multipv: 2),
    ],
    fen: _fen,
    playedSans: const ['d2d4'], // one move of real history
    height: 300,
  );
  return tree;
}

/// Two ingests: the engine suggests something at the root, then the player
/// plays a DIFFERENT move and the engine analyses the new position. The first
/// suggestion is now history — a road not taken, anchored at a position that is
/// no longer current — and blind must keep drawing it.
LinesTreeModel _treeWithPastExploration() {
  final tree = LinesTreeModel(FakeChess());
  tree.ingest(
    lines: const [
      EngineMove(pv: ['g1f3'], score: 0.3, mate: null, depth: 18, multipv: 1),
    ],
    fen: _fen,
    playedSans: const [],
    height: 300,
  );
  tree.ingest(
    lines: const [
      EngineMove(pv: ['e2e4'], score: 0.4, mate: null, depth: 18, multipv: 1),
    ],
    fen: _fen,
    playedSans: const ['d2d4'],
    height: 300,
  );
  return tree;
}

void main() {
  test('sighted: the engine lines are there to leak', () {
    // The control. If this ever stops holding, the blind assertions below stop
    // meaning anything — they would pass on a tree that simply has no hints.
    final tree = _treeWithEngineLines();
    expect(tree.bestNodeId, isNotNull);
    final visible = tree.visibleNodeIds(blind: false);
    expect(visible, equals(tree.nodes.keys.toSet()),
        reason: 'sighted mode withholds nothing');
    expect(tree.nodes.values.map((n) => n.san), contains('g1f3'));
  });

  test('blind: the best move is not marked', () {
    final tree = _treeWithEngineLines();
    expect(tree.visibleBestNodeId(blind: true), isNull,
        reason: 'the green ring is the single most valuable hint on the panel');
  });

  test('blind: the engine line nodes are withheld, not just their links', () {
    // The bug this test was written for. Hiding only the LINKS left the engine's
    // moves on screen as floating labelled boxes — the suggestion is the move
    // name, so it leaks with or without a curve attached to it.
    final tree = _treeWithEngineLines();
    final visible = tree.visibleNodeIds(blind: true);
    final shown = tree.nodes.entries
        .where((e) => visible.contains(e.key))
        .map((e) => e.value.san)
        .toSet();

    expect(shown, isNot(contains('g1f3')), reason: 'the top engine move');
    expect(shown, isNot(contains('e2e4')), reason: 'the second engine line');
    expect(shown, isNot(contains('b8c6')), reason: 'deeper in a live line');
  });

  test('blind: earlier exploration stays — it is history, not a hint', () {
    // The over-hiding guard. Without it, replacing isLiveHint with "keep only
    // the played path" passes every other test in this file: the single-ingest
    // fixture has no past to erase. Blind withholds the engine's opinion about
    // the CURRENT position, not the record of where the game has been.
    final tree = _treeWithPastExploration();
    final visible = tree.visibleNodeIds(blind: true);
    final shown = tree.nodes.entries
        .where((e) => visible.contains(e.key))
        .map((e) => e.value.san)
        .toSet();

    expect(shown, contains('d2d4'), reason: 'the move actually played');
    expect(shown, contains('g1f3'),
        reason: 'suggested at a position that is no longer current — history');
    expect(shown, isNot(contains('e2e4')),
        reason: 'the live suggestion at the CURRENT position');
  });

  test('blind: the played move stays', () {
    // The half that must NOT change. Blind is about the engine's opinion, not
    // amnesia — the game's own history is still the player's to see.
    final tree = _treeWithEngineLines();
    final visible = tree.visibleNodeIds(blind: true);
    final shown = tree.nodes.entries
        .where((e) => visible.contains(e.key))
        .map((e) => e.value.san)
        .toSet();

    expect(shown, contains('d2d4'), reason: 'a move already played');
    expect(visible, contains(kRoot));
  });
}
