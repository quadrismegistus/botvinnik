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

      review.next();
      expect(board.position.fen, _kAfterE4);
      expect(board.lastMove?.uci, 'e2e4');
      expect(board.browsing, isFalse);

      review.next();
      expect(board.position.fen, _kAfterE5);
      expect(board.lastMove?.uci, 'e7e5');

      review.goto(0);
      expect(board.position.fen, _kStart);
      expect(board.lastMove, isNull, reason: 'nothing has been played yet');
      board.dispose();
    });

    test('the whole game stays in moves whatever the cursor says', () async {
      // The move list, the chart and the tree's played path all read this,
      // and they show the whole game from any cursor position.
      final (review, board) = await _open();
      expect(board.moves, hasLength(2));
      review.next();
      expect(board.moves, hasLength(2));
      board.dispose();
    });

    test('opening a different game rebuilds the board', () async {
      final (review, board) = await _open();
      review.next();
      expect(board.position.fen, _kAfterE4);

      review.open(_game(id: 'g2'));
      expect(board.position.fen, _kStart, reason: 'a fresh game opens at 0');
      board.dispose();
    });

    test('closing the archive clears the board', () async {
      final (review, board) = await _open();
      review.close();
      expect(board.moves, isEmpty);
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
      review.next();
      review.next();
      review.goto(0);

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
      // engineArrowUcis and `threat` read `blind` BARE, not `blind &&
      // botEnabled` — so a live blind game would strip the arrows and the
      // threat glyphs off an unrelated archived one.
      final settings = await loadSettings(black: kTestBotId);
      settings.blind = true;
      final review = ReviewController(_StubDb());
      final board = fakeReviewBoard(review, settings);
      review.open(_game());
      expect(board.blind, isFalse);
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

  group('review is read-only until #196', () {
    test('a move cannot be played onto the archive', () async {
      // `moves` is the whole archived game while `position` sits at the
      // cursor, so an append here would splice a move onto the end of a list
      // the board is not standing at.
      final (review, board) = await _open();
      review.goto(1);
      board.playUci('e7e5');
      expect(board.moves, hasLength(2), reason: 'nothing appended');
      expect(board.position.fen, _kAfterE4, reason: 'the board did not move');
      board.dispose();
    });

    test('undo and redo refuse', () async {
      final (review, board) = await _open();
      review.goto(2);
      expect(board.canUndo, isFalse);
      expect(board.canRedo, isFalse);
      board.undo();
      expect(board.moves, hasLength(2));
      expect(board.position.fen, _kAfterE5);
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
