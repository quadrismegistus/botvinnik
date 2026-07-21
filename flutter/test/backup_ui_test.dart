// The two doors out of the app (#138): a PGN button on every archive row, and
// backup/restore in Settings.
//
// These drive the REAL widgets over a real BackupService and a real
// MemoryDb — only the last step, the platform's own save/open dialog, is a
// recorder. That is deliberate: the interesting failures are "the button
// exported the wrong string", "the filename named the wrong player" and "the
// restore wrote to the database and nothing on screen noticed", and all three
// survive a test that only checks a dialog was asked for.
//
// The layout half loads the real bundled Roboto and lays out at 375 and 320,
// because the export button is new WIDTH in a row that was already tight and
// the analyzer cannot see a RenderFlex overflow.
//
// Each test was made to fail first — the mutations are listed above the group
// they belong to.
//
//   cd flutter && flutter test test/backup_ui_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/practice_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/backup.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/stores/pgn_import.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/ui/games_list.dart';
import 'package:botvinnik_mobile/ui/settings_tab.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';
import 'support/practice_harness.dart';

typedef Save = ({String filename, String text, String mimeType});

/// Stands in for the platform's save panel / share sheet / download.
class SaveRecorder {
  final List<Save> saves = [];

  /// What the platform reports back. False is a user who backed out of the
  /// dialog, which the UI must not report as a save.
  bool accepts = true;

  Future<bool> call({
    required String filename,
    required String text,
    required String mimeType,
    Rect? origin,
  }) async {
    saves.add((filename: filename, text: text, mimeType: mimeType));
    return accepts;
  }

  Save get only => saves.single;
}

/// Stands in for the file picker. Null is a dismissed dialog.
class OpenStub {
  String? text;
  int calls = 0;
  OpenStub([this.text]);

  Future<String?> call({
    required String extension,
    required String mimeType,
    required String uti,
  }) async {
    calls++;
    return text;
  }
}

Map<String, dynamic> storedGame({
  String id = 'g-1',
  String botColor = 'b',
  String result = '1-0',
  String? pgn = '[White "You"]\n[Black "Squarefish"]\n\n1. e4 e5 1-0',
  String endedAt = '2026-07-21T10:30:00.000',
}) =>
    {
      'id': id,
      'endedAt': endedAt,
      'result': result,
      'botElo': 1740,
      'botPersona': 'squarefish-1500',
      'botColor': botColor,
      'botHintsUsed': false,
      'moveCount': 42,
      'whiteAccuracy': 81.4,
      'blackAccuracy': 74.2,
      'labelCounts': const {'w': {}, 'b': {}},
      'moves': const [],
      'pgn': ?pgn,
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

/// The roster the archive resolves `botPersona` against. Present so the
/// filename test exercises the persona's NAME rather than its stored id — the
/// same distinction the row itself makes, and the reason a game against
/// `squarefish-1500` is not filed under that string.
final _roster = {
  'squarefish-1500': const Persona({
    'id': 'squarefish-1500',
    'name': 'Squarefish 1500',
    'elo': 1500,
    'family': 'squarefish',
    'blurb': '',
  }),
};

Future<ReviewController> pumpArchive(
  WidgetTester tester,
  List<Map<String, dynamic>> games, {
  required SaveRecorder saver,
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final review = ReviewController(MemoryDb(games));
  await review.loadGames();
  final game = GameController(
      FakeArbiter(), FakeBot(_roster), FakeGrading(), await loadSettings());

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<GameController>.value(value: game),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: MaterialApp(
      home: Scaffold(body: GamesListBody(saveFile: saver.call)),
    ),
  ));
  return review;
}

/// Settings over one shared store, so a restore written by the tab is a
/// restore both controllers can be asked about afterwards.
Future<({PracticeController practice, ReviewController review, MemoryDb db})>
    pumpSettings(
  WidgetTester tester, {
  required SaveRecorder saver,
  required OpenStub opener,
  MemoryDb? db,
  double width = 375,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = db ?? MemoryDb();
  final practice = PracticeController(
      store, PracticeApi(FakeBridge()), FakeGrading(), FakeArbiter());
  await practice.load();
  final review = ReviewController(store);
  await review.loadGames();
  final settings = await loadSettings();
  practice.settings = settings;

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<PracticeController>.value(value: practice),
      ChangeNotifierProvider<ReviewController>.value(value: review),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SettingsTab(saveFile: saver.call, readFile: opener.call),
      ),
    ),
  ));
  await tester.pump();
  return (practice: practice, review: review, db: store);
}

/// The section lives below three others in a scrolling tab.
Future<void> scrollTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);
  setUp(() {
    // SettingsTab ends in the About section, which asks for the package info.
    PackageInfo.setMockInitialValues(
      appName: 'botvinnik',
      packageName: 'app.botvinnik',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // Mutations proved on this group, each reintroduced singly: drawing the
  // button unconditionally (reddens the record-without-a-PGN test alone);
  // exporting `''` instead of the record's pgn; swapping the white/black
  // arguments to pgnFilename; passing the stored `botPersona` id where the
  // persona's name belongs; and announcing the save whatever the platform
  // answered. Dropping the button altogether reddens five of these, which is
  // the shape you would expect and the reason it is not the interesting one.
  group('the PGN button on an archive row', () {
    testWidgets('is offered for a game that has a PGN', (tester) async {
      await pumpArchive(tester, [storedGame()], saver: SaveRecorder());

      expect(find.byTooltip('Export PGN'), findsOneWidget);
    });

    testWidgets('is not offered for a record saved before PGNs were stored',
        (tester) async {
      // Not a hypothetical: `pgn` is optional on the record and the archive
      // predates it. An export button that produced an empty file would look
      // like the feature working.
      await pumpArchive(tester, [storedGame(pgn: null)], saver: SaveRecorder());

      expect(find.byTooltip('Export PGN'), findsNothing);
    });

    testWidgets('hands over the stored PGN, unaltered', (tester) async {
      final saver = SaveRecorder();
      await pumpArchive(tester, [storedGame()], saver: saver);

      await tester.tap(find.byTooltip('Export PGN'));
      await tester.pump();

      expect(saver.only.text, storedGame()['pgn'],
          reason: 'the string game_controller already wrote, not a rebuild');
      expect(saver.only.mimeType, 'application/x-chess-pgn');
    });

    testWidgets('names the file for the side each player took', (tester) async {
      final saver = SaveRecorder();
      // botColor 'b' — the human had White.
      await pumpArchive(tester, [storedGame()], saver: saver);
      await tester.tap(find.byTooltip('Export PGN'));
      await tester.pump();
      // "Squarefish1500", from the persona's current NAME — not the stored
      // "squarefish-1500", which is the id the record carries and which the
      // row itself already refuses to show for the same reason.
      expect(saver.only.filename,
          'botvinnik-You-vs-Squarefish1500-2026-07-21.pgn');

      // The same game from the other side must not produce the same name.
      final other = SaveRecorder();
      await pumpArchive(tester, [storedGame(botColor: 'w', result: '0-1')],
          saver: other);
      await tester.tap(find.byTooltip('Export PGN'));
      await tester.pump();
      expect(other.only.filename,
          'botvinnik-Squarefish1500-vs-You-2026-07-21.pgn',
          reason: 'the human was Black here; a filename that always puts You '
              'first is wrong for half the archive');
    });

    testWidgets('says so when the file was written, and stays quiet when the '
        'user backed out', (tester) async {
      final saver = SaveRecorder();
      await pumpArchive(tester, [storedGame()], saver: saver);

      await tester.tap(find.byTooltip('Export PGN'));
      await tester.pump();
      expect(find.textContaining('Saved botvinnik-You-vs'), findsOneWidget);

      saver.accepts = false;
      await tester.pumpWidget(const SizedBox()); // drop the snackbar
      await pumpArchive(tester, [storedGame()], saver: saver);
      await tester.tap(find.byTooltip('Export PGN'));
      await tester.pump();
      expect(find.textContaining('Saved'), findsNothing,
          reason: 'a cancelled save panel is the user telling the app what '
              'they want; announcing it back at them is noise');
    });
  });

  // Mutations proved on this group, each singly, each reddening only the test
  // named: dropping `await practice.load()`, and dropping
  // `await review.loadGames()`, after the import (each takes down one half of
  // the restore test's assertions); catching BackupFormatException as a
  // generic error; losing the "nothing new" branch; and treating a cancelled
  // picker as an import of nothing rather than as no import at all.
  group('backup and restore in Settings', () {
    testWidgets('exports both tables under a dated name', (tester) async {
      final saver = SaveRecorder();
      final db = MemoryDb([storedGame()]);
      db.kv[kPracticeKvKey] = jsonEncode([practiceItem('fen-1')]);

      await pumpSettings(tester, saver: saver, opener: OpenStub(), db: db);
      await scrollTo(tester, 'Back up everything');
      await tester.tap(find.text('Back up everything'));
      await tester.pump();

      final doc = jsonDecode(saver.only.text) as Map<String, dynamic>;
      expect(doc['app'], 'botvinnik');
      expect((doc['games'] as List).single['id'], 'g-1');
      expect((doc['practice'] as List).single['id'], 'fen-1');
      expect(saver.only.mimeType, 'application/json');
      expect(saver.only.filename, startsWith('botvinnik-backup-'));
      expect(saver.only.filename, endsWith('.json'));
    });

    testWidgets('a restore is visible to the tabs that use it', (tester) async {
      final file = jsonEncode({
        'app': 'botvinnik',
        'version': 1,
        'exportedAt': '2026-07-20T00:00:00.000Z',
        'practice': [practiceItem('fen-restored')],
        'games': [storedGame(id: 'g-restored')],
      });
      final s = await pumpSettings(tester,
          saver: SaveRecorder(), opener: OpenStub(file));

      expect(s.practice.items, isEmpty);
      expect(s.review.games, isEmpty);

      await scrollTo(tester, 'Restore from a backup');
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Restored 1 game and 1 puzzle'),
          findsOneWidget);
      // The half that is easy to leave out: the import writes UNDERNEATH the
      // controllers, so without the reloads the Practice tab keeps serving the
      // old queue and the archive keeps showing the old list until restart —
      // indistinguishable from an import that did nothing.
      expect(s.practice.items.single['id'], 'fen-restored',
          reason: 'the practice controller must re-read after the import');
      expect(s.review.games.single['id'], 'g-restored',
          reason: 'the archive controller must re-read after the import');
    });

    testWidgets('a file that is not a backup is named as such', (tester) async {
      final s = await pumpSettings(tester,
          saver: SaveRecorder(), opener: OpenStub('{"app":"chess.com"}'));

      await scrollTo(tester, 'Restore from a backup');
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(find.text('Not a botvinnik backup file.'), findsOneWidget,
          reason: 'the sentence from the exception, not "Could not restore: '
              'Instance of BackupFormatException"');
      expect(s.db.writes, isEmpty);
    });

    testWidgets('dismissing the picker does nothing at all', (tester) async {
      final opener = OpenStub(); // null text = cancelled
      await pumpSettings(tester, saver: SaveRecorder(), opener: opener);

      await scrollTo(tester, 'Restore from a backup');
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'cancelling is not an error and not a result');
    });

    testWidgets('says when the file held nothing new', (tester) async {
      final db = MemoryDb([storedGame()]);
      final file = jsonEncode({
        'app': 'botvinnik',
        'practice': [],
        'games': [storedGame()],
      });
      await pumpSettings(tester,
          saver: SaveRecorder(), opener: OpenStub(file), db: db);

      await scrollTo(tester, 'Restore from a backup');
      await tester.tap(find.text('Restore from a backup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already here'), findsOneWidget,
          reason: '"Restored 0 games and 0 puzzles" reads as a failure');
    });
  });

  // A green suite and a clean analyzer say nothing about layout, and the
  // export button is new width in a row that already carried a verdict, a
  // crown, an opponent name and an accuracy.
  //
  // Two things were MEASURED here rather than assumed. Giving the button back
  // its stock 48x48 IconButton constraints does NOT overflow the row at either
  // width — a ListTile takes its trailing out of the title's width and the
  // title's name is Expanded, so the row absorbs it; the 40px is a spacing
  // choice, not a fix, and the comment in games_list.dart says so. What the
  // row cannot absorb is a title that refuses to shrink, which is why the
  // fixture carries an imported game with two long player names: replacing
  // that title's Expanded with a Spacer overflows at 320 and reddens the 320
  // case alone (375 has the room, which is exactly why 320 is here).
  for (final width in [375.0, 320.0]) {
    testWidgets('the archive row survives the export button at $width',
        (tester) async {
      await pumpArchive(
        tester,
        [
          // the widest row the archive can draw: a helped win, so the crown
          // and its itemised second line are both present
          {
            ...storedGame(id: 'a'),
            'botUndos': 12,
            'botHintsUsed': true,
            'botFallback': true,
          },
          // an import: no crown, but the longest title the list can hold, and
          // it carries a PGN so it gets a button too
          {
            ...storedGame(id: 'b', endedAt: '2026-07-20T10:30:00.000'),
            kImportedKey: true,
            'white': 'Kasparov, Garry',
            'black': 'Topalov, Veselin',
          },
        ],
        saver: SaveRecorder(),
        width: width,
      );

      expect(find.byTooltip('Export PGN'), findsNWidgets(2),
          reason: 'both buttons must be on screen, or this proves nothing');
      expect(tester.takeException(), isNull,
          reason: 'the archive row overflowed at $width');

      // The button must not be pushed off the right edge by the title row.
      for (final b in [0, 1]) {
        final button = tester.getRect(find.byTooltip('Export PGN').at(b));
        expect(button.right, lessThanOrEqualTo(width));
        expect(button.width, greaterThanOrEqualTo(40),
            reason: 'a tap target squeezed to nothing is not a button');
      }
    });

    // The restore row's subtitle is two sentences and wraps to three lines at
    // 320. A ListTile POSITIONS its subtitle rather than flexing around it, so
    // a row that stopped growing to fit would paint that text over the row
    // below with no overflow error to catch — geometry is the only witness.
    // Verified sensitive by wrapping the tile in a SizedBox(height: 40),
    // which reddens both widths and nothing else.
    testWidgets('the backup rows survive at $width', (tester) async {
      await pumpSettings(tester,
          saver: SaveRecorder(), opener: OpenStub(), width: width);
      await scrollTo(tester, 'Back up everything');

      expect(find.text('Back up everything'), findsOneWidget);
      expect(find.text('Restore from a backup'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the Your data section overflowed at $width');

      final blurb = find.textContaining('Nothing here is deleted');
      final tile = find.ancestor(of: blurb, matching: find.byType(ListTile));
      expect(tester.getRect(blurb).bottom,
          lessThanOrEqualTo(tester.getRect(tile).bottom),
          reason: 'the restore blurb spilled out of its own row at $width');
    });
  }
}
