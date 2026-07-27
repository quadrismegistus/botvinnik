// Review's move comparison as a PICTURE (#233): the mini-board in the verdict
// strip, showing the move played and the move the engine wanted on the
// position the move was chosen in.
//
// Review used to say "best: Nf3" in 12pt grey and leave you to find Nf3 on the
// board yourself, while the Insight card had drawn the same fact as a board
// since #185. This is the third consumer of one [MovePreview], so most of what
// could go wrong is in the WIRING rather than the drawing: which position it
// gets, which way up it is, which of the two constructors it picks, and what
// it costs the board underneath it.
//
// Pumps the real [ReviewBody] over a real [ReviewController], with the real
// bundled Roboto — the strip's height is a claim layout.dart makes in a
// constant, and a font that measures nothing (Ahem's uniform squares) is no
// evidence about it.
//
//   cd flutter && flutter test test/review_preview_test.dart

import 'dart:io';

// `show`, not a bare import: dartchess exports its own `File` (a board file,
// a-h) which otherwise shadows dart:io's and takes the font loader with it.
import 'package:dartchess/dartchess.dart'
    show Chess, NormalMove, Setup, Side, Square;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/db/app_db.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/board_pane.dart';
import 'package:botvinnik_mobile/ui/grade_strip.dart';
import 'package:botvinnik_mobile/ui/layout.dart';
import 'package:botvinnik_mobile/ui/move_preview.dart';
import 'package:botvinnik_mobile/ui/review_screen.dart';

import '../support/game_harness.dart';

const _kClassRaw = {
  'best': {'glyph': '★', 'color': '#81b64c', 'noun': 'the best move'},
  'inaccuracy': {'glyph': '?!', 'color': '#f0c15c', 'noun': 'an inaccuracy'},
  'blunder': {'glyph': '??', 'color': '#ca3431', 'noun': 'a blunder'},
};

class _StubDb implements AppDb {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// Fens DERIVED by playing, not typed: dartchess drops an en-passant square no
/// capture can reach, so a hand-written "after 1.e4" fen is one this app never
/// writes and the tree would fork off it (review_board_test.dart made the same
/// point the hard way).
final _start = Chess.initial;
final _afterE4 = _start.play(NormalMove.fromUci('e2e4'));
final _afterE5 = _afterE4.play(NormalMove.fromUci('e7e5'));
final _afterNf3 = _afterE5.play(NormalMove.fromUci('g1f3'));

/// A three-ply game covering the three cases the strip has to tell apart.
///
///   1. e4  — played, engine wanted d4: the red/green pair.
///   2. e5  — the engine's own move: one blue arrow.
///   3. Nf3 — LABELLED best, but bestUci is d2d4. Not a contrivance: see the
///      test that reads it.
Map<String, dynamic> _game({String? botColor = 'b'}) => {
      'id': 'g-1',
      'endedAt': '2026-07-26T09:00:00.000',
      'botColor': botColor,
      'moves': [
        {
          'ply': 1,
          'san': 'e4',
          'uci': 'e2e4',
          'color': 'w',
          'fenBefore': _start.fen,
          'fenAfter': _afterE4.fen,
          'label': 'inaccuracy',
          'bestSan': 'd4',
          'bestUci': 'd2d4',
        },
        {
          'ply': 2,
          'san': 'e5',
          'uci': 'e7e5',
          'color': 'b',
          'fenBefore': _afterE4.fen,
          'fenAfter': _afterE5.fen,
          'label': 'best',
          'bestSan': 'e5',
          'bestUci': 'e7e5',
        },
        {
          'ply': 3,
          'san': 'Nf3',
          'uci': 'g1f3',
          'color': 'w',
          'fenBefore': _afterE5.fen,
          'fenAfter': _afterNf3.fen,
          'label': 'best',
          'bestSan': 'd4',
          'bestUci': 'd2d4',
        },
      ],
    };

/// The same game with an explanation on ply 1 — the TALLEST real strip, and
/// the state every height assertion here used to miss. `_game()` carries no
/// 'explanation' key, so `prose` was null at every ply and the strip was
/// measured in its easiest form.
Map<String, dynamic> _withProse() {
  final g = _game();
  // A fresh list, not a write through `.cast()`: `_game()`'s moves literal
  // infers as List<Map<String, Object>>, so assigning a Map<String, dynamic>
  // back into a cast view of it throws at the reverse check.
  final ms = <Map<String, dynamic>>[
    for (final m in (g['moves'] as List).cast<Map<String, dynamic>>())
      <String, dynamic>{...m}
  ];
  ms[0]['explanation'] = <String, dynamic>{
    'playedIssue': 'It drops the e-pawn to a knight fork that also hits the '
        'queen, and there is no way to hold both.'
  };
  return {...g, 'moves': ms};
}

/// The same shape with every grade stripped: what `gameFromPgn` writes, and
/// the game that must not pay for a mini-board it can never draw.
Map<String, dynamic> _ungraded() {
  final g = _game();
  return {
    ...g,
    'id': 'import-1',
    'moves': [
      for (final m in g['moves'] as List)
        {...(m as Map).cast<String, dynamic>()}
          ..remove('label')
          ..remove('bestSan')
          ..remove('bestUci'),
    ],
  };
}

/// One move, from a position where the only choice is which piece to promote
/// to. e8=Q and e8=N leave from the same square and land on the same square,
/// so two arrows would be one line — [MovePreview.arrowsFor] refuses it and
/// only a sentence can tell them apart.
final _promoBefore =
    Chess.fromSetup(Setup.parseFen('8/4P3/8/8/8/8/8/K6k w - - 0 1'));
final _promoAfter = _promoBefore.play(NormalMove.fromUci('e7e8q'));

Map<String, dynamic> _promotion() => {
      'id': 'promo-1',
      'endedAt': '2026-07-26T09:00:00.000',
      'botColor': 'b',
      'moves': [
        {
          'ply': 1,
          'san': 'e8=Q',
          'uci': 'e7e8q',
          'color': 'w',
          'fenBefore': _promoBefore.fen,
          'fenAfter': _promoAfter.fen,
          'label': 'blunder',
          'bestSan': 'e8=N',
          'bestUci': 'e7e8n',
        },
      ],
    };

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

Future<ReviewBoardController> _pump(
  WidgetTester tester,
  Map<String, dynamic> game, {
  double width = 390,
  double height = 844,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final settings = await loadSettings();
  final review = ReviewController(_StubDb())..open(game);
  final board = fakeReviewBoard(review, settings);
  addTearDown(board.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ClassTable>.value(value: const ClassTable(_kClassRaw)),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<ReviewBoardController>.value(value: board),
    ],
    child: const MaterialApp(home: Scaffold(body: ReviewBody())),
  ));
  await tester.pump();
  return board;
}

Future<void> _goto(WidgetTester tester, ReviewBoardController board, int ply) async {
  board.gotoMainlinePly(ply);
  await tester.pump();
}

MovePreview _preview(WidgetTester tester) =>
    tester.widget<MovePreview>(find.byType(MovePreview));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRoboto);

  group('the comparison is drawn, not named (#233)', () {
    testWidgets('on the position the move was chosen in', (tester) async {
      final board = await _pump(tester, _game());
      await _goto(tester, board, 1);

      final p = _preview(tester);
      // fenBefore, not fenAfter and not whatever the analysis board is showing.
      // This is the assertion #194's objection turns on: on the position AFTER
      // the move, the best move's from-square may be empty or hold something
      // else, and the arrow would be drawn from it anyway.
      expect(p.fen, _start.fen);
      expect(p.playedSan, 'e4');
      expect(p.bestSan, 'd4');
      expect(p.played!.from, Square.e2);
      expect(p.best!.from, Square.d2);
      expect(p.best!.to, Square.d4);
    });

    testWidgets('and the sentence it replaces is gone', (tester) async {
      // The legend already reads "Best was d4". Keeping the old grey "best: d4"
      // in the header would name the same move twice in one strip.
      final board = await _pump(tester, _game());
      await _goto(tester, board, 1);

      expect(find.text('Best was d4'), findsOneWidget);
      expect(find.text('best: d4'), findsNothing);
    });

    testWidgets('the start position has nothing to compare', (tester) async {
      final board = await _pump(tester, _game());
      await _goto(tester, board, 0);
      expect(find.byType(MovePreview), findsNothing);
      expect(find.text('Start position'), findsOneWidget);
    });

    testWidgets('a move that WAS the engine\'s gets one arrow, not two',
        (tester) async {
      final board = await _pump(tester, _game());
      await _goto(tester, board, 2);

      final p = _preview(tester);
      // MovePreview.same: red under green on the identical line would read as
      // one arrow anyway, in the loser's colour (#185).
      expect(p.same, isNotNull);
      expect(p.played, isNull);
      expect(find.textContaining('also the best move'), findsOneWidget);
    });

    testWidgets('a move LABELLED best, whose uci is not bestUci, still compares',
        (tester) async {
      // Not a contrived record. backfillGrade widens isBest to any move
      // scoring 100% under the deeper post-move search, while bestUci stays
      // pinned to the pre-move MultiPV winner — so label 'best' with a
      // different bestUci is routine. Keyed off the LABEL, this strip would
      // draw the played move in the engine's blue captioned "also the best
      // move" for a move the engine did not pick, which is the exact bug #185
      // fixed in the Insight card.
      final board = await _pump(tester, _game());
      await _goto(tester, board, 3);

      final p = _preview(tester);
      expect(p.same, isNull, reason: 'g1f3 is not d2d4');
      expect(p.playedSan, 'Nf3');
      expect(p.bestSan, 'd4');
    });

    testWidgets('a promotion differing only in the piece falls back to words',
        (tester) async {
      // e7e8q and e7e8n share both squares, so the arrows would overlap
      // exactly and the picture would say "you played the engine's move".
      final board = await _pump(tester, _promotion());
      await _goto(tester, board, 1);

      expect(find.byType(MovePreview), findsNothing);
      expect(find.text('best: e8=N'), findsOneWidget,
          reason: 'the sentence is the fallback, not a leftover');
    });

    testWidgets('an ungraded import draws neither', (tester) async {
      final board = await _pump(tester, _ungraded());
      await _goto(tester, board, 1);

      expect(find.byType(MovePreview), findsNothing);
      expect(find.textContaining('best:'), findsNothing);
      expect(find.text('e4'), findsWidgets, reason: 'the verdict strip is still there');
    });
  });

  group('it agrees with the board above it', () {
    // The one place this departs from the Insight card, which orients to the
    // MOVER because it has no board of its own to contradict. Here a
    // mini-board that turned over every half-move would be a second frame of
    // reference two inches below the first.
    testWidgets('white at the bottom for a black move, when you were White',
        (tester) async {
      final board = await _pump(tester, _game(botColor: 'b'));
      expect(board.whiteAtBottom, isTrue, reason: 'precondition');
      await _goto(tester, board, 2); // Black's move

      expect(_preview(tester).orientation, Side.white,
          reason: "the mover's own side would be black here");
    });

    testWidgets('and black at the bottom for a white move, when you were Black',
        (tester) async {
      // The mirror. Without it, "always Side.white" passes the test above.
      final board = await _pump(tester, _game(botColor: 'w'));
      expect(board.whiteAtBottom, isFalse, reason: 'precondition');
      await _goto(tester, board, 1); // White's move

      expect(_preview(tester).orientation, Side.black);
    });
  });

  group('what it costs the board', () {
    // Everything here is about the narrow stacked layout, where the board is
    // sized against a CONSTANT rather than against the strip's real height.

    testWidgets('scrubbing never resizes the board', (tester) async {
      // The strip's height varies by ply — ply 1 has a mini-board and a
      // two-line prose slot, the start position has one line. The board must
      // not move with it: a board that resized under the player as they
      // scrubbed is the same fault #231 avoided in the rated shell.
      //
      // Short AND narrow on purpose: on a phone the board is width-limited and
      // this passes for a reason that has nothing to do with the reservation.
      final board = await _pump(tester, _game(), width: 620, height: 560);
      final sizes = <Size>[];
      for (final ply in [0, 1, 2, 3, 0]) {
        await _goto(tester, board, ply);
        sizes.add(tester.getSize(find.byType(BoardPane)));
      }
      expect(sizes.toSet(), hasLength(1), reason: 'the board moved: $sizes');
    });

    // The rule this replaced was weaker AND wrong-shaped: it asserted that an
    // ungraded import keeps the 120px a graded game spends on the preview,
    // which was true when the preview could cost board height. Since #239 it
    // cannot — `reviewShowsPreview` draws it if and only if it is FREE — so
    // the honest claim is stronger and covers every viewport rather than one.
    for (final (label, w, h) in [
      ('320x480, portrait and cramped', 320.0, 480.0),
      ('320x568, the SE', 320.0, 568.0),
      ('390x844', 390.0, 844.0),
      ('568x320, landscape', 568.0, 320.0),
      ('620x520, narrow and short', 620.0, 520.0),
      ('800x600, desktop', 800.0, 600.0),
    ]) {
      testWidgets('the preview costs the board nothing ($label)',
          (tester) async {
        // Both controllers stay alive to the end — addTearDown disposes them,
        // and disposing one here would be a second dispose.
        await _pump(tester, _game(), width: w, height: h);
        final graded = tester.getSize(find.byType(BoardPane));

        await _pump(tester, _ungraded(), width: w, height: h);
        final imported = tester.getSize(find.byType(BoardPane));

        expect(graded, imported,
            reason: 'a graded game got a smaller board than an import at $label');
      });
    }

    testWidgets('the strip fits what layout.dart reserves for it',
        (tester) async {
      // kMovePreview is a number in a constant, and a constant nothing
      // measures goes stale the first time the preview grows. Budget: the
      // strip's own share of kReviewFixed (which also covers the 52px scrub
      // bar) plus kMovePreview.
      // At the NARROWEST width and WITH prose, which is where the strip is
      // tallest — 184px, against the 178 the first version of this reserved.
      // Measured at 390pt with no explanation, 112 looked like plenty.
      const budget = kReviewFixed - 52 + kMovePreview;
      for (final (label, w, h) in [
        ('390pt', 390.0, 844.0),
        ('320pt', 320.0, 900.0), // tall enough that the preview is still drawn
      ]) {
        final board = await _pump(tester, _withProse(), width: w, height: h);
        expect(reviewShowsPreview(w, h), isTrue, reason: 'precondition at $label');
        for (final ply in [0, 1, 2, 3]) {
          await _goto(tester, board, ply);
          final got = tester
              .getSize(find.byKey(const ValueKey('review-verdict')))
              .height;
          expect(got, lessThanOrEqualTo(budget),
              reason: 'strip is ${got}px at ply $ply, $label; budget $budget');
        }
      }
    });

    // Every phone the app targets, in the state that costs the most: a graded
    // move whose explanation wraps. This is the assertion that "a phone pays
    // nothing at all" should have been. That one measured the BOARD, which
    // genuinely does not move on a phone — because the 120px comes out of the
    // move list instead, and Expanded absorbs it silently down to zero. At
    // 320x568 with prose the list was 8px.
    for (final (label, width, height) in [
      // The two #239 was filed about. 568x320 stacked a 202px board over the
      // furniture and left the list at 8px; 320x480 left it at 42.
      ('568x320, landscape', 568.0, 320.0),
      ('320x480, portrait and cramped', 320.0, 480.0),
      ('320x568, the SE', 320.0, 568.0),
      ('375x667', 375.0, 667.0),
      ('390x844', 390.0, 844.0),
      ('620x520, narrow and short', 620.0, 520.0),
      ('720x620, at the breakpoint', 720.0, 620.0),
      ('800x600, desktop', 800.0, 600.0),
    ]) {
      testWidgets('the move list survives a graded move with prose ($label)',
          (tester) async {
        final board =
            await _pump(tester, _withProse(), width: width, height: height);
        await _goto(tester, board, 1);

        expect(tester.getSize(find.byType(ListView)).height,
            greaterThanOrEqualTo(kMinMoveList),
            reason: 'the move list was squeezed out at $label');
        expect(tester.takeException(), isNull, reason: 'overflowed at $label');
      });
    }

    testWidgets('a landscape phone puts the board BESIDE the list (#239)',
        (tester) async {
      // The shape, not just the floor. Stacked at 568x320 the list came out at
      // 8px — a board, a verdict and no game — and because the list is
      // `Expanded` it absorbed that silently instead of overflowing. Landscape
      // is the case where the width exists and the height does not, so the Row
      // the wide layout already uses is the answer rather than another
      // subtraction.
      final board = await _pump(tester, _withProse(), width: 568, height: 320);
      await _goto(tester, board, 1);

      final b = tester.getRect(find.byType(BoardPane));
      final list = tester.getRect(find.byType(ListView));
      expect(b.right, lessThanOrEqualTo(list.left),
          reason: 'the board is still stacked above the list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('but a cramped PORTRAIT one keeps stacking', (tester) async {
      // The control, and it is the reason the rule is `width > height` rather
      // than "small". Side by side at 320pt the board takes 240 and the list
      // gets 80 wide, which is not a move list — so 320x480 must stay stacked
      // and pay for its list out of board HEIGHT instead (reviewStackedBoard).
      final board = await _pump(tester, _withProse(), width: 320, height: 480);
      await _goto(tester, board, 1);

      final b = tester.getRect(find.byType(BoardPane));
      final list = tester.getRect(find.byType(ListView));
      expect(b.bottom, lessThanOrEqualTo(list.top),
          reason: 'a narrow portrait viewport must not go side by side');
      expect(list.width, greaterThan(300), reason: 'the list has the full width');
    });

    testWidgets('a viewport too short for the mini-board falls back to words',
        (tester) async {
      // The mini-board yields, not the list and not the board. The strip keeps
      // its fallback sentence, which is the same one a promotion gets.
      final board = await _pump(tester, _withProse(), width: 320, height: 568);
      await _goto(tester, board, 1);

      expect(reviewShowsPreview(320, 568), isFalse, reason: 'precondition');
      expect(find.byType(MovePreview), findsNothing);
      expect(find.text('best: d4'), findsOneWidget,
          reason: 'the fact is still there, just not as a picture');
    });

    testWidgets('and a viewport with room for it draws it', (tester) async {
      // The control: without it, "never draw the preview" passes the test
      // above and every list-height assertion in this file.
      final board = await _pump(tester, _withProse(), width: 390, height: 844);
      await _goto(tester, board, 1);

      expect(reviewShowsPreview(390, 844), isTrue, reason: 'precondition');
      expect(find.byType(MovePreview), findsOneWidget);
      expect(find.text('best: d4'), findsNothing);
    });

    testWidgets('whether it is drawn cannot change under a scrub',
        (tester) async {
      // A per-ply answer would make the board resize as the player steps
      // through the game. It is per viewport and per game, so stepping across
      // a ply that HAS prose and one that has not cannot flip it.
      final board = await _pump(tester, _withProse(), width: 390, height: 844);
      final seen = <bool>{};
      final sizes = <Size>{};
      for (final ply in [0, 1, 2, 3, 1, 0]) {
        await _goto(tester, board, ply);
        seen.add(find.byType(MovePreview).evaluate().isNotEmpty || ply == 0);
        sizes.add(tester.getSize(find.byType(BoardPane)));
      }
      expect(seen, {true});
      expect(sizes, hasLength(1));
    });
  });
}
