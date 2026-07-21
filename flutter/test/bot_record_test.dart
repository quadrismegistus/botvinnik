// The per-persona head-to-head record shown in the roster picker (#142).
//
// Two things have to hold or the count answers the wrong question:
//
//   - a game archived under a PRE-RENAME id (`square-*`/`fish-*`, 2026-07-21)
//     must count under the persona's CURRENT id — the id the roster row
//     carries — because the aggregation keys by the RESOLVED id, not the raw
//     stored string. Comparing the raw id is the bug that shipped twice this
//     session; the `real rename migration` group proves the fix over the actual
//     brain, and reintroducing a raw-id key reddens it (see the note there).
//   - an IMPORTED game (a PGN with real player names, no persona) is not a game
//     against a roster bot and must not count — the same `if (!p) continue`
//     guard `estimatePlayerElo` opens with. Deleting that guard reddens the
//     import test and nothing else.
//
//   cd flutter && flutter test test/bot_record_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/bot_api.dart';
import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/stores/bot_record_store.dart';

import 'support/fake_db.dart';
import 'support/node_brain.dart';

Persona _persona(String id, {int elo = 1200, String family = 'squarefish'}) =>
    Persona({
      'id': id,
      'name': id,
      'elo': elo,
      'family': family,
      'blurb': '',
    });

/// A resolver in the shape [GameController.personaFor] has: null in, null out,
/// and an alias table standing in for the brain's rename map.
Persona? Function(String?) _resolve(
  Map<String, Persona> byId, [
  Map<String, String> aliases = const {},
]) =>
    (id) => id == null ? null : byId[aliases[id] ?? id];

/// A record in the shape GameController._saveGame writes, reduced to the fields
/// the aggregation reads. [persona] null models an analysis or imported game:
/// the save path omits `botPersona` and `botColor` entirely for those.
Map<String, dynamic> _game({
  String? persona = 'squarefish-1200',
  required String result,
  String? botColor = 'b',
  bool bothSides = false,
}) =>
    {
      'id': 'g-${persona ?? 'none'}-$result-${botColor ?? 'x'}',
      'result': result,
      'botPersona': ?persona,
      if (bothSides) 'botBothSides': true,
      'botColor': persona == null ? null : botColor,
    };

void main() {
  final byId = {
    for (final id in ['squarefish-1000', 'squarefish-1200', 'stockfish-2000'])
      id: _persona(id, elo: int.parse(id.split('-').last))
  };

  group('aggregation (fake resolver)', () {
    final resolve = _resolve(byId);

    test('a human White win is a win, a human White loss is a loss', () {
      final r = botRecordsFrom([
        _game(result: '1-0', botColor: 'b'), // human White, White won  => win
        _game(result: '0-1', botColor: 'b'), // human White, Black won  => loss
      ], resolve);
      expect(r['squarefish-1200'], const BotRecord(won: 1, lost: 1));
    });

    test('a human Black win is a win, a human Black loss is a loss', () {
      final r = botRecordsFrom([
        _game(result: '0-1', botColor: 'w'), // human Black, Black won  => win
        _game(result: '1-0', botColor: 'w'), // human Black, White won  => loss
      ], resolve);
      expect(r['squarefish-1200'], const BotRecord(won: 1, lost: 1));
    });

    test('a draw counts either colour', () {
      final r = botRecordsFrom([
        _game(result: '1/2-1/2', botColor: 'b'),
        _game(result: '1/2-1/2', botColor: 'w'),
      ], resolve);
      expect(r['squarefish-1200'], const BotRecord(drawn: 2));
    });

    test("an unfinished game ('*') counts as nothing", () {
      final r = botRecordsFrom([_game(result: '*')], resolve);
      expect(r, isEmpty, reason: '* is neither a win, a loss, nor a draw');
    });

    test('a bot-vs-bot game has no human result and is excluded', () {
      // playerColor falls back to White when both sides carry a persona, so
      // this archives with a real result and botColor 'b' and would otherwise
      // read as a human White win — exactly the #144 crown trap.
      final r = botRecordsFrom(
        [_game(result: '1-0', botColor: 'b', bothSides: true)],
        resolve,
      );
      expect(r, isEmpty, reason: 'nobody human played it');
    });

    test('an imported / analysis game (no persona) is excluded — CONTROL', () {
      // Deleting the `if (p == null) continue` guard in botRecordsFrom is what
      // this pins: with the guard gone a resolve(null) => null would throw on
      // `null.id`, or worse be keyed under a null persona.
      final r = botRecordsFrom([
        _game(persona: null, result: '1-0'),
        _game(persona: null, result: '0-1'),
      ], resolve);
      expect(r, isEmpty);
    });

    test('records are kept per persona', () {
      final r = botRecordsFrom([
        _game(persona: 'squarefish-1200', result: '1-0', botColor: 'b'),
        _game(persona: 'stockfish-2000', result: '0-1', botColor: 'b'),
      ], resolve);
      expect(r['squarefish-1200'], const BotRecord(won: 1));
      expect(r['stockfish-2000'], const BotRecord(lost: 1));
    });

    test('a renamed-id game keys under the CURRENT persona id — GOLDEN', () {
      // The resolver maps the pre-rename id to the same persona the post-rename
      // id resolves to. Key by the RESOLVED id and both games land on one
      // record; key by the raw stored string and `square-1000` splits off into
      // its own bucket that the roster row (which carries `squarefish-1000`)
      // never reads. Reintroduce that raw-id key and this is the test that
      // reddens.
      final resolveAliased =
          _resolve(byId, {'square-1000': 'squarefish-1000'});
      final r = botRecordsFrom([
        _game(persona: 'square-1000', result: '1-0', botColor: 'b'),
        _game(persona: 'squarefish-1000', result: '1/2-1/2', botColor: 'b'),
      ], resolveAliased);
      expect(r.keys, ['squarefish-1000'],
          reason: 'the pre-rename id must not survive as its own key');
      expect(r['squarefish-1000'], const BotRecord(won: 1, drawn: 1));
    });
  });

  // The store over the REAL brain, the same discipline as player_rating_test:
  // a fake resolver re-implements the rename map and so proves nothing about
  // whether the migration is actually honoured. This evaluates the shipped
  // bundle through node.
  group('the real rename migration (node brain)', () {
    final bot = BotApi(NodeBrainBridge());
    Persona? resolve(String? id) => id == null ? null : bot.personaById(id);

    setUpAll(() {
      // A missing node FAILS rather than skips — an unrun migration test is as
      // reassuring as none. (node_brain.dart makes the same argument.)
      expect(File(NodeBrainBridge.bundle).existsSync(), isTrue,
          reason: 'run from flutter/ — assets/brain.js is the shipped bundle');
    });

    test('a game stored under the pre-rename id counts under the current one',
        () async {
      final store = BotRecordStore(FakeDb([
        // `square-1000` was the id before the 2026-07-21 rename; the brain's
        // personaById maps it to `squarefish-1000`. A raw `==` here counts
        // nothing.
        _game(persona: 'square-1000', result: '1-0', botColor: 'b'),
      ]));
      await store.refresh(resolve);

      expect(store.recordFor('squarefish-1000'), const BotRecord(won: 1),
          reason: 'the renamed game must reach the current persona');
      expect(store.records.containsKey('square-1000'), isFalse,
          reason: 'the pre-rename id must not survive as its own key');
    });

    test('an imported game with no persona is excluded by the real resolver',
        () async {
      final store = BotRecordStore(FakeDb([
        _game(persona: null, result: '1-0'),
        _game(persona: 'squarefish-1200', result: '1-0', botColor: 'b'),
      ]));
      await store.refresh(resolve);

      expect(store.records.keys, ['squarefish-1200'],
          reason: 'only the persona game counts');
    });
  });

  // provider_parity_test scans for `context.read<*Api>` reads, and this store
  // is not an Api and is not watched from the tree — so nothing there guards
  // that pickBot's `context.read<BotRecordStore>()` has a provider. Without one
  // the app throws ProviderNotFoundException the moment the roster sheet opens,
  // and no widget test (they pump RosterSheet directly) would catch it.
  group('wiring', () {
    test('BotRecordStore is read by the picker and provided in main.dart', () {
      final picker = File('lib/ui/roster_picker.dart').readAsStringSync();
      expect(picker, contains('context.read<BotRecordStore>()'),
          reason: 'this guard is watching for a reader that no longer exists');

      final provided = File('lib/main.dart')
          .readAsStringSync()
          .split('\n')
          .any((l) => l.contains('Provider') && l.contains('BotRecordStore('));
      expect(provided, isTrue,
          reason: 'the picker reads BotRecordStore from the tree but main.dart '
              'never provides it — the app throws ProviderNotFoundException on '
              'the first roster sheet');
    });
  });
}
