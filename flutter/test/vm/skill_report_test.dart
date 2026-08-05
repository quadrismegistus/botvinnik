// The skill report screen (#268): the projection that keeps a bridge call
// slim, and the four cards it draws from canned brain answers.
//
// The projection test is pure Dart — no widget, no bridge. The rendering
// tests use FakeBridge's skillReportUser/skillReportPeer cases
// (test/support/practice_harness.dart) rather than the real bundle: what is
// under test here is the SCREEN's honesty rules (sample floors, no invented
// baseline, the population footer), not brain/report.ts's arithmetic, which
// report.test.ts already pins on the TS side.
//
//   cd flutter && flutter test test/vm/skill_report_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/rating_api.dart';
import 'package:botvinnik_mobile/brain/report_api.dart';
import 'package:botvinnik_mobile/stores/player_rating_store.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/skill_report_screen.dart';

import '../support/memory_db.dart';
import '../support/practice_harness.dart';

// ---- canned brain answers ------------------------------------------------

/// Shape-faithful to brain/report.ts's `skillReportUser` return. Every axis
/// clears its floor by default ([kEvalFloor] 50, [kClockedFloor] 100,
/// [kPanicFloor] 20) — individual tests dial one field down to cross a floor
/// on purpose.
Map<String, dynamic> _userReport({
  int winningN = 120,
  double winningMean = 4.2,
  double winningBlunder = 0.05,
  int losingN = 80,
  double losingMean = 2.4,
  double losingBlunder = 0.03,
  int endgameN = 60,
  double endgameMean = 3.0,
  double endgameBlunder = 0.04,
  int clockedMoves = 300,
  double under2sShare = 0.20,
  double meanThinkS = 8.5,
  int panicN = 40,
  double panicBlunder = 0.08,
  int calmN = 200,
  double calmBlunder = 0.01,
  int considered = 42,
  int humanless = 3,
  int otherClass = 5,
  int noClass = 2,
}) =>
    {
      'timeClass': 'blitz',
      'games': {
        'considered': considered,
        'humanless': humanless,
        'otherClass': otherClass,
        'noClass': noClass,
      },
      'winning': {'n': winningN, 'mean': winningMean, 'blunderRate': winningBlunder},
      'losing': {'n': losingN, 'mean': losingMean, 'blunderRate': losingBlunder},
      'endgame': {'n': endgameN, 'mean': endgameMean, 'blunderRate': endgameBlunder},
      'time': {
        'clockedMoves': clockedMoves,
        'under2sShare': under2sShare,
        'meanThinkS': meanThinkS,
        'panic': {'n': panicN, 'pBlunder': panicBlunder},
        'calm': {'n': calmN, 'pBlunder': calmBlunder},
      },
    };

/// Shape-faithful to `skillReportPeer`'s return (report.ts reshapes t3/t4/t5
/// + t1/t2 into exactly this). Deliberately distinct numbers per axis, so a
/// test can prove ONE axis's numbers are on screen without the others.
Map<String, dynamic> _peerReport({
  double winningMean = 6.5,
  double winningBlunder = 0.10,
  double losingMean = 1.2,
  double losingBlunder = 0.02,
  double endgameMean = 5.5,
  double endgameBlunder = 0.06,
  double under2sShare = 0.30,
  double panicBlunder = 0.09,
  double calmBlunder = 0.02,
}) =>
    {
      'winning': {'n': 2524189, 'mean': winningMean, 'blunderRate': winningBlunder, 'deciles': [0, 0, 0]},
      'losing': {'n': 2247176, 'mean': losingMean, 'blunderRate': losingBlunder, 'deciles': [0, 0, 0]},
      'endgame': {
        'n': 24576,
        'mean': endgameMean,
        'blunderRate': endgameBlunder,
        'deciles': [0, 0, 0],
        'games': 2000,
      },
      'time': {
        'under2sShare': under2sShare,
        'panic': {'n': 400000, 'pBlunder': panicBlunder},
        'calm': {'n': 900000, 'pBlunder': calmBlunder},
      },
      'bookPlyDeciles': [3, 3, 4],
    };

// ---- pumping ---------------------------------------------------------------

/// Pumps [SkillReportScreen] with [bridge] behind ReportApi/RatingApi, and
/// [games] behind ReviewController — the same three providers main.dart
/// wires, minus everything the screen does not read. The screen's _load
/// refreshes the rating store; with no canned [FakeBridge.playerEloResult]
/// the estimate stays null and the band defaults to 1500, which is why the
/// expected verdicts below read "the typical 1500 (blitz)".
Future<void> _pump(WidgetTester tester,
    {required FakeBridge bridge,
    List<Map<String, dynamic>> games = const [],
    Future<String> Function()? loadTables}) async {
  final review = ReviewController(FakeDb())..games = games;
  // MemoryDb, not FakeDb: the screen's _load refreshes the rating store, and
  // refresh reads db.listGames — a FakeDb answers null and the refresh throws
  // (harmlessly, caught) before any canned playerEloResult can land.
  final rating = PlayerRatingStore(MemoryDb(), RatingApi(bridge));
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ReportApi>.value(value: ReportApi(bridge)),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<PlayerRatingStore>.value(value: rating),
    ],
    child: MaterialApp(
      home: SkillReportScreen(
          loadTables: loadTables ?? () async => _fakeTables),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every Text inside the card titled [title], in TREE ORDER. Which column a
/// number sits in is the entire claim this screen makes — a joined blob of
/// all on-screen text cannot see a user/peer swap, because both numbers stay
/// on screen and both verdict phrasings still appear across the three cards
/// (#293 mutation review: the swapped build passed the whole suite).
List<String> _cardTexts(WidgetTester tester, String title) => tester
    .widgetList<Text>(find.descendant(
      of: find
          .ancestor(of: find.text(title), matching: find.byType(Column))
          .first,
      matching: find.byType(Text),
    ))
    .map((t) => t.data ?? '')
    .toList();

/// A minimal `peer-tables.json` stand-in — only `source` (the provenance
/// line reads it) matters here; the actual band/class numbers on screen come
/// from [FakeBridge.skillReportPeerResult], not from parsing this. Resolving
/// via a plain async function rather than the real bundled asset is what
/// keeps this a normal, fast, no-runAsync widget test: rootBundle.loadString
/// is a genuine disk read that a widget test's fake clock cannot drive to
/// completion (see about_test.dart's own rootBundle tests for the same
/// caveat), and [SkillReportScreen.loadTables] exists so a test never has to
/// find that out by timing out.
const String _fakeTables =
    '{"source":"lichess_db_standard_rated_2026-07","brainVersion":2}';

/// Every Text on screen, joined — see player_rating_card_test.dart for the
/// same helper and the same reason (cheaper than a finder per assertion).
String _text(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- the projection (pure, no widget) -----------------------------------

  group('reportGameProjection', () {
    test('strips heavy fields the contract never lists', () {
      final projected = reportGameProjection({
        'botColor': 'b',
        'botBothSides': false,
        'pgn': '[TimeControl "300+0"]\n\n1. e4 *',
        'source': 'lichess', // a StoredGame-level field the contract doesn't want either
        'moves': [
          {
            'ply': 1,
            'san': 'e4',
            'uci': 'e2e4',
            'color': 'w',
            'fenBefore': 'startpos-fen',
            'fenAfter': 'after-fen',
            'evalPawns': 0.3,
            'mate': null,
            'bestMate': null,
            'pctBest': 92.0,
            'wcDrop': 2.0,
            'depth': 22,
            'label': 'best',
            'bestSan': 'e4',
            'bestUci': 'e2e4',
            'bestPv': ['e2e4', 'e7e5'],
            'explanation': {'playedIssue': 'nothing wrong with this at all'},
          },
        ],
      });

      expect(projected['botColor'], 'b');
      expect(projected['botBothSides'], false);
      expect(projected['pgn'], '[TimeControl "300+0"]\n\n1. e4 *');
      expect(projected.containsKey('source'), isFalse,
          reason: 'a game-level field outside the contract must not cross the bridge');

      final move = (projected['moves'] as List).single as Map;
      expect(move.keys.toSet(), {'color', 'evalPawns', 'mate', 'fenBefore', 'san'},
          reason: 'label/bestPv/explanation/wcDrop/etc. are exactly the bytes '
              'the projection exists to drop');
      expect(move['color'], 'w');
      expect(move['evalPawns'], 0.3);
      expect(move['mate'], isNull);
      expect(move['fenBefore'], 'startpos-fen');
      expect(move['san'], 'e4');
    });

    test('declares evalPawns/mate as explicit null, never omits the key', () {
      // A move whose 'mate' key is ABSENT altogether (not merely null) — the
      // shape a StoredMove predating the field, or one report.ts itself never
      // wrote, would have. If the projection let this key stay missing, the
      // marshalled JS object would read `undefined` there, and report.ts's
      // `afterMate !== null` gate treats undefined and null differently
      // (js_bridge_shared.dart's JsBridge.omit documents the same split at
      // the call-argument level) — silently corrupting the walk rather than
      // throwing.
      final projected = reportGameProjection({
        'botColor': 'w',
        'moves': [
          {'color': 'b', 'evalPawns': null, 'san': 'e5', 'fenBefore': 'f1'},
        ],
      });
      final move = (projected['moves'] as List).single as Map;
      expect(move.containsKey('evalPawns'), isTrue);
      expect(move['evalPawns'], isNull);
      expect(move.containsKey('mate'), isTrue,
          reason: 'mate must be DECLARED null, not simply absent');
      expect(move['mate'], isNull);
    });

    test('omits fenBefore/san when the source has none — they are optional', () {
      final projected = reportGameProjection({
        'botColor': 'w',
        'moves': [
          {'color': 'w', 'evalPawns': 0.1, 'mate': null},
        ],
      });
      final move = (projected['moves'] as List).single as Map;
      expect(move.containsKey('fenBefore'), isFalse);
      expect(move.containsKey('san'), isFalse);
    });

    test('an empty or missing moves list projects to an empty list', () {
      expect(reportGameProjection({'botColor': 'w'})['moves'], isEmpty);
      expect(reportGameProjection({'botColor': 'w', 'moves': <Map>[]})['moves'], isEmpty);
    });
  });

  // ---- the screen ----------------------------------------------------------

  group('SkillReportScreen', () {
    testWidgets('renders all four cards, peer numbers beside user numbers',
        (tester) async {
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge);

      expect(find.text('Keeping a won game'), findsOneWidget);
      expect(find.text('Defence when worse'), findsOneWidget);
      expect(find.text('Endgame'), findsOneWidget);
      expect(find.text('Clock discipline'), findsOneWidget);

      final text = _text(tester);
      // winning: user 4.2 < peer 6.5 → "less"
      expect(text, contains('4.2 pts/move'));
      expect(text, contains('6.5 pts/move'));
      expect(text, contains('5.0% blunder rate'));
      expect(text, contains('10.0% blunder rate'));
      expect(text, contains('you leak less than the typical 1500 (blitz)'));
      // losing: user 2.4 > peer 1.2 → "more"
      expect(text, contains('2.4 pts/move'));
      expect(text, contains('1.2 pts/move'));
      expect(text, contains('you leak more than the typical 1500 (blitz)'));
      // endgame: user 3.0 < peer 5.5 → "less" (already covered by the phrase
      // above; the mean figures pin it to THIS card)
      expect(text, contains('3.0 pts/move'));
      expect(text, contains('5.5 pts/move'));
      // time: under-2s share and panic/calm, both columns
      expect(text, contains('20.0%'));
      expect(text, contains('30.0%'));
      expect(text, contains('panic 8.0%'));
      expect(text, contains('calm 1.0%'));
      expect(text, contains('panic 9.0%'));
      expect(text, contains('calm 2.0%'));

      expect(text, isNot(contains('percentile')),
          reason: 'the peer tables pool moves, not players — see the honesty rules');
    });

    testWidgets('below the eval floor: not-enough wording, not a comparison',
        (tester) async {
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport(winningN: 10)
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge);

      expect(find.text('Not enough moves in this slice yet — 10 so far.'),
          findsOneWidget);
      // the winning card's own numbers must not have rendered — the endgame
      // card's own verdict also reads "leak less" (a different comparison,
      // same wording), so the unique figures are what proves THIS card
      // withheld its comparison rather than the phrase alone
      expect(find.textContaining('4.2 pts/move'), findsNothing);
      expect(find.textContaining('6.5 pts/move'), findsNothing);
      expect(find.textContaining('5.0% blunder rate'), findsNothing);
      expect(find.textContaining('10.0% blunder rate'), findsNothing);
      // the OTHER cards still cleared their own floors and rendered fully —
      // proving the gate is per-card, not a screen-wide short-circuit
      expect(find.textContaining('2.4 pts/move'), findsOneWidget);
      expect(find.textContaining('1.2 pts/move'), findsOneWidget);
    });

    testWidgets('a null peer: "no baseline", user numbers still show',
        (tester) async {
      final bridge = FakeBridge()..skillReportUserResult = _userReport();
      // skillReportPeerResult left at its default null — the "no cell for
      // this band/class" case.
      await _pump(tester, bridge: bridge);

      // one per eval card (3) + the time card's under-2s row + its
      // panic/calm row = 5 — never an invented number in their place.
      expect(find.text('no baseline for this band/class'), findsNWidgets(5));
      final text = _text(tester);
      expect(text, contains('4.2 pts/move'));
      expect(text, contains('2.4 pts/move'));
      expect(text, contains('3.0 pts/move'));
      expect(text, contains('panic 8.0%'));
      expect(text, contains('calm 1.0%'));
      // no verdict can be drawn with nothing to compare against
      expect(text, isNot(contains('the typical 1500')));
    });

    testWidgets('the footer states all three excluded counts', (tester) async {
      final bridge = FakeBridge()
        ..skillReportUserResult =
            _userReport(considered: 42, humanless: 3, otherClass: 5, noClass: 2)
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge);

      // The footer is below the four cards, off the default test viewport —
      // ListView only builds what is near the visible area, so the text
      // simply is not in the tree yet without this.
      final footer = find.textContaining('Computed from 42 games · excluded: '
          '3 no human side, 5 other time class, 2 no time control.');
      await tester.scrollUntilVisible(footer, 300);
      expect(
        footer,
        findsOneWidget,
      );
    });

    testWidgets('the You column holds YOUR numbers, in tree order',
        (tester) async {
      // #293 mutation review: a build with every user/peer value swapped
      // (peer present) passed the entire suite — the blob-contains test sees
      // both numbers regardless of column. Tree order is the pin.
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge);
      final texts = _cardTexts(tester, 'Keeping a won game');
      expect(
          texts.take(7).toList(),
          [
            'Keeping a won game',
            'You',
            '4.2 pts/move',
            '5.0% blunder rate',
            'Typical 1500 (blitz)',
            '6.5 pts/move',
            '10.0% blunder rate',
          ],
          reason: 'user first, peer second — the columns ARE the claim');
    });

    testWidgets('a failed table load renders an error and Retry — never a '
        'spinner forever', (tester) async {
      // #293 review: a rejected loadTables (offline web before the asset was
      // ever fetched, a corrupt file, a bridge throw) escaped _load and left
      // _loading true for good — a hang indistinguishable from a bug.
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport();
      var fail = true;
      await _pump(tester, bridge: bridge, loadTables: () async {
        if (fail) throw Exception('offline');
        return _fakeTables;
      });

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Could not load the report'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Keeping a won game'), findsOneWidget,
          reason: 'Retry reruns the whole load');
    });

    testWidgets('the default band FLOORS the rating, like the pipeline does',
        (tester) async {
      // #293 review: the screen rounded while bandFor floors — a 1550 player
      // defaulted into the 1600 cell, whose population is 1600-1699. Half of
      // all ratings landed in the neighbouring band's company.
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport()
        ..playerEloResult = {'elo': 1550, 'se': 40, 'games': 12};
      await _pump(tester, bridge: bridge);
      expect(_text(tester), contains('Typical 1500 (blitz)'));
      expect(_text(tester), isNot(contains('Typical 1600')));
    });

    testWidgets('tables built by a different brain are refused, not mixed',
        (tester) async {
      // The envelope carries brainVersion for exactly this; #293's review
      // found it written and never read. Mixing tables from one win-chance
      // implementation with a user walk from another poisons every verdict.
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge, loadTables: () async =>
          '{"source":"lichess_db_standard_rated_2026-07","brainVersion":1}');
      expect(find.textContaining('built by brain v1'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Keeping a won game'), findsNothing);
    });

    testWidgets('changing the band dropdown re-queries skillReportPeer',
        (tester) async {
      final bridge = FakeBridge()
        ..skillReportUserResult = _userReport()
        ..skillReportPeerResult = _peerReport();
      await _pump(tester, bridge: bridge);

      final before =
          bridge.calls.where((c) => c.fn == 'skillReportPeer').length;
      expect(before, greaterThan(0), reason: 'the initial load must have asked once');
      final firstBand = bridge.calls.lastWhere((c) => c.fn == 'skillReportPeer').args[1];
      expect(firstBand, 1500, reason: 'no rating on record — the default is 1500');

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1600').last);
      await tester.pumpAndSettle();

      final peerCalls = bridge.calls.where((c) => c.fn == 'skillReportPeer').toList();
      expect(peerCalls.length, greaterThan(before),
          reason: 'the band change must have asked again');
      expect(peerCalls.last.args[1], 1600,
          reason: 'the new band must be in the request, not just on screen');
      expect(peerCalls.last.args[2], 'blitz',
          reason: 'the time class did not change — the request should say so too');
    });
  });
}
