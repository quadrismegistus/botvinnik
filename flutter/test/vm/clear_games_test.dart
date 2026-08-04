// The bulk local clear (#292) — the missing local half of #258's server
// wipe. The button must be sync-aware for the same reason #258's had to
// disable sync afterwards: clearing locally while sync is on means the next
// pull merges every server-held game straight back, a delete that undoes
// itself. Practice puzzles stay — they are the distilled value of the games.
//
//   cd flutter && flutter test test/vm/clear_games_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/brain/practice_api.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';
import 'package:botvinnik_mobile/stores/review_controller.dart';
import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:botvinnik_mobile/sync/sync_controller.dart';
import 'package:botvinnik_mobile/sync/sync_crypto.dart';
import 'package:botvinnik_mobile/sync/sync_key_store.dart';
import 'package:botvinnik_mobile/ui/settings_tab.dart';

import '../support/fake_sync_key_store.dart';
import '../support/game_harness.dart';
import '../support/memory_db.dart';
import '../support/practice_harness.dart';

Map<String, dynamic> _game(String id) => {
      'id': id,
      'endedAt': '2026-08-0${id.length}T10:00:00.000',
      'result': '1-0',
      'pgn': '1. e4 e5 1-0',
      'moveCount': 2,
      'botColor': 'b',
      'moves': const [],
    };

Future<
    ({
      PracticeController practice,
      ReviewController review,
      MemoryDb db,
    })> _pump(WidgetTester tester, {bool syncOn = false}) async {
  tester.view.physicalSize = const Size(375, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final db = MemoryDb();
  await db.saveGame(_game('g1'));
  await db.saveGame(_game('g22'));
  final practice = PracticeController(
      db, PracticeApi(FakeBridge()), FakeGrading(), FakeArbiter());
  practice.items = [practiceItem('fen-keep')];
  practice.loaded = true;
  final review = ReviewController(db);
  await review.loadGames();
  final settings = await loadSettings();
  practice.settings = settings;

  final keyStore = FakeSyncKeyStore();
  if (syncOn) {
    keyStore.session = SyncSession(
        phrase: 'test phrase',
        keys: SyncKeys(
            blobId: 'a' * 43, encKey: List<int>.filled(32, 7)));
  }
  final sync = SyncController(db: db, keyStore: keyStore);
  await sync.loadCached();

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsStore>.value(value: settings),
      ChangeNotifierProvider<PracticeController>.value(value: practice),
      ChangeNotifierProvider<ReviewController>.value(value: review),
      ChangeNotifierProvider<SyncController>.value(value: sync),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SettingsTab(
            saveFile: (
                    {required String filename,
                    required String text,
                    required String mimeType,
                    Rect? origin}) async =>
                false,
            readFile: (
                    {required String extension,
                    required String mimeType,
                    required String uti}) async =>
                null),
      ),
    ),
  ));
  await tester.pump();
  return (practice: practice, review: review, db: db);
}

Future<void> _scrollTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 120,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('confirming deletes every game — and only the games',
      (tester) async {
    final s = await _pump(tester);
    expect(s.review.games, hasLength(2), reason: 'precondition');

    await _scrollTo(tester, 'Clear local games');
    await tester.tap(find.text('Clear local games'));
    await tester.pumpAndSettle();
    // the dialog states the count — a destructive tap must know its size
    expect(find.textContaining('2 games'), findsWidgets);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(s.review.games, isEmpty, reason: 'the controller list');
    expect(await s.db.listGames(), isEmpty, reason: 'the store itself');
    expect(s.practice.items, hasLength(1),
        reason: 'practice puzzles are not games and must survive');
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    final s = await _pump(tester);
    await _scrollTo(tester, 'Clear local games');
    await tester.tap(find.text('Clear local games'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.review.games, hasLength(2));
  });

  testWidgets('with sync on, the row is disabled and says why',
      (tester) async {
    // The #258 lesson in the other direction: a local wipe under live sync is
    // undone by the next pull, so the button must refuse rather than pretend.
    final s = await _pump(tester, syncOn: true);
    await _scrollTo(tester, 'Clear local games');
    expect(find.textContaining('sync'), findsWidgets);
    await tester.tap(find.text('Clear local games'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing,
        reason: 'no dialog — the row is inert while sync is on');
    expect(s.review.games, hasLength(2));
  });
}
