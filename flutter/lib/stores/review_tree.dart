// The reviewed game as a TREE (#196), not a list: the line that was actually
// played, plus every alternative tried out on top of it.
//
// The shape is lichess's and chess.com's, because it is the one that matches
// what reviewing a game is: you follow the game, wonder about a move, play
// something else to see, and then come back to what really happened and carry
// on. That requires the played line to survive being departed from, and a
// departure to survive being come back from — neither of which a flat list of
// moves with a cursor can do.
//
// The MAINLINE is the ARCHIVE, and nothing else: a node is on it only if it
// came out of the stored game ([ReviewNode.archived]). Everything else — "am I
// in a variation", "which mainline ply does this hang off" — is derived from
// that one fact rather than stored separately, so it cannot disagree.
//
// It was "children.first all the way down" first, and that is wrong in one
// specific place that turns out to be a completely ordinary thing to do: at the
// LAST move of the game there are no children yet, so the first move you play
// there becomes children.first — and silently joined the game. The board then
// showed a position the move list did not contain, the verdict strip called it
// "Start position", and no "Back to the game" button appeared, because by every
// derived rule it was not a variation. Reachable on any game whose final
// position is still playable: every resignation, every flag-fall, every
// imported PGN.
//
// Deliberately free of Flutter, dartchess and the engine: it is handed FENs
// and SANs that its caller has already computed, so the whole structure is
// testable as plain data.

/// One position: the move that reached it, and everything played from it.
class ReviewNode {
  ReviewNode._(
    this.parent, {
    required this.fen,
    required this.ply,
    this.san,
    this.uci,
    this.color,
    this.stored,
    this.archived = false,
  });

  final ReviewNode? parent;

  /// The position AFTER [uci] — for the root, the game's starting position.
  final String fen;

  /// Plies from the start. 0 at the root, and the same number for a variation
  /// move as for the played move it replaces.
  final int ply;

  final String? san;
  final String? uci;
  final String? color; // 'w' | 'b'

  /// This move came out of the archived game, rather than being played here
  /// during review. THE definition of the mainline — see the file header for
  /// why "the first child" is not.
  final bool archived;

  /// The archived record for this move — its grade, label and explanation, as
  /// saved when the game was played. Null for a move played during review:
  /// nothing about it was ever graded and stored, and pretending otherwise
  /// would put a label on a move the archive never saw.
  final Map<String, dynamic>? stored;

  final List<ReviewNode> children = [];

  bool get isRoot => parent == null;

  /// The continuation of whatever line this node is on — the played move on
  /// the mainline, a variation's own next move inside one. This is what
  /// forward navigation follows, and it is deliberately NOT the same question
  /// as [archivedChild].
  ReviewNode? get mainChild => children.isEmpty ? null : children.first;

  /// The archived continuation, if the game went on from here. Null at the
  /// last move of the game even when a move has been played there during
  /// review — which is exactly the distinction the file header is about.
  ReviewNode? get archivedChild {
    for (final c in children) {
      if (c.archived) return c;
    }
    return null;
  }

  /// Everything played from here that is NOT the archived continuation — the
  /// alternatives, for a move list to print. Includes a move played on past
  /// the end of the game, which has no archived sibling to be an alternative
  /// to but is still not part of what happened.
  List<ReviewNode> get variations =>
      [for (final c in children) if (!c.archived) c];

  /// This node lies on the line that was actually played.
  bool get onMainline {
    for (ReviewNode? n = this; n != null && !n.isRoot; n = n.parent) {
      if (!n.archived) return false;
    }
    return true;
  }

  /// The root-most node of the variation this one belongs to — the SHALLOWEST
  /// move on the path here that was not its parent's first child, i.e. the one
  /// that departed from the played line. Null when [onMainline].
  ///
  /// Shallowest, not nearest: inside a variation of a variation, the departure
  /// that matters for "get me back to the game" is the first one.
  ReviewNode? get variationRoot {
    for (final n in pathFromRoot) {
      if (!n.archived) return n;
    }
    return null;
  }

  /// Root → here, excluding the root.
  List<ReviewNode> get pathFromRoot {
    final out = <ReviewNode>[];
    for (ReviewNode? n = this; n != null && !n.isRoot; n = n.parent) {
      out.insert(0, n);
    }
    return out;
  }
}

class ReviewTree {
  ReviewTree(String startFen)
      : root = ReviewNode._(null, fen: startFen, ply: 0) {
    current = root;
  }

  /// The archived game: its moves become the mainline, each carrying the
  /// stored record it was saved with.
  factory ReviewTree.fromStored(
      String startFen, List<Map<String, dynamic>> stored) {
    final tree = ReviewTree(startFen);
    var at = tree.root;
    for (final m in stored) {
      final node = ReviewNode._(
        at,
        fen: m['fenAfter'] as String,
        ply: (m['ply'] as num).toInt(),
        san: m['san'] as String,
        uci: m['uci'] as String,
        color: m['color'] as String?,
        stored: m,
        archived: true,
      );
      at.children.add(node);
      at = node;
    }
    return tree;
  }

  final ReviewNode root;
  late ReviewNode current;

  /// Which child to take forward out of a node, when it is not the played one.
  ///
  /// Without this, stepping back out of a variation and forward again lands on
  /// the move that was actually PLAYED — `children.first` — and the branch you
  /// were in a moment ago is unreachable by the arrow keys. That is the bug a
  /// flat "forward means first child" rule cannot avoid, and the reason
  /// lichess navigates by a PATH rather than a node: where you go next depends
  /// on how you got here.
  ///
  /// Kept as parent → child rather than as a path, so it survives jumping
  /// about the tree and needs no rebuilding. Forgotten for a node as soon as
  /// you back out past it (see [back]), and cleared wholesale when you name a
  /// move of the played game — both being ways of saying you are done with the
  /// branch.
  final Map<ReviewNode, ReviewNode> _preferred = {};

  /// The played line, root excluded — the archive, and only the archive.
  List<ReviewNode> get mainline {
    final out = <ReviewNode>[];
    for (var n = root.archivedChild; n != null; n = n.archivedChild) {
      out.add(n);
    }
    return out;
  }

  int get mainlineLength => mainline.length;

  bool get onMainline => current.onMainline;

  /// Where the cursor sits ON the played line: its own ply when it is on it,
  /// otherwise the ply of the move the current variation departed after. This
  /// is what the win chart highlights and the move list scrolls to, both of
  /// which only ever speak about the game that was played.
  int get anchorPly {
    if (current.onMainline) return current.ply;
    var n = current;
    while (!n.onMainline) {
      n = n.parent!;
    }
    return n.ply;
  }

  ReviewNode? childFor(String uci) {
    for (final c in current.children) {
      if (c.uci == uci) return c;
    }
    return null;
  }

  /// Play a move from [current].
  ///
  /// A move that is already a child — including the played one — is FOLLOWED
  /// rather than duplicated: replaying the game move by move on the board must
  /// walk the game, not build a shadow copy of it beside itself. Anything else
  /// is appended after the existing children, which is what keeps the played
  /// line as `children.first` and therefore still the mainline.
  ReviewNode play({
    required String uci,
    required String san,
    required String color,
    required String fen,
  }) {
    final existing = childFor(uci);
    if (existing != null) {
      _preferred[current] = existing;
      current = existing;
      return existing;
    }
    final node = ReviewNode._(
      current,
      fen: fen,
      ply: current.ply + 1,
      san: san,
      uci: uci,
      color: color,
    );
    current.children.add(node);
    _preferred[current] = node; // a move just played is the way forward
    current = node;
    return node;
  }

  /// Throw away the variation the cursor is in and put it back on the played
  /// line at the move that variation departed after. Returns that node, or
  /// null when there was no variation to leave.
  ///
  /// Only ever removes the branch the cursor is actually in — other
  /// variations at the same anchor are somebody else's line of thought and
  /// survive.
  ReviewNode? discardVariation() {
    final departure = current.variationRoot;
    if (departure == null) return null;
    final anchor = departure.parent!;
    anchor.children.remove(departure);
    // Every remembered way forward could point into the branch just deleted.
    _preferred.clear();
    current = anchor;
    return anchor;
  }

  bool get canBack => !current.isRoot;
  bool get canForward => _nextFrom(current) != null;

  ReviewNode? _nextFrom(ReviewNode n) => _preferred[n] ?? n.mainChild;

  bool back() {
    if (!canBack) return false;
    final leaving = current;
    // Two halves, and the second is what stops the memory outstaying its
    // welcome. Remember the way back INTO this node, so one step back and one
    // forward returns you to the line you were reading rather than evicting
    // you from it. But forget the way ONWARD from it: you have now retreated
    // past this move, and a branch you have backed out of should not be
    // re-entered by walking forward through it later. Retreat far enough and
    // every branch below you has been forgotten, so forward follows the game.
    //
    // Stricter than lichess, which drops the branch on the first step back
    // (its forward is plainly `children[0]`; branch selection is a separate
    // up/down fork control). Looser than remembering the path forever, which
    // is what this did first and what made backing out of a variation feel
    // like it had trapped you in it.
    _preferred.remove(leaving);
    _preferred[leaving.parent!] = leaving;
    current = leaving.parent!;
    return true;
  }

  /// Forward along the line the cursor is on: the branch it came down, where
  /// there is one, and the played continuation otherwise.
  bool forward() {
    final next = _nextFrom(current);
    if (next == null) return false;
    current = next;
    return true;
  }

  /// Jump to any node — the move list tapping into a variation. Records the
  /// whole path, so forward from anywhere above continues down THIS branch.
  void goto(ReviewNode node) {
    for (final n in node.pathFromRoot) {
      _preferred[n.parent!] = n;
    }
    current = node;
  }

  /// Jump to a ply of the PLAYED line, leaving any variation. Clamped.
  ///
  /// Clears the remembered branches: naming a move of the game is how you say
  /// you are back on the game, and forward from there must follow the game.
  /// The last move of the PLAYED game — not the end of an exploration that
  /// happens to hang off it.
  void gotoMainlineEnd() => gotoMainlinePly(mainlineLength);

  void gotoMainlinePly(int ply) {
    _preferred.clear();
    final line = mainline;
    final n = ply.clamp(0, line.length);
    current = n == 0 ? root : line[n - 1];
  }
}
