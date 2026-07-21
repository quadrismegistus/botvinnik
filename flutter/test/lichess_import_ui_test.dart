// The lichess import as the user meets it: a button in the Review tab, a
// username, and — the part that makes this more than a convenience — a
// practice queue that afterwards holds the blunders from those games (#134).
//
// Everything below the widgets is real: the brain maps the games (through
// node), PracticeController collects through its own public API, and both the
// archive and the practice kv row are written to an in-memory AppDb. Only the
// network is faked, and it answers with a captured lichess response.
//
// Loads the REAL bundled Roboto and runs at 375px, because a green suite says
// nothing about whether a dialog fits on a phone.
//
//   cd flutter && flutter test test/lichess_import_ui_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/lichess_import_api.dart';
import 'package:botvinnik_mobile/brain/practice_api.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/games_list.dart';

import 'support/game_harness.dart';
import 'support/lichess_fixture.dart';
import 'support/memory_db.dart';
import 'support/node_brain.dart';

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

typedef Harness = ({
  MemoryDb db,
  ReviewController review,
  PracticeController practice,
});

/// The Review tab with a working importer behind it, at [width] logical px.
Future<Harness> pumpArchive(WidgetTester tester,
    {double width = 375, String body = kLichessNdjson, int status = 200}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final bridge = NodeBrainBridge();
  final db = MemoryDb();
  final review = ReviewController(db);
  await review.loadGames();
  final practice = PracticeController(
      db, PracticeApi(bridge), FakeGrading(), FakeArbiter());
  await practice.load();
  final game = await makeGame();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<PracticeController>.value(value: practice),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: GamesListBody(
          importApi: LichessImportApi(
            bridge,
            client: MockClient((_) async => http.Response(body, status)),
          ),
        ),
      ),
    ),
  ));
  return (db: db, review: review, practice: practice);
}

/// Open the dialog, type [name], press Import, and settle.
Future<void> importAs(WidgetTester tester, String name) async {
  await tester.tap(find.text('Import from lichess'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.widgetWithText(FilledButton, 'Import'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('an empty archive offers the import rather than a dead end',
      (tester) async {
    await pumpArchive(tester);

    expect(find.text('Import from lichess'), findsOneWidget);
    expect(find.textContaining('import your lichess history'), findsOneWidget);
  });

  testWidgets('importing archives the games and seeds practice',
      (tester) async {
    final h = await pumpArchive(tester);
    expect(h.practice.items, isEmpty);

    await importAs(tester, 'DrNykterstein');

    // archived, both of them, under the ids that make a re-import a no-op
    expect(h.db.games.keys, containsAll(['lichess-kAdOQKeh', 'lichess-xKWdG1d1']));
    // and the queue now holds this player's real mistakes — no engine ran
    expect(h.practice.items, hasLength(4));
    expect(h.practice.items.map((i) => i['playedSan']),
        containsAll(['f6', 'Kf7', 'g3', 'a4']));
    // persisted, not only in memory: the kv row is what survives a restart
    expect(jsonDecode(h.db.kv['botvinnik-practice-v1']!), hasLength(4));

    // the rows name the human opponents, not "bot"
    expect(find.text('vs Sharkfang'), findsOneWidget);
    expect(find.text('vs respects_55'), findsOneWidget);
    expect(find.textContaining('· lichess'), findsNWidgets(2));

    expect(find.textContaining('Imported 2 games'), findsOneWidget);
    expect(find.textContaining('4 practice positions'), findsOneWidget);
  });

  testWidgets('a second import of the same games changes nothing',
      (tester) async {
    final h = await pumpArchive(tester);
    await importAs(tester, 'DrNykterstein');
    final itemIds = h.practice.items.map((i) => i['id']).toList();

    await importAs(tester, 'DrNykterstein');

    expect(h.db.games, hasLength(2), reason: 'no duplicate archive rows');
    expect(h.practice.items.map((i) => i['id']), itemIds,
        reason: 'the same blunders must not be collected twice');
    // the dialog stays open and says so rather than claiming an import
    expect(find.textContaining('already here'), findsOneWidget);
  });

  testWidgets('a lichess error is shown in the dialog, not swallowed',
      (tester) async {
    final h = await pumpArchive(tester, status: 404, body: '{"error":"nope"}');

    await importAs(tester, 'nosuchplayer');

    expect(find.textContaining('No lichess user "nosuchplayer"'),
        findsOneWidget);
    expect(h.db.games, isEmpty);
  });

  testWidgets('the dialog fits a 375px phone', (tester) async {
    await pumpArchive(tester);
    await tester.tap(find.text('Import from lichess'));
    await tester.pumpAndSettle();

    // A RenderFlex overflow is an exception, and an exception in a widget test
    // is only a failure if something looks for it.
    expect(tester.takeException(), isNull);
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.width, lessThanOrEqualTo(375));
  });
}
