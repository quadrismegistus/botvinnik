// The W-L-D record line the roster picker shows per persona (#142), rendered.
//
// The aggregation is proved in bot_record_test.dart; this is about what a
// player sees. Two dense extra lines in a ListTile subtitle at 375px is a
// RenderFlex overflow waiting to happen, and neither the analyzer nor a green
// unit suite says anything about one — so this loads the REAL bundled Roboto
// (Ahem's uniform squares are not evidence about what fits) and asserts the
// line is on screen and nothing overflowed.
//
//   cd flutter && flutter test test/roster_picker_record_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/bot_record_store.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/roster_picker.dart';

import 'support/game_harness.dart';

Persona _p(String family, int elo) => Persona({
      'id': '$family-$elo',
      'name': '${family[0].toUpperCase()}${family.substring(1)} $elo',
      'elo': elo,
      'family': family,
      'blurb': 'A bot that plays chess and has a reasonably long blurb here.',
    });

/// Only the two unconditional families, injected as playable — CI is Linux,
/// where the other four vanish and take any assertion resting on them with it.
final _roster = <Persona>[
  _p('squarefish', 1000),
  _p('squarefish', 1200),
  _p('stockfish', 2000),
];
const _playable = {'squarefish', 'stockfish'};

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

Future<GameController> _game() async => GameController(
      FakeArbiter(),
      FakeBot({for (final p in _roster) p.id: p}),
      FakeGrading(),
      await loadSettings(),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Map<String, BotRecord> records,
  int? playerElo,
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF262421),
      body: RosterSheet(
        game: await _game(),
        playable: _playable,
        records: records,
        playerElo: playerElo,
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  testWidgets('a persona with a record shows it, one without shows no line',
      (tester) async {
    await _pump(tester, records: {
      'squarefish-1200': const BotRecord(won: 3, lost: 1, drawn: 0),
    });

    expect(find.text('3W 1L 0D'), findsOneWidget);
    // The other two personas have no record and (playerElo null) no marker, so
    // a W-L-D line appears exactly once. Nothing else in the sheet — heading,
    // title, blurb — carries a 'W '.
    expect(find.textContaining('W '), findsOneWidget,
        reason: 'only the persona with a record shows a W-L-D line');
    expect(tester.takeException(), isNull, reason: 'overflowed at 375px');
  });

  testWidgets('near the player, the marker joins the record on one line',
      (tester) async {
    // 1180 is 20 off Squarefish 1200 (marked) and 180 off Squarefish 1000
    // (not) — so the marker is selective, not on every row.
    await _pump(
      tester,
      records: {'squarefish-1200': const BotRecord(won: 3, lost: 1)},
      playerElo: 1180,
    );

    expect(find.text('3W 1L 0D  ·  near your level'), findsOneWidget);
    expect(find.textContaining('near your level'), findsOneWidget,
        reason: 'only the persona within 100 elo is marked');
    expect(tester.takeException(), isNull, reason: 'overflowed at 375px');
  });

  testWidgets('a near persona with no record shows the marker alone',
      (tester) async {
    await _pump(tester, records: const {}, playerElo: 1010);

    // 1010 is 10 off Squarefish 1000 and 190 off Squarefish 1200.
    expect(find.text('near your level'), findsOneWidget);
    expect(find.textContaining('W '), findsNothing,
        reason: 'no games played means no W-L-D line');
    expect(tester.takeException(), isNull);
  });

  // A record present is the row under the most pressure — an extra line above
  // the two-line blurb. Both narrow widths, so the fix is not tuned to one.
  for (final width in [375.0, 320.0]) {
    testWidgets('no overflow at ${width.toInt()}px with a record and a marker',
        (tester) async {
      await _pump(
        tester,
        records: {'squarefish-1200': const BotRecord(won: 12, lost: 10, drawn: 3)},
        playerElo: 1200,
        width: width,
      );
      expect(find.text('12W 10L 3D  ·  near your level'), findsOneWidget,
          reason: 'the line under test must be on screen');
      expect(tester.takeException(), isNull,
          reason: 'overflowed at ${width.toInt()}px');
    });
  }
}
