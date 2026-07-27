// The lines tree is re-ingested at EVERY ending, including the two that do not
// go through _apply (#237).
//
// #147 bakes blind mode into the tree's LAYOUT rather than its paint: a hidden
// node's y is a function of the engine's live score, so leaving it in the
// layout pass would let it displace a visible node in the same column and leak
// the eval through the survivor's position. The model only recomputes y on
// ingest — so when the veil lifts at game over, the pane repaints unblinded
// against a layout computed blind, and every previously-hidden node is drawn
// at the default y it was created with, stacked on the midline.
//
// Mate and the draws go through `_apply`, which resyncs. Resignation and
// flag-fall set the game-over state directly and bypass it. Both were fixed in
// #236, and a fresh verification agent then showed that deleting either
// `_syncTree()` left the whole suite green.
//
// The issue this file closes was filed believing the harness could not reach
// any of this without extracting an interface for `JsBridge` — a production
// refactor of the seam the entire brain bridge sits on. It could: `implements
// ChessApi` supplies the facade one level ABOVE the conditional export, and
// nothing platform-specific is involved. See [FakeChess].
//
//   cd flutter && flutter test test/tree_resync_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/chess_clock.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/lines_tree_model.dart';

import 'support/fake_db.dart';
import 'support/game_harness.dart';

/// Where the tree puts a node it has laid out at full confidence: [kFakeLines]
/// is a single line, so its first move is the only candidate, takes 100% of
/// the softmax, and lands at the top of the band.
///
/// Derived from the model's own geometry rather than typed, so a change to the
/// padding moves this with it instead of reddening a test about resyncing.
const double _kHeight = 300; // what _syncTree passes
const double _kTop = kPadTop + kNodeH / 2;
const double _kMid =
    (_kTop + (_kHeight - kPadBottom - kNodeH / 2)) / 2;

/// The y of the engine's own top suggestion — the node whose position is the
/// leak, and the one thing the blind and sighted layouts disagree about.
double _bestY(GameController g) {
  final tree = g.linesTree!;
  final id = tree.bestNodeId;
  expect(id, isNotNull, reason: 'the engine suggested nothing to lay out');
  return tree.nodes[id]!.y;
}

Future<(GameController, FakeDb)> _game({
  bool blind = true,
  bool rated = false,
}) async {
  // The human is White, the bot Black, so White can resign a played move.
  final settings = await loadSettings(black: kTestBotId);
  settings.blind = blind;
  final db = FakeDb();
  final g = GameController(
    FakeArbiter(analysisLines: kFakeLines, streamPartials: true),
    FakeBot({kTestBotId: testBotPersona}),
    SavingGrading(),
    settings,
    db,
    null,
    FakeChess(),
  );
  if (rated) {
    // showThreats OFF before the rated game starts, and this is load-bearing.
    // A rated game snapshots the overlay switches and forces all four off
    // (_applyRatedPreset); _saveGame hands them back at every ending, which
    // changes the settings, which fires _onSettings, which resyncs the tree
    // for its OWN reason (#147's blind toggle). With the player's switches in
    // their default state that incidental resync covers for the missing one
    // and this file's flag test passes with the onFlag _syncTree() deleted —
    // which is exactly the shape of inert test #237 is about.
    //
    // Matching what the preset would set means the restore is a no-op, so the
    // only thing that can re-lay the tree is the callback under test.
    settings.showThreats = false;
    g.newGame(rated: true, timeControl: TimeControl.parse('5+0'));
  }
  return (g, db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the blind layout really does stack the engine\'s node',
      (tester) async {
    // The precondition every assertion below rests on. Without it, a test that
    // only checked the post-resign y would pass against a build where blind
    // mode never moved anything in the first place.
    final (g, _) = await _game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));

    expect(g.hidingHelp, isTrue, reason: 'blind, bot game, still running');
    expect(_bestY(g), _kMid,
        reason: 'a hidden node keeps the default y it was created with');
    g.dispose();
  });

  testWidgets('and the sighted layout does not', (tester) async {
    final (g, _) = await _game(blind: false);
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));

    expect(_bestY(g), _kTop,
        reason: 'the only line takes the whole softmax, so it sits at the top');
    g.dispose();
  });

  testWidgets('resigning re-lays the tree it just unblinded', (tester) async {
    final (g, db) = await _game();
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(_bestY(g), _kMid, reason: 'precondition: laid out blind');

    g.resign();
    await tester.pump(const Duration(seconds: 1));

    expect(g.gameOver, isTrue);
    expect(g.hidingHelp, isFalse, reason: 'the veil lifts at game over');
    // The assertion #237 is about. Without the _syncTree() in resign(), the
    // pane paints every node — the veil having lifted — at the y the BLIND
    // pass left it, which is this same midline for all of them.
    expect(_bestY(g), _kTop,
        reason: 'resign() did not re-ingest: the pane draws a stacked tree');
    expect(db.saved, hasLength(1), reason: 'and it still archives');
    g.dispose();
  });

  testWidgets('flag-fall does too', (tester) async {
    // The other ending that bypasses _apply. Reached through the clock rather
    // than by calling the handler, since what is under test is the callback
    // newGame() installs.
    final (g, _) = await _game(rated: true);
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(_bestY(g), _kMid, reason: 'precondition: laid out blind');

    g.clock!.debugFlag(ClockSide.white);
    await tester.pump(const Duration(seconds: 1));

    expect(g.gameOver, isTrue);
    expect(g.statusLine, contains('ran out of time'), reason: 'a flag, not a mate');
    expect(_bestY(g), _kTop,
        reason: 'the onFlag callback did not re-ingest');
    g.dispose();
  });

  testWidgets('a sighted game is not disturbed by either', (tester) async {
    // The control. A resign() that resynced with the WRONG predicate — say a
    // hardcoded `blind: true` — would satisfy nothing above but would break
    // this, and so would one that wiped the tree instead of re-laying it.
    final (g, _) = await _game(blind: false);
    g.playUci('e2e4');
    await tester.pump(const Duration(milliseconds: 50));
    final before = _bestY(g);

    g.resign();
    await tester.pump(const Duration(seconds: 1));

    expect(_bestY(g), before);
    expect(g.linesTree!.nodes, isNotEmpty, reason: 're-laid, not wiped');
    g.dispose();
  });
}
