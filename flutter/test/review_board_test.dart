// The Review tab's board (#194): an archived game on the ANALYSIS board.
//
// What these tests are really guarding is the one design decision the feature
// rests on — that the review cursor's position IS `position`, not a
// [GameController.browseFen] over some other one. Every overlay in the
// controller (the engine arrows, the threat probe, the square control) is
// computed for `position.fen`, and BoardPane blanks all of them while
// `browsing` is true. So a review board that navigated by browsing would draw
// exactly nothing, which is the bug this file exists to keep out.
//
//   cd flutter && flutter test test/review_board_test.dart

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';

import 'support/game_harness.dart';

// DERIVED, not typed. A stored record's fens come out of `position.fen`, and
// dartchess drops an en-passant square no capture can reach — so a
// hand-written "after 1.e4" fen with `e3` on it is a fen this app never
// writes, and the board would not match it. Play the moves and read them off.
final _kStart = Chess.initial.fen;
final _afterE4Pos = Chess.initial.play(NormalMove.fromUci('e2e4'));
final _kAfterE4 = _afterE4Pos.fen;
final _kAfterE5 = _afterE4Pos.play(NormalMove.fromUci('e7e5')).fen;

/// A two-ply archived game. [botColor] is what orientation is read from — null
/// is an import, which has no "you" in it.
Map<String, dynamic> _game({String? botColor = 'b', String id = 'g1'}) => {
      'id': id,
      'botColor': botColor,
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': _kStart,
          'fenAfter': _kAfterE4,
          'label': 'blunder',
        },
        {
          'ply': 2,
          'san': 'e5',
          'uci': 'e7e5',
          'color': 'b',
          'fenBefore': _kAfterE4,
          'fenAfter': _kAfterE5,
        },
      ],
    };

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<(ReviewController, ReviewBoardController)> _open({
  String? botColor = 'b',
  String? white,
  String? black,
  Map<String, dynamic>? game,
}) async {
  final settings = await loadSettings(white: white, black: black);
  final review = ReviewController(_StubDb());
  final board = fakeReviewBoard(review, settings);
  review.open(game ?? _game(botColor: botColor));
  return (review, board);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the cursor moves the POSITION, not a browse overlay (#194)', () {
    test('opening a game puts its start position on the board', () async {
      final (_, board) = await _open();
      expect(board.position.fen, _kStart);
      expect(board.browsing, isFalse,
          reason: 'browsing is what makes BoardPane blank every overlay — a '
              'review board that used it would draw nothing');
      expect(board.browseFen, isNull);
      board.dispose();
    });

    test('stepping the cursor steps the position the overlays are keyed on',
        () async {
      final (review, board) = await _open();

      board.stepForward();
      expect(board.position.fen, _kAfterE4);
      expect(board.lastMove?.uci, 'e2e4');
      expect(board.browsing, isFalse);

      board.stepForward();
      expect(board.position.fen, _kAfterE5);
      expect(board.lastMove?.uci, 'e7e5');

      board.gotoMainlinePly(0);
      expect(board.position.fen, _kStart);
      expect(board.lastMove, isNull, reason: 'nothing has been played yet');
      board.dispose();
    });

    test('the whole game stays in moves whatever the cursor says', () async {
      // The move list, the chart and the tree's played path all read this,
      // and they show the whole game from any cursor position.
      final (review, board) = await _open();
      expect(board.moves, hasLength(2));
      board.stepForward();
      expect(board.moves, hasLength(2));
      board.dispose();
    });

    test('opening a different game rebuilds the board', () async {
      final (review, board) = await _open();
      board.stepForward();
      expect(board.position.fen, _kAfterE4);

      review.open(_game(id: 'g2'));
      expect(board.position.fen, _kStart, reason: 'a fresh game opens at 0');
      board.dispose();
    });

    test('closing the archive clears the board', () async {
      final (review, board) = await _open();
      board.stepForward();
      review.close();
      expect(board.moves, isEmpty);
      expect(board.tree, isNull);
      // The board itself, not just the list — it used to keep the closed
      // game's position and last-move highlight.
      expect(board.position.fen, Chess.initial.fen);
      expect(board.lastMove, isNull);
      board.dispose();
    });

    test('re-notifying about the SAME game leaves the cursor alone', () async {
      // ReviewController notifies on loadGames(), which fires on archive
      // refresh, after an import and after a sync pull. Without the same-id
      // guard every one of those would snap the board back to ply 0 and throw
      // away any variation being explored.
      final (review, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5'); // a variation in progress
      expect(board.inVariation, isTrue);

      review.notifyListeners();

      expect(board.inVariation, isTrue, reason: 'the branch survived');
      expect(board.tree!.current.san, 'c5');
      board.dispose();
    });
  });

  group('review is independent of the live game', () {
    test('scrubbing never voids the live game\'s work on the shared arbiter',
        () async {
      // One arbiter stands behind both boards. bumpGeneration voids queued
      // AND running work of EVERY priority — so a review scrub would have
      // resolved the live game's in-flight bot-move search as null, and its
      // bot would have silently declined to move. Only position-scoped work
      // (analysis, threat probe) may be dropped from here.
      final settings = await loadSettings();
      final arbiter = FakeArbiter();
      final review = ReviewController(_StubDb());
      final board = fakeReviewBoard(review, settings, arbiter: arbiter);
      review.open(_game());
      board.stepForward();
      board.stepForward();
      board.gotoMainlinePly(0);

      expect(arbiter.bumpGenerations, 0,
          reason: 'that would kill a bot move on the other board');
      expect(arbiter.cancelledExcept, isNotEmpty,
          reason: 'stale review analyses must still yield the engine');
      expect(arbiter.cancelledExcept.last, _kStart,
          reason: 'everything except the position now on the review board');
      board.dispose();
    });

    test('a bot game on the Play tab does not put a bot on the review board',
        () async {
      // The settings say black is a bot, which is what the LIVE game is. If
      // the review board read that, `botEnabled` would be true, a persona
      // would be on the move in a finished game, and the overlays would be
      // gated behind blind mode's live-game rules.
      final (_, board) = await _open(black: kTestBotId);
      expect(board.botEnabled, isFalse);
      expect(board.blackPersona, isNull);
      expect(board.whitePersona, isNull);
      expect(board.isPlayerTurn, isTrue);
      board.dispose();
    });

    test('blind mode never withholds anything from a finished game', () async {
      // A blind game in progress on the Play tab must not strip the arrows
      // and threat glyphs off an unrelated ARCHIVED game. The review board
      // used to force `blind` false to get this; since #148 it falls out of
      // the one predicate instead, via its `!_review` clause. (`botEnabled`
      // covered this for one commit, when blind required an opponent — but
      // blind is wanted on the analysis board, which has none either, so the
      // exclusion had to be named rather than inferred.)
      final settings = await loadSettings(black: kTestBotId);
      settings.blind = true;
      final review = ReviewController(_StubDb());
      final board = fakeReviewBoard(review, settings,
          arbiter: FakeArbiter(
              analysisLines: kFakeLines, streamPartials: true));
      review.open(_game());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(board.blind, isTrue, reason: 'the SETTING is shared and still on');
      expect(board.hidingHelp, isFalse, reason: 'but nothing is withheld here');
      // Not `isEmpty` — that was the assertion here before, and it passed for
      // want of an analysis rather than for the reason it claimed, so it held
      // whatever the predicate said. This is the case that separates `blind`
      // from `hidingHelp` at a BOARD overlay: an overlay that reverts to
      // asking `blind` goes dark here.
      expect(board.currentLines, isNotEmpty, reason: 'precondition');
      expect(board.engineArrowUcis, isNotEmpty);
      expect(board.visibleLines, isNotEmpty, reason: 'and the panes, likewise');
      board.dispose();
    });

    test('orientation comes from the record, not the live player colour',
        () async {
      // The live settings put the human on white; this archived game was
      // played from black.
      final (_, board) = await _open(botColor: 'w', white: null, black: null);
      expect(board.playerColor, 'b');
      board.dispose();
    });

    test('an import is read from White — there is no "you" in it', () async {
      final (_, board) = await _open(botColor: null);
      expect(board.playerColor, 'w');
      board.dispose();
    });
  });

  group('branching on the board (#196)', () {
    test('an alternative move makes a variation, leaving the game intact',
        () async {
      final (_, board) = await _open();
      board.gotoMainlinePly(1); // after 1. e4
      board.playUci('c7c5'); // the Sicilian instead of what was played

      expect(board.inVariation, isTrue);
      expect(board.tree!.current.san, 'c5');
      expect(board.position.fen, isNot(_kAfterE5),
          reason: 'the board is on the variation, not the game');
      expect(board.tree!.mainline.map((n) => n.san), ['e4', 'e5'],
          reason: 'the archived game is untouched');
      expect(board.moves, hasLength(2),
          reason: 'and so is the move list it drives');
    });

    test('replaying the game\'s own move just walks the game', () async {
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('e7e5'); // what was actually played

      expect(board.inVariation, isFalse);
      expect(board.position.fen, _kAfterE5);
      expect(board.tree!.mainline, hasLength(2),
          reason: 'followed, not cloned beside itself');
    });

    test('you can go back to the played line and carry on', () async {
      // The whole point of the issue.
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      expect(board.inVariation, isTrue);

      board.gotoMainlinePly(2);
      expect(board.inVariation, isFalse);
      expect(board.position.fen, _kAfterE5);
    });

    test('the variation survives going back to the game and is walkable again',
        () async {
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      final branch = board.tree!.current;

      board.gotoMainlinePly(2); // back to the game
      board.gotoNode(branch); // and into the branch again
      expect(board.inVariation, isTrue);
      expect(board.tree!.current.san, 'c5');
    });

    test('discarding a variation returns to the move it left from', () async {
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      board.discardVariation();

      expect(board.inVariation, isFalse);
      expect(board.position.fen, _kAfterE4);
      expect(board.tree!.mainline.first.variations, isEmpty);
    });

    test('stepping inside a variation walks the VARIATION', () async {
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      final sicilianFen = board.position.fen;
      board.stepBack();
      expect(board.position.fen, _kAfterE4);
      board.stepForward();
      expect(board.position.fen, sicilianFen,
          reason: 'not the played game\'s e5');
    });

    test('anchorPly stays on the game while you are off it', () async {
      // What the win chart rings and the move list highlights.
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playUci('c7c5');
      expect(board.reviewAnchorPly, 1);
      expect(board.reviewStoredMove, isNull,
          reason: 'a move never played was never graded');
    });

    test('an illegal move is refused', () async {
      // Through playerMove, NOT playUci: playUci has its own legality guard
      // and returns before reviewPlay is ever reached, so driving this via
      // playUci passed even with reviewPlay's own guard deleted.
      final (_, board) = await _open();
      board.gotoMainlinePly(1);
      board.playerMove(NormalMove.fromUci('e2e4'), 'e4'); // pawn already on e4
      expect(board.inVariation, isFalse);
      expect(board.position.fen, _kAfterE4);
      expect(board.tree!.current.san, 'e4', reason: 'nothing was played');
    });

    test('a move played past the END of the game is a variation', () async {
      // The archive's last node has no children, so an append there used to
      // become children.first — the mainline — and the board showed a position
      // the move list did not contain, with no way back.
      final (_, board) = await _open();
      board.gotoMainlinePly(2); // the last archived move
      board.playUci('g1f3');

      expect(board.inVariation, isTrue);
      expect(board.moves, hasLength(2), reason: 'the archive did not grow');
      expect(board.tree!.mainline, hasLength(2));
      expect(board.reviewStoredMove, isNull);
      board.discardVariation();
      expect(board.inVariation, isFalse);
      expect(board.position.fen, _kAfterE5);
    });

    test('castling matches the archive however the king was dragged',
        () async {
      // dartchess normalises castling to king-takes-rook, which is what a PGN
      // import stores; the lichess/chess.com importers store from+to; an
      // in-app game stores whatever was dragged. Matched by raw string, the
      // ordinary way to castle forked a phantom variation off the played move
      // and dropped its archived grade.
      final settings = await loadSettings();
      final review = ReviewController(_StubDb());
      final board = fakeReviewBoard(review, settings);

      // Build an archive that stores O-O the PGN-import way (e1h1)...
      Position pos = Chess.initial;
      final moves = <Map<String, dynamic>>[];
      var ply = 0;
      for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5']) {
        final m = NormalMove.fromUci(uci);
        final before = pos.fen;
        final (_, san) = pos.makeSan(m);
        pos = pos.play(m);
        moves.add({
          'ply': ++ply,
          'san': san,
          'uci': uci,
          'color': ply.isOdd ? 'w' : 'b',
          'fenBefore': before,
          'fenAfter': pos.fen,
        });
      }
      final castle = pos.parseSan('O-O')! as NormalMove;
      expect(castle.uci, 'e1h1', reason: 'precondition: the import spelling');
      final before = pos.fen;
      final after = pos.play(castle);
      moves.add({
        'ply': ++ply,
        'san': 'O-O',
        'uci': castle.uci,
        'color': 'w',
        'fenBefore': before,
        'fenAfter': after.fen,
        'label': 'good',
      });
      review.open({'id': 'castle', 'botColor': 'b', 'moves': moves});

      board.gotoMainlinePly(6); // just before the castle
      board.playUci('e1g1'); // ...and castle the way a player drags

      expect(board.inVariation, isFalse,
          reason: 'this IS the played move, not a departure from it');
      expect(board.tree!.current.san, 'O-O');
      expect(board.reviewStoredMove?['label'], 'good',
          reason: 'the archived grade came with it');
      expect(board.tree!.mainline, hasLength(7),
          reason: 'no phantom second O-O');
      board.dispose();
    });
  });

  group('a malformed archive row cannot take down the tab', () {
    test('unparseable fens degrade to an empty start position', () async {
      // The save path always writes real fens, but the archive is the one
      // thing here we do not control — an import or an older schema can carry
      // something else, and a FenException thrown inside a ChangeNotifier
      // notification surfaces as a blank tab.
      final settings = await loadSettings();
      final review = ReviewController(_StubDb());
      final board = fakeReviewBoard(review, settings);
      review.open({
        'id': 'bad',
        'moves': [
          {
            'ply': 1,
            'san': 'e4',
            'uci': 'e2e4',
            'color': 'w',
            'fenBefore': 'not-a-fen',
            'fenAfter': 'also-not-a-fen',
          }
        ],
      });

      expect(board.moves, isEmpty);
      expect(board.tree!.mainline, isEmpty);
      expect(board.position.fen, Chess.initial.fen);
      board.dispose();
    });
  });

  test('a live controller is unaffected by any of this', () async {
    // The same getters, on the ordinary controller, still read the settings.
    final settings = await loadSettings(black: kTestBotId);
    final game =
        GameController(FakeArbiter(), const FakeBot({kTestBotId: testBotPersona}),
            FakeGrading(), settings);
    expect(game.reviewing, isFalse);
    expect(game.botEnabled, isTrue);
    expect(game.blackPersona, isNotNull);
    game.dispose();
  });
}
