// The collection browser (#137 the list, #125 the due column, #49 the attempt
// record): the Practice tab's idle view, and the only place a player can see
// or curate the queue.
//
// Widget-level throughout, because every claim here is a claim about what is
// on screen — that the sub-threshold items are reachable at all (delete is the
// only way anything leaves the collection, so a row that is not drawn is a
// puzzle that cannot be thrown out), that "overdue by 3 days" says three days,
// that the badges are the brain's answers and not a Dart guess. The last group
// measures LAYOUT under the real bundled Roboto: a dense row is where a
// RenderFlex overflow happens, and neither the analyzer nor a green suite says
// anything about one.
//
//   cd flutter && flutter test test/practice_collection_test.dart

import 'dart:io';

import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/practice_tab.dart';

import 'support/game_harness.dart';
import 'support/practice_harness.dart';

// Four distinct legal positions, so each row has its own board and its own id.
const _fenA = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _fenB = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
const _fenC = 'rnbqkbnr/ppp1pppp/8/3p4/8/8/PPPPPPPP/RNBQKBNR w KQkq d6 0 2';
const _fenD = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _pumpTab(WidgetTester tester, PracticeController practice) async {
  final settings = await loadSettings();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PracticeController>.value(value: practice),
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
    ],
    child: const MaterialApp(home: Scaffold(body: PracticeTab())),
  ));
  await tester.pumpAndSettle();
}

DateTime _ago(Duration d) => DateTime.now().subtract(d);
DateTime _ahead(Duration d) => DateTime.now().add(d);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRoboto);

  group('the list', () {
    testWidgets('shows every collected position, most overdue first',
        (tester) async {
      final h = makePractice([
        // deliberately out of due order in the stored array
        practiceItem(_fenA, playedSan: 'Qh5', dueAt: _ahead(const Duration(days: 2))),
        practiceItem(_fenB, playedSan: 'Nf3', dueAt: _ago(const Duration(days: 3))),
        // _fenD is BLACK to move, so the orientation assertion below is not
        // trivially satisfied by three white-to-move fixtures.
        practiceItem(_fenD, playedSan: 'Ke2', dueAt: _ago(const Duration(hours: 4))),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      // A thumbnail per row, showing THAT ROW'S position from the side to
      // move. Counting widgets is not enough: `flutter test` resolves neither
      // the piece images nor the board texture, so every board paints as a
      // blank box — hard-coding all three to the start position, or forcing
      // one orientation, left this file green. Read the widget's own fields.
      final boards = tester.widgetList<StaticChessboard>(
          find.byType(StaticChessboard)).toList();
      expect(boards, hasLength(3));
      expect(boards.map((b) => b.fen).toSet(), hasLength(3),
          reason: 'three rows, three positions');
      expect(boards.map((b) => b.orientation).toSet(), hasLength(greaterThan(1)),
          reason: 'orientation follows each position\'s side to move');

      double y(String san) =>
          tester.getTopLeft(find.textContaining('played $san')).dy;
      expect(y('Nf3'), lessThan(y('Ke2')), reason: '3 days overdue before 4 hours');
      expect(y('Ke2'), lessThan(y('Qh5')), reason: 'overdue before not yet due');
    });

    testWidgets('counts the collection, the queue and what is due',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA), // due now, above the 15% bar
        practiceItem(_fenB, dueAt: _ahead(const Duration(days: 2))),
        practiceItem(_fenC, drop: 6), // collected but under the bar
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.text('3 collected · 2 in the queue · 1 due'), findsOneWidget);
    });

    // The curation claim from #137's decision: a takeback does not remove the
    // blunder, so delete is the only exit — and an item the threshold will
    // never serve is exactly the one a player wants gone. If the list showed
    // `servable` it would be permanently unreachable.
    testWidgets('lists the items the queue will not serve, and says why',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA),
        practiceItem(_fenB, playedSan: 'Ke2', drop: 6),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.textContaining('played Ke2'), findsOneWidget,
          reason: 'a sub-threshold item must still be reachable');
      expect(find.textContaining('not queued — under 15%'), findsOneWidget);
    });

    testWidgets('a sub-threshold item can be deleted from the list',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA),
        practiceItem(_fenB, playedSan: 'Ke2', drop: 6),
      ]);
      h.practice.startSession();
      expect(h.practice.current?['id'], _fenA, reason: 'precondition');
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      // The row for the item that is NOT being drilled, so this is a delete
      // the drill view could not have performed.
      final row = find.ancestor(
          of: find.textContaining('played Ke2'), matching: find.byType(Row));
      await tester.tap(find.descendant(
          of: row.first, matching: find.byIcon(Icons.delete_outline)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(h.practice.items.map((i) => i['id']), [_fenA]);
      expect(h.db.kv['botvinnik-practice-v1'], isNot(contains(_fenB)),
          reason: 'and it is persisted, not just dropped from memory');
      expect(h.practice.current?['id'], _fenA,
          reason: 'deleting another row must not disturb the served puzzle');
    });

    testWidgets('the difficulty badge is the brain answer for that row',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA, playedSan: 'Qh5'),
        practiceItem(_fenB, playedSan: 'Ke2'),
      ]);
      h.bridge.difficulties[_fenA] = 'hard';
      h.bridge.difficulties[_fenB] = 'easy';
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      // Per row, not one constant for the list.
      expect(find.text('hard'), findsOneWidget);
      expect(find.text('easy'), findsOneWidget);
    });
  });

  // #125: when each item is due, in the terms a queue is read in.
  group('due', () {
    for (final (label, due, expected) in [
      ('three days overdue', -3.0 * 1440, 'overdue by 3 days'),
      ('four hours overdue', -4.0 * 60, 'overdue by 4 hours'),
      ('one hour overdue', -65.0, 'overdue by 1 hour'),
      ('ten minutes overdue', -10.0, 'due now'),
      ('due in ten minutes', 10.0, 'due now'),
      ('due in six hours', 6.0 * 60, 'due in 6 hours'),
      ('due in a week', 7.0 * 1440, 'due in 7 days'),
    ]) {
      testWidgets('$label reads "$expected"', (tester) async {
        final h = makePractice([
          practiceItem(_fenA,
              dueAt: DateTime.now().add(Duration(minutes: due.round()))),
        ]);
        h.practice.startSession();
        await _pumpTab(tester, h.practice);
        await tester.tap(find.byIcon(Icons.format_list_bulleted));
        await tester.pumpAndSettle();

        expect(find.textContaining('$expected · '), findsOneWidget);
      });
    }
  });

  // #49: attempts and correct are counts. `lastResult` is overwritten by every
  // recordResult (brain/practice.ts), so there is no per-attempt trail — a
  // sparkline would be inventing an order. These pin what IS known.
  group('attempt record', () {
    testWidgets('a tried item shows the ratio and the last verdict',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA, attempts: 5, correct: 2, lastResult: 'fail'),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 of 5 correct'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget,
          reason: 'the last attempt failed; the close icon is that verdict');
    });

    testWidgets('an untried item says so instead of showing 0 of 0',
        (tester) async {
      final h = makePractice([practiceItem(_fenA)]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.textContaining('never tried'), findsOneWidget);
      expect(find.textContaining('0 of 0'), findsNothing);
    });

    // The unmixed records: nothing but passes, and nothing but failures. Both
    // bars are count-weighted, so these are the rows where a band is empty —
    // and 0/4 is the one a player most needs to read off the list, since it is
    // the puzzle they keep getting wrong.
    testWidgets('an all-pass and an all-fail record both read correctly',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA, attempts: 3, correct: 3, lastResult: 'pass'),
        practiceItem(_fenB, attempts: 4, correct: 0, lastResult: 'fail'),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 of 3 correct'), findsOneWidget);
      expect(find.textContaining('0 of 4 correct'), findsOneWidget);
      expect(find.text('0 mastered · 2 learning · 0 new'), findsOneWidget,
          reason: 'and two of the three mastery bands are empty');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the mastery bar counts mastered, learning and new',
        (tester) async {
      final h = makePractice([
        // Mastered AND under the serve threshold, which is the case that says
        // which collection the bar is over. It has to be the whole one: an
        // item you mastered before raising the threshold did not become less
        // mastered by dropping out of the queue, and counting only `servable`
        // would quietly erase your record every time you tightened the filter.
        practiceItem(_fenA, box: 4, attempts: 6, correct: 5, drop: 6),
        practiceItem(_fenB, box: 1, attempts: 2, correct: 1), // learning
        practiceItem(_fenC), // fresh
        practiceItem(_fenD), // fresh
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      expect(find.text('1 mastered · 1 learning · 2 new'), findsOneWidget);
    });
  });

  group('routes', () {
    testWidgets('the list opens from the drill and closes back onto it',
        (tester) async {
      final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)]);
      h.practice.startSession();
      final served = h.practice.current!['id'] as String;
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();
      expect(find.text('2 positions · 2 due'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.format_list_bulleted), findsOneWidget,
          reason: 'back on the drill, whose action row this is');
      expect(h.practice.current?['id'], served,
          reason: 'browsing is view state — it must not reshuffle the drill');
    });

    testWidgets('tapping a row drills that exact position', (tester) async {
      final h = makePractice([
        practiceItem(_fenA, playedSan: 'Qh5'),
        practiceItem(_fenB, playedSan: 'Ke2'),
        practiceItem(_fenC, playedSan: 'Na3'),
      ]);
      h.practice.startSession();
      expect(h.practice.current?['id'], _fenA, reason: 'precondition');
      await _pumpTab(tester, h.practice);
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('played Na3'));
      await tester.pumpAndSettle();

      expect(h.practice.current?['id'], _fenC);
      expect(find.text('3 positions · 3 due'), findsNothing,
          reason: 'and the list gets out of the way');
    });

    // The old idle state told this player they had no puzzles while holding a
    // collection: everything ≥5% is collected and the threshold filters at
    // serve time, so a default 15% setting routinely leaves items that cannot
    // be served. That is not "no puzzles yet", it is a queue with a reason.
    testWidgets('nothing servable shows the collection, not "No puzzles yet"',
        (tester) async {
      final h = makePractice([
        practiceItem(_fenA, playedSan: 'Qh5', drop: 6),
        practiceItem(_fenB, playedSan: 'Ke2', drop: 9),
      ]);
      h.practice.startSession();
      expect(h.practice.current, isNull, reason: 'precondition: nothing to serve');
      await _pumpTab(tester, h.practice);

      expect(find.textContaining('No puzzles yet'), findsNothing);
      expect(find.textContaining('played Qh5'), findsOneWidget);
      expect(find.textContaining('played Ke2'), findsOneWidget);
      expect(find.textContaining('below the 15% drop you set'), findsOneWidget);
      // Nothing to go back to, so nothing pretends there is.
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('an empty collection still says so', (tester) async {
      final h = makePractice([]);
      await _pumpTab(tester, h.practice);
      expect(find.textContaining('No puzzles yet'), findsOneWidget);
    });
  });

  // A collection row is dense: thumbnail, two lines of prose, a badge, a due
  // string, the attempt record and a delete. This is its worst case — the
  // longest motif list the tagger emits, a two-digit drop, five attempts and
  // an overdue string — at the two widths that matter.
  group('layout', () {
    for (final width in [375.0, 320.0]) {
      testWidgets('a full row does not overflow at $width', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final h = makePractice([
          practiceItem(_fenA,
              motifs: ['discovered attack', 'back-rank mate', 'free capture'],
              playedSan: 'Qxh7+',
              bestSan: 'Rxd8+',
              drop: 47,
              attempts: 5,
              correct: 2,
              lastResult: 'fail',
              dueAt: _ago(const Duration(days: 12))),
          practiceItem(_fenB, drop: 6),
        ]);
        h.practice.startSession();
        await _pumpTab(tester, h.practice);
        await tester.tap(find.byIcon(Icons.format_list_bulleted));
        await tester.pumpAndSettle();

        // The row is under pressure, or this proves nothing.
        expect(find.textContaining('discovered attack'), findsOneWidget);
        expect(find.textContaining('overdue by 12 days'), findsOneWidget);
        expect(find.text('2 collected · 1 in the queue · 1 due'), findsOneWidget);

        expect(tester.takeException(), isNull,
            reason: 'the collection row overflowed at $width');
      });
    }
  });
  // #123 item 2: maybeCollect now reports what it did, so the insight card can
  // say it at the moment the move is graded rather than leaving the player to
  // find the puzzle later with no memory of the position.
  group('maybeCollect reports its verdict', () {
    Map<String, dynamic> stored(String fen,
            {double wcDrop = 20, int depth = 22}) =>
        {
          'fenBefore': fen,
          'san': 'Qh5',
          'uci': 'd1h5',
          'bestSan': 'Nf3',
          'bestUci': 'g1f3',
          'wcDrop': wcDrop,
          'depth': depth,
        };

    test('a fresh over-threshold move is added', () async {
      final h = makePractice([]);
      final outcome = await h.practice.maybeCollect(stored(_fenA));
      expect(outcome, CollectOutcome.added);
      expect(h.practice.items.map((i) => i['fen']), [_fenA]);
    });

    test('a move for a position already collected is a duplicate', () async {
      final h = makePractice([practiceItem(_fenA)]);
      final outcome = await h.practice.maybeCollect(stored(_fenA));
      expect(outcome, CollectOutcome.duplicate,
          reason: 'the fen is already a puzzle — nothing new to add');
      expect(h.practice.items, hasLength(1), reason: 'and it stays one item');
    });

    test('a move under the collect floor is not eligible', () async {
      final h = makePractice([]);
      // kCollectMin is 5; 3 is below the floor everything is collected at.
      final outcome = await h.practice.maybeCollect(stored(_fenA, wcDrop: 3));
      expect(outcome, CollectOutcome.notEligible);
      expect(h.practice.items, isEmpty);
    });

    test('a move graded too shallow to trust is not eligible', () async {
      final h = makePractice([]);
      // over the drop floor, but the grade is only depth 5 — below minDepth 8,
      // so the loss is not yet worth committing to a puzzle.
      final outcome =
          await h.practice.maybeCollect(stored(_fenA, depth: 5));
      expect(outcome, CollectOutcome.notEligible);
      expect(h.practice.items, isEmpty);
    });
  });

  testWidgets('tapping a sub-threshold row serves it anyway', (tester) async {
    // serveItem searches `items`, not `servable`, and says so — "practise this
    // one anyway" is the whole reason the browser lists sub-threshold puzzles
    // it cannot queue. Searching `servable` instead makes the tap a dead one:
    // nothing is served, but the list still closes, which is exactly the "No
    // puzzles yet" dead end the browser exists to remove.
    final h = makePractice([
      practiceItem(_fenA, drop: 3), // under the 15% collect threshold
    ]);
    expect(h.practice.servable, isEmpty, reason: 'precondition: not queueable');

    h.practice.serveItem(_fenA);
    expect(h.practice.current?['id'], _fenA,
        reason: 'a row you tap is served whether or not it is queueable');
  });

}
