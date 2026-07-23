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

/// The layout leak (#147). After a takeback the tree carries a *ghost* — a
/// visible node the game once explored — in the same depth column as the
/// engine's new, hidden live hints. If the layout pass separates the whole
/// column, a hidden node's score-derived y can push the visible ghost, so its
/// position becomes a readout of an evaluation blind mode is withholding.
///
/// Sequence: play d2d4, play g8f6, analyse; then take back to d2d4 and analyse
/// the new position. The first analysis' first moves survive as depth-3 ghosts
/// (visible history); the new analysis' depth-3 nodes are hidden live hints in
/// the same column. `secondLine` is the score of the hidden second line only.
LinesTreeModel _treeAfterTakeback(double secondLine, {required bool blind}) {
  final tree = LinesTreeModel(FakeChess());
  tree.ingest(
    lines: const [
      EngineMove(pv: ['g8f6'], score: 0.3, mate: null, depth: 18, multipv: 1),
    ],
    fen: _fen,
    playedSans: const ['d2d4'],
    height: 300,
    blind: blind,
  );
  // At the depth-2 position, two lines. h2h3 lands mid-column; both first moves
  // survive the takeback as visible depth-3 ghosts.
  tree.ingest(
    lines: const [
      EngineMove(pv: ['c2c4'], score: 0.6, mate: null, depth: 18, multipv: 1),
      EngineMove(pv: ['h2h3'], score: -0.09, mate: null, depth: 18, multipv: 2),
    ],
    fen: _fen,
    playedSans: const ['d2d4', 'g8f6'],
    height: 300,
    blind: blind,
  );
  // Take back to d2d4. The hidden second line's depth-3 node (3:c7c5) shares the
  // column with the visible ghost 3:h2h3; only `secondLine` varies between runs.
  tree.ingest(
    lines: [
      const EngineMove(
          pv: ['b1c3', 'e7e6', 'f1c4'],
          score: 0.6,
          mate: null,
          depth: 18,
          multipv: 1),
      EngineMove(
          pv: const ['e2e4', 'c7c5', 'g1f3'],
          score: secondLine,
          mate: null,
          depth: 18,
          multipv: 2),
    ],
    fen: _fen,
    playedSans: const ['d2d4'],
    height: 300,
    blind: blind,
  );
  return tree;
}

void main() {
  test('blind: a hidden line\'s score does not move a visible ghost', () {
    // #147. The ghost 3:h2h3 is drawn in blind mode (it is history). The hidden
    // node 3:c7c5 is not. With the whole column laid out together, c7c5's
    // score-derived y pushes the ghost: measured y=167.6 at a 0.0 second line
    // vs 149.6 at 0.5 — a 30px readout of an eval the player may not see.
    final strong = _treeAfterTakeback(0.5, blind: true);
    final weak = _treeAfterTakeback(0.0, blind: true);

    // Guard the fixture: the ghost is visible, the mover is hidden, and the two
    // genuinely share the depth-3 column.
    final vis = strong.visibleNodeIds(blind: true);
    expect(vis, contains('3:h2h3'), reason: 'the ghost is history, drawn blind');
    expect(vis, isNot(contains('3:c7c5')),
        reason: 'the mover is a live hint, hidden blind');
    expect(strong.nodes['3:h2h3']!.depth, equals(strong.nodes['3:c7c5']!.depth),
        reason: 'ghost and mover share a column, else nothing could push');

    // Prove the second line's score really drives that column: laid out SIGHTED
    // (nothing hidden), the same score change moves the mover. This is exactly
    // the displacement blind must not let reach the visible ghost.
    expect(
        _treeAfterTakeback(0.5, blind: false).nodes['3:c7c5']!.y,
        isNot(equals(
            _treeAfterTakeback(0.0, blind: false).nodes['3:c7c5']!.y)),
        reason: 'the score genuinely drives this column');

    expect(strong.nodes['3:h2h3']!.y, equals(weak.nodes['3:h2h3']!.y),
        reason: 'the visible ghost must not encode the hidden score');
  });

  test('non-blind layout is unaffected by the blind flag', () {
    // The regression guard: blind:false must be byte-identical to the old
    // default-argument call. Same fixture, both flags, every y must match.
    final a = LinesTreeModel(FakeChess());
    final b = LinesTreeModel(FakeChess());
    for (final tree in [a, b]) {
      tree.ingest(
        lines: const [
          EngineMove(pv: ['g1f3', 'b8c6'], score: 0.4, mate: null, depth: 18, multipv: 1),
          EngineMove(pv: ['e2e4', 'e7e5'], score: 0.2, mate: null, depth: 18, multipv: 2),
        ],
        fen: _fen,
        playedSans: const ['d2d4'],
        height: 300,
        blind: false,
      );
    }
    for (final id in a.nodes.keys) {
      expect(a.nodes[id]!.y, equals(b.nodes[id]!.y));
    }
  });

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
