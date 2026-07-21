// The chess.com import as the user meets it: a button in the Review tab beside
// the lichess one, a username, a month-walk with a live line and a cancel, and
// — unlike lichess — games that land UNGRADED, so the practice queue is
// untouched and the rows say where they came from (#166).
//
// Loads the REAL bundled Roboto and runs at 375px, because a green suite says
// nothing about whether two import buttons and a dialog fit on a phone. The
// brain mapping is faked (see support/chesscom_fixture.dart for why); the
// widgets, the archive writes and the snackbar are all real.
//
//   cd flutter && flutter test test/chesscom_import_ui_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/chesscom_import_api.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/ui/games_list.dart';

import 'support/chesscom_fixture.dart';
import 'support/game_harness.dart';
import 'support/memory_db.dart';

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

typedef Harness = ({MemoryDb db, ReviewController review});

/// The Review tab with a working chess.com importer behind it, at [width]
/// logical px. One month of two games by default.
Future<Harness> pumpArchive(
  WidgetTester tester, {
  double width = 375,
  List<String> months = const ['2024/03'],
  Map<String, String>? monthBodies,
  int archivesStatus = 200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = MemoryDb();
  final review = ReviewController(db);
  await review.loadGames();
  final game = await makeGame();

  final srv = chesscomServer(
    user: 'botvinnik_fan',
    months: months,
    monthBodies: monthBodies ??
        {
          '2024/03': monthBody([
            ccGame(uuid: 'aaa', endTime: 1709900001),
            ccGame(uuid: 'bbb', endTime: 1709900000),
          ]),
        },
    archivesStatus: archivesStatus,
  );

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: GamesListBody(
          chesscomApi: ChesscomImportApi(FakeCcBridge(), client: srv.client),
        ),
      ),
    ),
  ));
  return (db: db, review: review);
}

Future<void> importAs(WidgetTester tester, String name) async {
  await tester.tap(find.text('Import from chess.com'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.widgetWithText(FilledButton, 'Import'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('both import buttons sit in the bar without overflowing 375px',
      (tester) async {
    await pumpArchive(tester);

    expect(find.text('Import from lichess'), findsOneWidget);
    expect(find.text('Import from chess.com'), findsOneWidget);
    // a RenderFlex overflow is an exception, and an exception in a widget test
    // is only a failure if something looks for it
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dialog fits a 375px phone', (tester) async {
    await pumpArchive(tester);
    await tester.tap(find.text('Import from chess.com'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.width, lessThanOrEqualTo(375));
  });

  testWidgets('importing archives the games UNGRADED and names the opponents',
      (tester) async {
    final h = await pumpArchive(tester);

    await importAs(tester, 'botvinnik_fan');

    // archived, both of them, under the ids that make a re-import a no-op
    expect(h.db.games.keys, containsAll(['chesscom-aaa', 'chesscom-bbb']));
    // and they carry NO grades — that is the background job's work, not this
    // import's (chess.com serves no evals)
    for (final g in h.db.games.values) {
      expect(g['whiteAccuracy'], isNull);
      expect(g['source'], 'chesscom');
    }

    // the rows name the human opponent, not "bot", and say where it came from
    expect(find.text('vs Opponent99'), findsNWidgets(2));
    expect(find.textContaining('· chesscom'), findsNWidgets(2));

    expect(find.textContaining('Imported 2 games from chess.com'),
        findsOneWidget);
  });

  testWidgets('a second import of the same games changes nothing',
      (tester) async {
    final h = await pumpArchive(tester);
    await importAs(tester, 'botvinnik_fan');
    expect(h.db.games, hasLength(2));

    await importAs(tester, 'botvinnik_fan');

    expect(h.db.games, hasLength(2), reason: 'no duplicate archive rows');
    // the dialog stays open and says so rather than claiming an import
    expect(find.textContaining('already here'), findsOneWidget);
  });

  testWidgets('a chess.com error is shown in the dialog, not swallowed',
      (tester) async {
    final h = await pumpArchive(tester, archivesStatus: 404);

    await importAs(tester, 'nosuchplayer');

    expect(find.textContaining('No chess.com user'), findsOneWidget);
    expect(h.db.games, isEmpty);
  });
}
