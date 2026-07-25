// The reviewed game as a tree (#196). Pure data — no engine, no widgets.
//
//   cd flutter && flutter test test/review_tree_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/review_tree.dart';

/// A stored mainline move. The fens are opaque to the tree — it is handed
/// them, it does not compute them — so short names are clearer here than real
/// FENs and cannot drift from a chess rule the tree does not implement.
Map<String, dynamic> _m(int ply, String san, String uci, String fen) => {
      'ply': ply,
      'san': san,
      'uci': uci,
      'color': ply.isOdd ? 'w' : 'b',
      'fenAfter': fen,
      'label': 'blunder',
    };

/// 1. e4 e5 2. Nf3
final _stored = [
  _m(1, 'e4', 'e2e4', 'fen-1'),
  _m(2, 'e5', 'e7e5', 'fen-2'),
  _m(3, 'Nf3', 'g1f3', 'fen-3'),
];

ReviewTree _tree() => ReviewTree.fromStored('fen-0', _stored);

void main() {
  group('the archived game becomes the mainline', () {
    test('every stored move is on it, in order, carrying its record', () {
      final t = _tree();
      expect(t.mainline.map((n) => n.san), ['e4', 'e5', 'Nf3']);
      expect(t.mainlineLength, 3);
      expect(t.mainline.every((n) => n.onMainline), isTrue);
      expect(t.mainline.first.stored?['label'], 'blunder',
          reason: 'the grade the game was saved with comes along');
      expect(t.current, t.root, reason: 'opens at the start position');
    });

    test('the root is the start position and has no move', () {
      final t = _tree();
      expect(t.root.fen, 'fen-0');
      expect(t.root.san, isNull);
      expect(t.root.isRoot, isTrue);
      expect(t.root.onMainline, isTrue);
    });
  });

  group('navigating the played line', () {
    test('forward and back walk it', () {
      final t = _tree();
      expect(t.canBack, isFalse);
      expect(t.forward(), isTrue);
      expect(t.current.san, 'e4');
      expect(t.forward(), isTrue);
      expect(t.current.san, 'e5');
      expect(t.back(), isTrue);
      expect(t.current.san, 'e4');
      expect(t.canForward, isTrue);
    });

    test('forward stops at the end, back stops at the root', () {
      final t = _tree();
      t.gotoMainlinePly(3);
      expect(t.canForward, isFalse);
      expect(t.forward(), isFalse);
      t.gotoMainlinePly(0);
      expect(t.canBack, isFalse);
      expect(t.back(), isFalse);
    });

    test('gotoMainlinePly clamps rather than throwing', () {
      final t = _tree();
      t.gotoMainlinePly(99);
      expect(t.current.san, 'Nf3');
      t.gotoMainlinePly(-5);
      expect(t.current, t.root);
    });

    test('replaying a played move FOLLOWS it instead of duplicating it', () {
      // Stepping through the game by playing its moves on the board must walk
      // the game, not build a shadow copy of it beside itself.
      final t = _tree();
      final node =
          t.play(uci: 'e2e4', san: 'e4', color: 'w', fen: 'fen-1');
      expect(identical(node, t.mainline.first), isTrue);
      expect(t.root.children, hasLength(1), reason: 'no second e4');
      expect(t.onMainline, isTrue);
    });
  });

  group('past the end of the game (review follow-up)', () {
    // The last move of the archive has no children, so "the mainline is
    // children.first" made the first move played there part of the game —
    // silently, and with no way back, since by every derived rule it was not
    // a variation. Reachable on any game whose final position is playable:
    // every resignation, every flag-fall, every imported PGN.
    test('a move played at the end is a VARIATION, not a continuation', () {
      final t = _tree();
      t.gotoMainlinePly(3); // the last archived move
      t.play(uci: 'f1b5', san: 'Bb5', color: 'w', fen: 'fen-bb5');

      expect(t.onMainline, isFalse, reason: 'nobody played this');
      expect(t.mainlineLength, 3, reason: 'the archive did not grow');
      expect(t.mainline.map((n) => n.san), ['e4', 'e5', 'Nf3']);
      expect(t.current.archived, isFalse);
    });

    test('and it can be discarded like any other variation', () {
      final t = _tree();
      t.gotoMainlinePly(3);
      t.play(uci: 'f1b5', san: 'Bb5', color: 'w', fen: 'fen-bb5');

      final back = t.discardVariation();
      expect(back?.san, 'Nf3', reason: 'the last move of the game');
      expect(t.onMainline, isTrue);
      expect(t.mainline.last.variations, isEmpty);
    });

    test('it is listed as a variation of the last move', () {
      // Which is what gives the move list something to render.
      final t = _tree();
      t.gotoMainlinePly(3);
      t.play(uci: 'f1b5', san: 'Bb5', color: 'w', fen: 'fen-bb5');
      expect(t.mainline.last.variations.map((n) => n.san), ['Bb5']);
    });

    test('forward still walks INTO it — it is the line you are on', () {
      final t = _tree();
      t.gotoMainlinePly(3);
      t.play(uci: 'f1b5', san: 'Bb5', color: 'w', fen: 'fen-bb5');
      t.back();
      expect(t.current.san, 'Nf3');
      t.forward();
      expect(t.current.san, 'Bb5');
    });

    test('gotoMainlineEnd stops at the end of the GAME', () {
      final t = _tree();
      t.gotoMainlinePly(3);
      t.play(uci: 'f1b5', san: 'Bb5', color: 'w', fen: 'fen-bb5');
      t.gotoMainlineEnd();
      expect(t.current.san, 'Nf3');
      expect(t.onMainline, isTrue);
    });
  });

  group('branching', () {
    test('an alternative move makes a variation and does not disturb the game',
        () {
      final t = _tree();
      t.gotoMainlinePly(1); // after 1. e4
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');

      expect(t.onMainline, isFalse);
      expect(t.current.san, 'c5');
      expect(t.current.stored, isNull,
          reason: 'a move played now was never graded and archived');
      expect(t.mainline.map((n) => n.san), ['e4', 'e5', 'Nf3'],
          reason: 'the game that was played is untouched');
      expect(t.mainline[0].variations.map((n) => n.san), ['c5']);
    });

    test('the variation continues on its own', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-sicilian-2');

      expect(t.current.ply, 3);
      expect(t.onMainline, isFalse);
      expect(t.current.pathFromRoot.map((n) => n.san), ['e4', 'c5', 'Nf3']);
      expect(t.mainlineLength, 3, reason: 'still the played game');
    });

    test('back then forward returns to the BRANCH, not the played move', () {
      // Navigating by node alone cannot do this: forward from e4 is
      // `children.first`, which is the move that was actually played. Stepping
      // out of a variation and back in has to land where you were.
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');
      t.back();
      expect(t.current.san, 'e4');
      t.forward();
      expect(t.current.san, 'c5', reason: 'not e5');
    });

    test('naming a move of the game drops the remembered branch', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');
      t.gotoMainlinePly(1); // explicitly back on the game
      t.forward();
      expect(t.current.san, 'e5', reason: 'the game, not the branch');
    });

    test('backing out PAST the branch point puts forward back on the game', () {
      // One step back and forward returns you to the branch (above) — but once
      // you have retreated past the move it departed from, you have left that
      // line of thought, and walking forward again must follow what was
      // actually played rather than silently re-entering it.
      final t = _tree();
      t.gotoMainlinePly(1); // after 1. e4
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');

      t.back(); // to e4 — still remembers c5
      t.back(); // to the start — past the branch point
      expect(t.current, t.root);

      t.forward();
      expect(t.current.san, 'e4');
      t.forward();
      expect(t.current.san, 'e5', reason: 'the played move, not the branch');
      expect(t.onMainline, isTrue);
    });

    test('the branch itself survives being backed out of', () {
      // Forgetting the way forward is not deleting the line — it is still
      // there to be tapped back into from the move list.
      final t = _tree();
      t.gotoMainlinePly(1);
      final branch =
          t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');
      t.back();
      t.back();
      t.forward();
      t.forward();
      expect(t.current.san, 'e5');
      expect(t.mainline[0].variations.map((n) => n.san), ['c5']);

      t.goto(branch);
      expect(t.current.san, 'c5');
      expect(t.onMainline, isFalse);
    });

    test('a deep branch is walked forward normally after one step back', () {
      // The rule must not eat the ordinary case: inside a variation, its own
      // continuation IS children.first, so stepping about within it is
      // unaffected by any of this.
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-a2');
      t.play(uci: 'd7d6', san: 'd6', color: 'b', fen: 'fen-a3');

      t.back();
      t.back();
      expect(t.current.san, 'c5');
      t.forward();
      expect(t.current.fen, 'fen-a2');
      t.forward();
      expect(t.current.fen, 'fen-a3');
    });

    test('forward inside a variation follows the VARIATION', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-sicilian-2');
      t.back();
      expect(t.current.san, 'c5');
      t.forward();
      expect(t.current.fen, 'fen-sicilian-2',
          reason: 'not the played game\'s Nf3');
    });

    test('you can go back up to the played line and carry on', () {
      // The whole point of the issue: leave the game, look at something else,
      // come back to what really happened and continue from there.
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-sicilian');

      t.gotoMainlinePly(2);
      expect(t.onMainline, isTrue);
      expect(t.current.san, 'e5');
      t.forward();
      expect(t.current.san, 'Nf3');
      expect(t.onMainline, isTrue);
    });

    test('several variations can hang off one move', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.gotoMainlinePly(1);
      t.play(uci: 'e7e6', san: 'e6', color: 'b', fen: 'fen-b');

      expect(t.mainline[0].variations.map((n) => n.san), ['c5', 'e6']);
      expect(t.mainline[0].children.first.san, 'e5',
          reason: 'the played move stays first — that IS the mainline rule');
    });

    test('a variation of a variation is still off the played line', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-a2');
      t.back();
      t.play(uci: 'b1c3', san: 'Nc3', color: 'w', fen: 'fen-a3');

      expect(t.onMainline, isFalse);
      expect(t.current.san, 'Nc3');
      expect(t.current.variationRoot?.san, 'c5',
          reason: 'the SHALLOWEST departure is the way back to the game');
    });
  });

  group('anchorPly — what the chart and move list follow', () {
    test('on the played line it is the cursor itself', () {
      final t = _tree();
      t.gotoMainlinePly(2);
      expect(t.anchorPly, 2);
    });

    test('inside a variation it is the move the variation departed after', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-a2');
      expect(t.anchorPly, 1,
          reason: 'two plies deep in the branch, but the game is still at e4');
    });
  });

  group('discarding a variation', () {
    test('drops the branch and lands on the move it left from', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.play(uci: 'g1f3', san: 'Nf3', color: 'w', fen: 'fen-a2');

      final back = t.discardVariation();
      expect(back?.san, 'e4');
      expect(t.onMainline, isTrue);
      expect(t.mainline[0].variations, isEmpty);
      expect(t.mainline.map((n) => n.san), ['e4', 'e5', 'Nf3']);
    });

    test('leaves other variations at the same move alone', () {
      final t = _tree();
      t.gotoMainlinePly(1);
      t.play(uci: 'c7c5', san: 'c5', color: 'b', fen: 'fen-a');
      t.gotoMainlinePly(1);
      t.play(uci: 'e7e6', san: 'e6', color: 'b', fen: 'fen-b');

      t.discardVariation(); // the cursor is in the e6 branch
      expect(t.mainline[0].variations.map((n) => n.san), ['c5'],
          reason: 'someone else\'s line of thought is not ours to delete');
    });

    test('is a no-op on the played line', () {
      final t = _tree();
      t.gotoMainlinePly(2);
      expect(t.discardVariation(), isNull);
      expect(t.current.san, 'e5');
      expect(t.mainlineLength, 3);
    });
  });
}
