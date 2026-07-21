// The roster picker groups personas by family (#136), and the whole point of
// the grouping is a number computed at RUNTIME: a family's place in the sheet
// is its members' average elo, averaged over the personas that survived
// `_playableFamilies`.
//
// That distinction is invisible on the web, where every family but Dala plays,
// which is why these tests inject the platform filter rather than trusting the
// one the host happens to have. Computing the averages before the filter puts
// a Dala heading (avg 1107) between Horizon and Squarefish on every platform,
// with nothing under it — the exact bug the issue asks to be designed out.
//
//   cd flutter && flutter test test/roster_picker_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/game_controller.dart';
import 'package:botvinnik_mobile/ui/roster_picker.dart';

import 'support/game_harness.dart';

Persona _p(String family, int elo, {String? name}) => Persona({
      'id': '$family-$elo',
      'name': name ?? '${family[0].toUpperCase()}${family.substring(1)} $elo',
      'elo': elo,
      'family': family,
      'blurb': 'A bot.',
    });

/// The real roster's families and elos (`brain/bots.ts`, 2026-07-21), so the
/// expected order below is the one a player actually gets rather than one
/// invented to suit the test.
///
/// Deliberately NOT in elo order: `PERSONAS` is sorted by elo before it
/// crosses the bridge, so a fixture in that order could not tell a working
/// within-group sort from no sort at all.
final _roster = <Persona>[
  ..._family('stockfish', [2500, 1800, 2200, 1900, 2400, 2000, 2300, 2100]),
  ..._family('maia', [1700, 1310, 1640, 1380, 1570, 1440]),
  ..._family('horizon', [860, 550]),
  ..._family('garbo', [2020]),
  ..._family('retro', [1300, 1200, 1230]),
  ..._family('dala', [1315, 911, 1095]),
  ..._family('squarefish',
      [1700, 600, 1600, 700, 1500, 800, 1400, 900, 1300, 1000, 1200, 1100]),
];

List<Persona> _family(String family, List<int> elos) =>
    [for (final e in elos) _p(family, e)];

/// Three sets `_playableFamilies` can actually evaluate to. Named for what
/// makes them differ rather than for a platform: Garbo, Maia and retro each
/// answer for themselves, and retro's answer is not even a platform check —
/// it asks whether the binary was staged (`RetroEngine.supported`).
///
/// Dala is in none of them. It is on no branch of `_pickBotMove` at all.
const _full = {'squarefish', 'stockfish', 'horizon', 'retro', 'garbo', 'maia'};

/// A build whose retro binaries were not staged — the gap opens in the MIDDLE
/// of the order (retro averages 1243), which is where a mis-ordered sheet is
/// hardest to notice by eye.
const _noRetro = {'squarefish', 'stockfish', 'horizon', 'garbo', 'maia'};

/// Android: QuickJS rather than JavaScriptCore, so none of the three has been
/// checked to run there (#46) and only the unconditional families remain.
const _jsOnly = {'squarefish', 'stockfish', 'horizon'};

List<String> _labels(List<RosterGroup> gs) => [for (final g in gs) g.label];

Future<void> _loadRoboto() async {
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('assets/fonts/Roboto-$w.ttf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }
}

/// A roster small enough that every row of the grouped sheet is laid out at
/// once — a `ListView` builds only what is visible, and an offscreen heading
/// would make an order assertion meaningless.
///
/// Only the three UNCONDITIONAL families: this is the one test that goes
/// through the real `_playableFamilies`, and Garbo and Maia are supported by
/// the host platform (`Platform.isMacOS`), not by the test. CI runs on Ubuntu,
/// where a Garbo row would silently vanish and take the assertions with it.
///
/// Horizon (550, 860) and Squarefish (600, 900) INTERLEAVE by elo, so a flat
/// sort of the old kind and the grouped sheet disagree about this fixture —
/// which is what makes the rendered order worth asserting at all.
final _smallRoster = <Persona>[
  _p('stockfish', 2000),
  _p('squarefish', 900),
  _p('horizon', 550),
  _p('squarefish', 600),
  _p('horizon', 860),
];

/// A bot whose `personaById` resolves the 2026-07-21 rename, as the real brain
/// does. Settings still hold ids like `square-900`, and the picker's selected
/// tile is found by resolving them — not by comparing the raw string.
class _RenamingBot extends FakeBot {
  final Map<String, String> aliases;
  const _RenamingBot(super.byId, this.aliases);
  @override
  Persona? personaById(String id) => byId[aliases[id] ?? id];
}

Future<GameController> _sheetGame(List<Persona> roster,
    {Map<String, String> aliases = const {}}) async {
  final settings = await loadSettings();
  return GameController(
    FakeArbiter(),
    _RenamingBot({for (final p in roster) p.id: p}, aliases),
    FakeGrading(),
    settings,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('families are ordered by the average elo of the personas shown', () {
    final groups = groupRoster(_roster, playable: _full);
    expect(_labels(groups),
        ['Horizon', 'Squarefish', 'Retro', 'Maia', 'Garbo', 'Stockfish']);
    // The averages the order is claimed to come from, so a green order test
    // cannot be a coincidence of some other sort key (weakest member, say,
    // gives Horizon/Squarefish/Retro/Maia/Stockfish/Garbo instead).
    expect([for (final g in groups) g.averageElo.round()],
        [705, 1150, 1243, 1507, 2020, 2150]);
  });

  test('members ascend by elo inside each group', () {
    for (final g in groupRoster(_roster, playable: _full)) {
      final elos = [for (final p in g.members) p.elo];
      expect(elos, orderedEquals(List.of(elos)..sort()),
          reason: '${g.label} is out of order');
    }
  });

  test('grouping loses and duplicates nothing', () {
    final groups = groupRoster(_roster, playable: _full);
    final grouped = [for (final g in groups) ...g.members.map((p) => p.id)];
    final expected =
        _roster.where((p) => _full.contains(p.family)).map((p) => p.id);
    expect(grouped.toSet(), expected.toSet());
    expect(grouped.length, expected.length, reason: 'a persona was duplicated');
  });

  // The load-bearing test: it is the only one that can tell an order computed
  // AFTER the filter from one computed before it. Dala plays nowhere and
  // averages 1107, so a pre-filter order hands back a Dala heading at index 1
  // with no members under it, and pushes every later family down one.
  test('an unplayable family neither renders nor shifts the ones that do', () {
    final groups = groupRoster(_roster, playable: _noRetro);
    expect(_labels(groups),
        ['Horizon', 'Squarefish', 'Maia', 'Garbo', 'Stockfish'],
        reason: 'a family that cannot play must leave no trace at all — not a '
            'heading, and not a gap in the order');
    // The same families the full sheet keeps, in the same relative order: the
    // filter removes groups, it never rearranges the survivors.
    expect(
        _labels(groups),
        _labels(groupRoster(_roster, playable: _full))
            .where((l) => _noRetro.contains(l.toLowerCase()))
            .toList());
  });

  test('no group can be empty, whatever the filter allows', () {
    for (final (name, filter) in [
      ('full', _full),
      ('no retro', _noRetro),
      ('js only', _jsOnly),
    ]) {
      final groups = groupRoster(_roster, playable: filter);
      expect(groups, isNotEmpty, reason: '$name showed nothing');
      for (final g in groups) {
        expect(g.members, isNotEmpty, reason: '$name rendered an empty $g');
      }
      expect(_labels(groups).toSet().length, groups.length,
          reason: '$name split a family across two headings');
    }
  });

  test('every playable family has a heading and no other does', () {
    final labels = _labels(groupRoster(_roster, playable: _jsOnly)).toSet();
    expect(labels.map((l) => l.toLowerCase()).toSet(), _jsOnly);
  });

  group('rendered', () {
    setUpAll(_loadRoboto);

    testWidgets('headings appear above their members, in average-elo order',
        (tester) async {
      // iPhone SE / mini class, the narrowest phone the app targets. The
      // default test font is Ahem, whose metrics are a fiction — the real
      // Roboto is loaded above so a no-overflow result means something.
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = await _sheetGame(_smallRoster);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF262421),
          body: RosterSheet(game: game),
        ),
      ));
      await tester.pump();

      // The sheet really built its rows — a later assertion about order would
      // pass trivially over an empty list.
      expect(find.byType(ListTile), findsNWidgets(_smallRoster.length));

      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      // Averages: Horizon 705, Squarefish 750, Stockfish 2000.
      expect(y('Horizon'), lessThan(y('Squarefish')));
      expect(y('Squarefish'), lessThan(y('Stockfish')));

      // Every member under its own heading, with nothing from another family
      // in between. Horizon 860 above Squarefish 600 is the assertion the old
      // flat list fails: by elo alone Squarefish 600 comes second.
      expect(y('Horizon'), lessThan(y('Horizon 550  ·  550')));
      expect(y('Horizon 550  ·  550'), lessThan(y('Horizon 860  ·  860')));
      expect(y('Horizon 860  ·  860'), lessThan(y('Squarefish')));
      expect(y('Squarefish'), lessThan(y('Squarefish 600  ·  600')));
      expect(y('Squarefish 600  ·  600'), lessThan(y('Squarefish 900  ·  900')));
      expect(y('Squarefish 900  ·  900'), lessThan(y('Stockfish')));
      expect(y('Stockfish'), lessThan(y('Stockfish 2000  ·  2000')));

      // Members are indented clear of the heading's mark and line up under its
      // label — with the per-row glyph gone, that column IS what ties a row to
      // its group.
      final markLeft = tester.getTopLeft(find.byType(CircleAvatar).first).dx;
      final labelLeft = tester.getTopLeft(find.text('Squarefish')).dx;
      expect(tester.getTopLeft(find.text('Squarefish 900  ·  900')).dx,
          labelLeft);
      expect(labelLeft, greaterThan(markLeft));

      // A RenderFlex overflow is a runtime error: neither the analyzer nor a
      // green suite says anything about it.
      expect(tester.takeException(), isNull,
          reason: 'the grouped sheet overflowed at 375px');
    });

    testWidgets('a pre-rename id still highlights its tile', (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = await _sheetGame(_smallRoster,
          aliases: {'square-900': 'squarefish-900'});
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF262421),
          body: RosterSheet(game: game, current: 'square-900'),
        ),
      ));
      await tester.pump();

      final selected = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((t) => t.selected)
          .toList();
      expect(selected.length, 1,
          reason: 'a stored pre-rename id must still find its persona — '
              'comparing raw ids highlights nothing');
      expect((selected.single.title as Text).data, contains('Squarefish 900'));
    });
  });
}
