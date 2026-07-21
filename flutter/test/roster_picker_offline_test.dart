// What the roster picker says about a Maia band's weights (#130).
//
// Maia is the only family that needs a download before it can play, and an
// undownloaded band is the commonest way a persona silently becomes Stockfish
// instead (#117). So the sheet has to distinguish a band that is ready from
// one that is not, BEFORE the game rather than during it — and on the web,
// where the worker's IndexedDB is invisible from Dart, it has to say the
// weaker thing rather than guess.
//
// Rendered at 375px with the real bundled Roboto: these are two extra lines of
// dense text in a ListTile subtitle, and a RenderFlex overflow is a runtime
// error neither the analyzer nor a green suite would mention. Ahem's uniform
// squares would not be evidence about it either.
//
//   cd flutter && flutter test test/roster_picker_offline_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/maia_weights_io.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/roster_picker.dart';

import 'support/game_harness.dart';

const _kReady = 'downloaded — plays offline';
const _kMissing = 'needs a short download — then plays offline';
const _kUnknown = 'a short download the first time — then plays offline';

/// The two personas that share band 1100 and one that does not, so a mark that
/// keyed off the persona rather than the BAND would be visible: Maia I and
/// Maia I (sampled) are the same 3.5MB file.
final _roster = <Persona>[
  _maia('maia-1100', 'Maia I', 1570, 1100),
  _maia('maia-s-1100', 'Maia I (sampled)', 1310, 1100),
  _maia('maia-1900', 'Maia IX', 1700, 1900),
  const Persona({
    'id': 'stockfish-2000',
    'name': 'Stockfish 2000',
    'elo': 2000,
    'family': 'stockfish',
    'blurb': 'Stockfish with the strength limiter on.',
  }),
];

Persona _maia(String id, String name, int elo, int band) => Persona({
      'id': id,
      'name': name,
      'elo': elo,
      'family': 'maia',
      'blurb': 'A neural net trained to move like real players.',
      'maiaBand': band,
    });

/// The real families, injected: CI is Linux, where `MaiaEngine.supported` is
/// false and every Maia row — and so every assertion here — would vanish.
const _playable = {'stockfish', 'maia'};

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

Future<GameController> _sheetGame() async => GameController(
      FakeArbiter(),
      FakeBot({for (final p in _roster) p.id: p}),
      FakeGrading(),
      await loadSettings(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadRoboto);

  setUp(() {
    MaiaWeights.debugReset();
    // No network from a widget test, and nowhere on disk to prefetch into —
    // so the prefetch the sheet starts in initState cannot do anything but
    // give up, whatever this machine's Application Support looks like.
    MaiaWeights.debugOpen = (uri) async =>
        throw StateError('a widget test must not reach the network: $uri');
  });

  tearDown(MaiaWeights.debugReset);

  Future<void> pumpSheet(WidgetTester tester, {double width = 375}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final game = await _sheetGame();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF262421),
        body: RosterSheet(game: game, playable: _playable),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a cached band reads as ready and an uncached one as a download',
      (tester) async {
    MaiaWeights.debugSetCached({1100});
    await pumpSheet(tester);

    // Both personas on band 1100 — the file is per band, not per persona.
    expect(find.text(_kReady), findsNWidgets(2));
    expect(find.text(_kMissing), findsOneWidget);
    expect(find.text(_kUnknown), findsNothing);

    // The mark belongs to the row it describes: Maia IX is the uncached one.
    final missing = tester.getTopLeft(find.text(_kMissing)).dy;
    expect(missing, greaterThan(tester.getTopLeft(find.text('Maia IX  ·  1700')).dy));
    expect(missing,
        lessThan(tester.getTopLeft(find.text('Stockfish 2000  ·  2000')).dy));

    // Nothing but Maia claims anything about downloads.
    expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.offline_pin_outlined), findsNWidgets(2));

    expect(tester.takeException(), isNull,
        reason: 'the sheet overflowed at 375px');
  });

  testWidgets('a band that lands while the sheet is open stops asking',
      (tester) async {
    MaiaWeights.debugSetCached(<int>{});
    await pumpSheet(tester);
    expect(find.text(_kMissing), findsNWidgets(3));

    // What the prefetch finishing looks like from here.
    MaiaWeights.debugSetCached({1100, 1500, 1900});
    await tester.pump();
    expect(find.text(_kMissing), findsNothing);
    expect(find.text(_kReady), findsNWidgets(3));
  });

  testWidgets('an unknown cache says the weaker thing, not the wrong one',
      (tester) async {
    // The web: the weights live in the worker's IndexedDB and Dart cannot see
    // them, so "not downloaded" would be a claim rather than a fact.
    MaiaWeights.debugSetCached(null);
    await pumpSheet(tester);

    expect(find.text(_kUnknown), findsNWidgets(3));
    expect(find.text(_kReady), findsNothing);
    expect(find.text(_kMissing), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Every mark at both narrow widths. The unknown one is the LONGEST line and
  // 320px the narrowest phone the app targets — that pair is the only
  // combination that overflows without the note's Expanded, so a loop that
  // left it out would be a layout test proving nothing.
  for (final (label, width) in [('375', 375.0), ('320', 320.0)]) {
    for (final (state, cached, line) in [
      ('cached', {1100}, _kReady),
      ('uncached', <int>{}, _kMissing),
      ('unknown', null, _kUnknown),
    ]) {
      testWidgets('no overflow at ${label}px: $state', (tester) async {
        MaiaWeights.debugSetCached(cached);
        await pumpSheet(tester, width: width);
        expect(find.text(line), findsWidgets,
            reason: 'the line under test must be on screen');
        expect(tester.takeException(), isNull,
            reason: '$state overflowed at ${label}px');
      });
    }
  }
}
