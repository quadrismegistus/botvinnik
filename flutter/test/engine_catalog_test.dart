// The download catalog: the parts that hold without a real network download
// (the install itself — fetch, checksum, chmod, de-quarantine — is verified on
// a desktop). What matters here is that the seed is well-formed (real URLs and
// 64-hex checksums), that build selection is by platform, and that the Engines
// screen renders an entry with its licence and a way in.
//
//   cd flutter && flutter test test/engine_catalog_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:botvinnik_mobile/stores/custom_engine.dart';
import 'package:botvinnik_mobile/stores/engine_catalog.dart';
import 'package:botvinnik_mobile/ui/engines_screen.dart';

import 'support/memory_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the seed is well-formed: real assets and 64-hex checksums', () {
    expect(kEngineCatalog, isNotEmpty);
    final ids = kEngineCatalog.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'ids are unique');

    final hex = RegExp(r'^[0-9a-f]{64}$');
    for (final e in kEngineCatalog) {
      expect(e.license, isNotEmpty, reason: '${e.id} must state a licence');
      expect(e.sourceUrl, startsWith('https://'),
          reason: '${e.id} needs a source link (AGPL §13 for phase 2)');
      expect(e.builds, isNotEmpty);
      for (final entry in e.builds.entries) {
        expect(entry.value.url, startsWith('https://'));
        expect(hex.hasMatch(entry.value.sha256), isTrue,
            reason: '${e.id}/${entry.key} sha256 must be 64 lowercase hex');
        expect(entry.value.sizeBytes, greaterThan(0));
      }
    }
  });

  test('Viridithas is seeded, AGPL, with a macOS build', () {
    final viri = kEngineCatalog.firstWhere((e) => e.id == 'viridithas');
    expect(viri.license, 'AGPL-3.0');
    expect(viri.buildFor('macos-arm64'), isNotNull);
    // v20 ships no Intel-mac binary — the catalog must not pretend it does.
    expect(viri.buildFor('macos-x64'), isNull);
    // an unknown platform selects nothing rather than throwing
    expect(viri.buildFor('haiku-sparc'), isNull);
    expect(viri.buildFor(null), isNull);
  });

  testWidgets('the Engines screen shows an entry, its licence, and a way in',
      (tester) async {
    // Tall enough that the whole catalog + the add-by-path row lay out; a lazy
    // ListView would not build the bottom row on the default 600px viewport now
    // that several engines precede it.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = CustomEngineStore(MemoryDb([]));
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<CustomEngineStore>.value(
          value: store,
          child: const EnginesScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Engines'), findsOneWidget); // the app bar
    expect(find.textContaining('Viridithas'), findsWidgets);
    // Several entries are AGPL now (Viridithas, Reckless), each with a source
    // link — so these are no longer one-of-a-kind.
    expect(find.textContaining('AGPL-3.0'), findsWidgets);
    expect(find.text('source'), findsWidgets);
    // the escape hatch for anything not in the catalog
    expect(find.text('Add an engine by path…'), findsOneWidget);
  });

  test('capsElo is verified per engine: only Velvet dials, over a real range',
      () {
    // Ground truth from each engine's source (a wrong value ships a lying UI):
    // these implement UCI_LimitStrength/UCI_Elo.
    const cappers = {'velvet', 'patricia', 'rodent', 'arasan', 'brainlearn'};
    for (final e in kEngineCatalog) {
      if (cappers.contains(e.id)) {
        expect(e.capsElo, isTrue, reason: '${e.id} should cap');
        expect(e.eloMin, lessThan(e.eloMax),
            reason: '${e.id} needs a real spin range');
        expect(e.eloMin, greaterThan(0));
      } else {
        expect(e.capsElo, isFalse,
            reason: '${e.id} has no UCI_Elo — must not offer a cap');
      }
    }
    final velvet = kEngineCatalog.firstWhere((e) => e.id == 'velvet');
    expect((velvet.eloMin, velvet.eloMax), (1225, 3000));
    final patricia = kEngineCatalog.firstWhere((e) => e.id == 'patricia');
    expect((patricia.eloMin, patricia.eloMax), (500, 3001));
    final rodent = kEngineCatalog.firstWhere((e) => e.id == 'rodent');
    expect((rodent.eloMin, rodent.eloMax), (800, 2800));
    final arasan = kEngineCatalog.firstWhere((e) => e.id == 'arasan');
    expect((arasan.eloMin, arasan.eloMax), (1000, 3450));
    final bl = kEngineCatalog.firstWhere((e) => e.id == 'brainlearn');
    expect((bl.eloMin, bl.eloMax), (1320, 3190));
  });

  test('BrainLearn styles are option toggles; Arasan hosts a downloaded net',
      () {
    final bl = kEngineCatalog.firstWhere((e) => e.id == 'brainlearn');
    // Two option-styles (Classic/MCTS) that send a UCI option, not a file, so
    // no bundled data and a flat (non-own-dir) install.
    expect(bl.personalities.map((p) => p.key).toList(), ['classic', 'mcts']);
    expect(bl.personalities.every((p) => p.file == null), isTrue);
    expect(bl.personalities.map((p) => p.setoption).toList(),
        ['MCTS value false', 'MCTS value true']);
    expect(bl.ownDir, isFalse, reason: 'a toggle needs no dir beside it');

    final arasan = kEngineCatalog.firstWhere((e) => e.id == 'arasan');
    // A downloaded net, keyed by the exact name Arasan loads beside itself.
    expect(arasan.dataFiles.keys, contains('arasanv8-20260622.nnue'));
    expect(arasan.personalities, isEmpty);
    expect(arasan.ownDir, isTrue, reason: 'the net must sit beside the binary');
    // Rodent's file styles also own a dir; a plain engine does not.
    expect(kEngineCatalog.firstWhere((e) => e.id == 'rodent').ownDir, isTrue);
    expect(kEngineCatalog.firstWhere((e) => e.id == 'velvet').ownDir, isFalse);
  });

  test('Rodent declares many styles; every style file is a bundled asset', () {
    final rodent = kEngineCatalog.firstWhere((e) => e.id == 'rodent');
    expect(rodent.personalities.length, greaterThanOrEqualTo(30));
    // ids must be unique, and every referenced style file must actually ship —
    // a typo would install an engine that loads nothing for that style.
    final keys = rodent.personalities.map((p) => p.key).toList();
    expect(keys.toSet().length, keys.length, reason: 'style keys are unique');
    for (final p in rodent.personalities) {
      expect(File('assets/rodent/personalities/${p.file}').existsSync(), isTrue,
          reason: '${p.file} is referenced but not bundled');
    }
    // the marker file the engine needs to find its home dir
    expect(File('assets/rodent/personalities/basic.ini').existsSync(), isTrue);
    // an ordinary engine declares no styles
    expect(kEngineCatalog.firstWhere((e) => e.id == 'velvet').personalities,
        isEmpty);
  });

  test('cap sliders round to hundreds; clampElo restores the real range', () {
    final bl = kEngineCatalog.firstWhere((e) => e.id == 'brainlearn'); // 1320-3190
    expect((bl.capSliderMin, bl.capSliderMax), (1300, 3200));
    expect(bl.clampElo(1300), 1320, reason: 'a round label below the real floor');
    expect(bl.clampElo(1500), 1500, reason: 'in range, unchanged');
    expect(bl.clampElo(3200), 3190, reason: 'rounded ceiling clamped to real max');
    final velvet = kEngineCatalog.firstWhere((e) => e.id == 'velvet'); // 1225-3000
    expect((velvet.capSliderMin, velvet.capSliderMax), (1200, 3000));
    expect(velvet.clampElo(1200), 1225);
  });

  test('catalogEntryById matches a catalog id, and only that', () {
    expect(catalogEntryById('velvet')?.id, 'velvet');
    // a hand-added engine's id is a timestamp, never a catalog slug
    expect(catalogEntryById('1a2b3c'), isNull);
    expect(catalogEntryById(null), isNull);
  });
}
