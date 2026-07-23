// The two affordances the Practice tab grew: the motif picker (#126) and the
// delete button (#137) — the only way a puzzle ever leaves the queue.
//
// Widget-level, because both bugs these guard against are widget-level: a
// picker offering motifs nobody has, and a delete that never reaches the
// controller. The last group measures LAYOUT, which a green suite and a clean
// analyzer say nothing about, under the real bundled Roboto — Ahem's uniform
// squares are not evidence about what a player sees.
//
//   cd flutter && flutter test test/practice_tab_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/practice_tab.dart';

import 'support/game_harness.dart';
import 'support/practice_harness.dart';

const _forkFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pinFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRoboto);

  group('delete', () {
    testWidgets('confirming removes the item from the controller',
        (tester) async {
      final h = makePractice([
        practiceItem(_forkFen, motifs: ['fork']),
        practiceItem(_pinFen, motifs: ['pin']),
      ]);
      h.practice.startSession();
      final served = h.practice.current!['id'] as String;
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete this puzzle?'), findsOneWidget,
          reason: 'an irreversible delete asks first');

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(h.practice.items.map((i) => i['id']), isNot(contains(served)));
      expect(h.practice.items.length, 1);
      // and it is persisted, not just dropped from memory
      expect(h.db.kv['botvinnik-practice-v1'], isNot(contains(served)));
      // the survivor is served rather than the tab going blank
      expect(h.practice.current, isNotNull);
    });

    testWidgets('cancelling keeps it', (tester) async {
      final h = makePractice([practiceItem(_forkFen, motifs: ['fork'])]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(h.practice.items.length, 1);
      expect(h.practice.current?['id'], _forkFen);
    });

    testWidgets('deleting the last one leaves the empty state, not a stale board',
        (tester) async {
      final h = makePractice([practiceItem(_forkFen, motifs: ['fork'])]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(h.practice.items, isEmpty);
      expect(find.textContaining('No puzzles yet'), findsOneWidget);
    });
  });

  group('motif picker', () {
    testWidgets('offers only the motifs the player own items carry',
        (tester) async {
      final h = makePractice([
        practiceItem(_forkFen, motifs: ['fork', 'material']),
        practiceItem(_pinFen, motifs: ['material']),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      expect(find.text('All puzzles (2)'), findsOneWidget);
      expect(find.text('material (2)'), findsOneWidget);
      expect(find.text('fork (1)'), findsOneWidget);
      // nothing invented: 'pin' is a real Motif, and no item has it
      expect(find.textContaining('pin'), findsNothing);

      await tester
          .tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'fork (1)'));
      await tester.pumpAndSettle();
      expect(h.practice.motifFilter, 'fork');
      expect(h.practice.current?['id'], _forkFen);
    });

    testWidgets('and the "all" row clears the filter again', (tester) async {
      // The picker was one-way. PopupMenuButton cannot tell a null-valued
      // selection from a dismissal — popup_menu.dart calls onCanceled and
      // returns before onSelected — so the "All puzzles" row, which had
      // value: null, was inert. The filter lives on the controller and
      // survives re-entering the tab, so a filter that still had items in it
      // could not be cleared for the rest of the session.
      //
      // The test above cannot see this: it only ever taps a NON-null row.
      final h = makePractice([
        practiceItem(_forkFen, motifs: ['fork', 'material']),
        practiceItem(_pinFen, motifs: ['material']),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'fork (1)'));
      await tester.pumpAndSettle();
      expect(h.practice.motifFilter, 'fork', reason: 'precondition');

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(
          find.widgetWithText(CheckedPopupMenuItem<String>, 'All puzzles (2)'));
      await tester.pumpAndSettle();

      expect(h.practice.motifFilter, isNull,
          reason: 'the all row must actually clear it');
    });

    testWidgets('an untagged collection gets no picker at all', (tester) async {
      final h = makePractice([practiceItem(_forkFen)]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      expect(find.byIcon(Icons.filter_list), findsNothing);
    });

    testWidgets('a filter that empties the queue can still be cleared',
        (tester) async {
      // 'fork' is real and present, but its one item is below the serve bar,
      // so the filtered pool is empty and the action row — which holds the
      // picker — is not drawn. Without a way out here the tab is stuck.
      final h = makePractice([
        practiceItem(_forkFen, motifs: ['fork'], drop: 6),
        practiceItem(_pinFen, motifs: ['pin']),
      ]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      h.practice.setMotifFilter('fork');
      await tester.pumpAndSettle();

      expect(h.practice.current, isNull);
      expect(find.textContaining('Nothing to practise tagged fork'),
          findsOneWidget);

      await tester.tap(find.text('Show all puzzles'));
      await tester.pumpAndSettle();
      expect(h.practice.motifFilter, isNull);
      expect(h.practice.current?['id'], _pinFen);
    });
  });

  // The action row now carries two more controls. Its worst case is a failed
  // attempt — Retry and Show best both up — with the picker and the delete
  // beside Next.
  //
  // Only 320 catches the regression today: with the scrolling group replaced
  // by a plain Row and a Spacer, this overflows by 34px at 320 and fits at
  // 375. 375 is kept as the phone-class width, since it is the one most
  // players are on and the row has grown twice now.
  for (final width in [375.0, 320.0]) {
    testWidgets('the action row does not overflow at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final h = makePractice([
        practiceItem(_forkFen, motifs: ['discovered attack']),
        practiceItem(_pinFen, motifs: ['fork']),
      ], arbiter: FakeArbiter(searchLines: kFakeLines));
      h.practice.startSession();
      await _pumpTab(tester, h.practice);

      // e4 from the start position: legal, and not the item's best move, so
      // it fails the check and both extra buttons appear. NOT awaited — the
      // fake arbiter resolves on a timer, and under the test's fake clock a
      // timer only fires while the tester pumps, so awaiting here deadlocks.
      unawaited(h.practice.checkAttempt('e2e4', 'e4', _afterE4Fen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Retry'), findsOneWidget,
          reason: 'the row is not under pressure, so this proves nothing');
      expect(find.text('Show best'), findsOneWidget, reason: 'ditto');
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      // A RenderFlex overflow is a runtime layout error: neither the analyzer
      // nor a green suite says anything about it.
      expect(tester.takeException(), isNull, reason: 'overflowed at $width');
    });
  }

  group('game session banner (#197)', () {
    testWidgets('a game session names its scope and offers the way out',
        (tester) async {
      final h = makePractice([practiceItem(_forkFen), practiceItem(_pinFen)]);
      h.practice.startGameSession({_forkFen});
      await _pumpTab(tester, h.practice);

      expect(find.text("Practising this game's mistakes"), findsOneWidget,
          reason: 'nothing else on the tab says the queue is narrowed');

      // "Practise all" returns to the full queue; the banner goes with it.
      await tester.tap(find.text('Practise all'));
      await tester.pumpAndSettle();

      expect(h.practice.inGameSession, isFalse);
      expect(find.text("Practising this game's mistakes"), findsNothing);
    });

    testWidgets('a normal session shows no banner', (tester) async {
      final h = makePractice([practiceItem(_forkFen)]);
      h.practice.startSession();
      await _pumpTab(tester, h.practice);
      expect(find.text("Practising this game's mistakes"), findsNothing);
    });
  });

  group('why a move is bad (#215)', () {
    testWidgets('a failed attempt names the punishment and offers to play it',
        (tester) async {
      final h = makePractice([practiceItem(_pinFen, bestUci: 'd2d4')]);
      h.practice.startSession();
      // The rendered state a failed attempt reaches — set directly, so the test
      // stays away from the async search (which never resolves under fake time)
      // and the preview timer. The controller path is covered in
      // practice_why_bad_test.dart; this checks only that the card renders it.
      h.practice.attempt = AttemptOutcome(
        san: 'Qh5',
        uci: 'd1h5',
        pass: false,
        drop: 40,
        evalPawns: -5,
        refutationUci: 'e8e1',
        refutationPv: const ['e8e1'],
        punishment: 'Re1 is checkmate.',
      );
      await _pumpTab(tester, h.practice);

      expect(find.textContaining('checkmate'), findsOneWidget,
          reason: 'the card should say WHY, not just the % drop');
      expect(find.text('Watch what it costs'), findsOneWidget);
    });

    testWidgets('a subtler failure shows no punishment line but still plays',
        (tester) async {
      final h = makePractice([practiceItem(_pinFen, bestUci: 'd2d4')]);
      h.practice.startSession();
      h.practice.attempt = AttemptOutcome(
        san: 'Nf3',
        uci: 'g1f3',
        pass: false,
        drop: 18,
        evalPawns: -1,
        refutationUci: 'b8c6',
        refutationPv: const ['b8c6'],
        // no mate, no capture → punishment null; the % drop carries it
      );
      await _pumpTab(tester, h.practice);

      // Still watchable (there's a line), but no "wins your …/checkmate" line.
      expect(find.text('Watch what it costs'), findsOneWidget);
      expect(find.textContaining('checkmate'), findsNothing);
      expect(find.textContaining('wins your'), findsNothing);
    });

    testWidgets('a solved good-enough move shows your move against the best',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700)); // wide layout
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final h = makePractice([practiceItem(_forkFen, bestUci: 'd2d4', bestSan: 'd4')]);
      h.practice.startSession();
      // A pass that ISN'T the best move — the comparison board has something to
      // say (found-the-best passes are filtered out by arrowsFor).
      h.practice.attempt = const AttemptOutcome(
        san: 'Nf3',
        uci: 'g1f3',
        pass: true,
        drop: 2,
        evalPawns: 0.3,
      );
      await _pumpTab(tester, h.practice);

      expect(find.text('You played Nf3'), findsOneWidget);
      expect(find.textContaining('Best was d4'), findsOneWidget);
    });

    testWidgets('an unsolved attempt does not reveal the best move board',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final h = makePractice([practiceItem(_forkFen, bestUci: 'd2d4', bestSan: 'd4')]);
      h.practice.startSession();
      // Failed, best NOT revealed → the comparison must stay hidden (no spoiler).
      h.practice.attempt = const AttemptOutcome(
        san: 'Nf3',
        uci: 'g1f3',
        pass: false,
        drop: 18,
        evalPawns: -1,
        refutationUci: 'b8c6',
        refutationPv: ['b8c6'],
      );
      await _pumpTab(tester, h.practice);

      expect(find.text('You played Nf3'), findsNothing);
      expect(find.textContaining('Best was'), findsNothing);
    });
  });
}
