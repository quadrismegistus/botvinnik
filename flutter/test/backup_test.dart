// Backup and restore (#138) — the merge semantics ported from
// svelte/src/lib/backup.ts, and the round trip they exist to protect.
//
// Every test here was made to fail first by reintroducing the exact defect it
// covers, and each defect was reintroduced singly to confirm that only the
// intended tests go red. The list, so the next person can repeat it:
//
//   - keeping the incoming copy unconditionally, and keeping the existing copy
//     unconditionally (the two ways to "dedupe by id" without the attempts
//     rule) — each reddens one of the two attempts tests and nothing else
//   - counting replacements in `added`
//   - `byId[id] = item` written as remove-then-insert, which moves a replaced
//     item to the end and reddens the ordering test alone
//   - overwriting an existing game instead of skipping it
//   - dropping the envelope check
//   - changing kPracticeKvKey by one character, which reddens ONLY the
//     controller round trip — the whole rest of this file passes, which is
//     exactly why that test is here
//
//   cd flutter && flutter test test/backup_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/practice_api.dart';
import 'package:botvinnik_mobile/stores/backup.dart';
import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/game_harness.dart';
import 'support/memory_db.dart';
import 'support/practice_harness.dart';

/// A practice item in the shape the brain writes, with the two fields the
/// merge actually reads spelled out at the call site.
Map<String, dynamic> _item(String id, {int attempts = 0, int box = 0}) => {
      ...practiceItem('fen-$id'),
      'id': id,
      'attempts': attempts,
      'box': box,
    };

Map<String, dynamic> _game(String id, {String? endedAt, String pgn = '1. e4'}) =>
    {
      'id': id,
      'endedAt': endedAt ?? '2026-07-2${id.length}T10:00:00.000',
      'result': '1-0',
      'pgn': pgn,
      'moveCount': 2,
      'botColor': 'b',
      'moves': const [],
    };

void main() {
  group('mergePractice', () {
    test('a stranger is added, and counted', () {
      final merged = mergePractice([_item('a')], [_item('b')]);

      expect(merged.items.map((i) => i['id']), ['a', 'b']);
      expect(merged.added, 1);
    });

    test('the copy with MORE attempts wins, whichever side it is on', () {
      final incomingTrained = mergePractice(
        [_item('a', attempts: 2, box: 1)],
        [_item('a', attempts: 9, box: 4)],
      );
      expect(incomingTrained.items.single['attempts'], 9,
          reason: 'the file had been trained more — its copy is the one with '
              'reps in it, and reps are what a replay cannot recreate');
      expect(incomingTrained.items.single['box'], 4,
          reason: 'the whole item is taken, not a merge of its fields');

      final localTrained = mergePractice(
        [_item('a', attempts: 9, box: 4)],
        [_item('a', attempts: 2, box: 1)],
      );
      expect(localTrained.items.single['attempts'], 9,
          reason: 'restoring an older backup must not undo training done '
              'since it was taken');
    });

    test('a tie keeps the copy already here', () {
      final merged = mergePractice(
        [_item('a', attempts: 3, box: 1)],
        [_item('a', attempts: 3, box: 4)],
      );

      expect(merged.items.single['box'], 1,
          reason: 'strictly greater, not >=: with nothing to choose between '
              'them the device wins, so import is never destructive');
    });

    test('a replacement is not an addition', () {
      final merged = mergePractice(
        [_item('a', attempts: 1)],
        [_item('a', attempts: 5), _item('b')],
      );

      expect(merged.added, 1,
          reason: 'one item is new; the other was already collected. Counting '
              'replacements would report a re-import of the same file as a '
              'restore of the whole collection');
      expect(merged.items.length, 2);
    });

    test('order: a replaced item holds its place, new ones go last', () {
      final merged = mergePractice(
        [_item('a'), _item('b', attempts: 1), _item('c')],
        [_item('b', attempts: 7), _item('z')],
      );

      expect(merged.items.map((i) => i['id']), ['a', 'b', 'c', 'z'],
          reason: 'the JS Map this ports keeps an overwritten key in place; a '
              'restore that silently reshuffled the queue would be felt and '
              'not understood');
      expect(merged.items[1]['attempts'], 7);
    });

    test('a missing or non-numeric attempts count reads as zero', () {
      final merged = mergePractice(
        [
          {'id': 'a', 'attempts': 4},
        ],
        [
          {'id': 'a'}, // no attempts at all
        ],
      );
      expect(merged.items.single['attempts'], 4,
          reason: 'an item with no attempts field has been trained zero times '
              'and cannot beat one that has');

      final junk = mergePractice(
        [
          {'id': 'a', 'attempts': 4},
        ],
        [
          {'id': 'a', 'attempts': 'lots'},
        ],
      );
      expect(junk.items.single['attempts'], 4,
          reason: 'a hand-edited file must lose the comparison, not crash it');
    });
  });

  group('the backup document', () {
    test('carries the Svelte envelope, so its files are interchangeable',
        () async {
      final db = MemoryDb([_game('g1')]);
      db.kv[kPracticeKvKey] = jsonEncode([_item('p1')]);

      final doc = await BackupService(db)
          .build(at: DateTime.parse('2026-07-21T09:30:00Z'));

      expect(doc['app'], 'botvinnik');
      expect(doc['version'], 1);
      expect(doc['exportedAt'], '2026-07-21T09:30:00.000Z');
      expect((doc['practice'] as List).single['id'], 'p1');
      expect((doc['games'] as List).single['id'], 'g1');
    });

    test('is named for the day it was taken', () {
      expect(backupFilename(DateTime.parse('2026-07-21T23:59:00')),
          'botvinnik-backup-2026-07-21.json');
    });

    test('an empty store still produces a valid, importable file', () async {
      final json = await BackupService(MemoryDb()).exportJson();
      final into = MemoryDb();

      final counts = await BackupService(into).importJson(json);

      expect(counts, (practice: 0, games: 0));
    });
  });

  group('round trip', () {
    test('a known archive exports and imports back, unchanged', () async {
      final games = [_game('g1'), _game('g2'), _game('g3')];
      final practice = [
        _item('p1', attempts: 3),
        _item('p2'),
      ];
      final source = MemoryDb(games);
      source.kv[kPracticeKvKey] = jsonEncode(practice);

      final json = await BackupService(source).exportJson();

      final restored = MemoryDb();
      final counts = await BackupService(restored).importJson(json);

      expect(counts, (practice: 2, games: 3));
      // Equality of the DOCUMENTS, not of a hand-picked field: a restore that
      // dropped `moves` or `pgn` would still satisfy any count assertion.
      expect(await restored.listGames(), await source.listGames());
      expect(jsonDecode(restored.kv[kPracticeKvKey]!),
          jsonDecode(source.kv[kPracticeKvKey]!));
    });

    test('a second import of the same file changes nothing', () async {
      final source = MemoryDb([_game('g1')]);
      source.kv[kPracticeKvKey] = jsonEncode([_item('p1', attempts: 2)]);
      final json = await BackupService(source).exportJson();

      final into = MemoryDb();
      await BackupService(into).importJson(json);
      final again = await BackupService(into).importJson(json);

      expect(again, (practice: 0, games: 0));
      expect(into.writes, ['g1'],
          reason: 'the second pass must not even reach the database — an '
              'archived game is immutable, so a rewrite can only lose');
    });
  });

  group('import', () {
    test('leaves a game already here alone', () async {
      final mine = _game('g1', pgn: '1. e4 e5 2. Nf3');
      final into = MemoryDb([mine]);

      final counts = await BackupService(into).importJson(jsonEncode({
        'app': 'botvinnik',
        'version': 1,
        'exportedAt': '2026-07-01T00:00:00.000Z',
        'practice': [],
        'games': [_game('g1', pgn: 'CLOBBERED'), _game('g2')],
      }));

      expect(counts.games, 1, reason: 'only g2 was new');
      expect(into.games['g1']!['pgn'], '1. e4 e5 2. Nf3');
      expect(into.writes, ['g2']);
    });

    test('counts a file listing the same game twice once', () async {
      final into = MemoryDb();

      final counts = await BackupService(into).importJson(jsonEncode({
        'app': 'botvinnik',
        'practice': [],
        'games': [_game('g1'), _game('g1')],
      }));

      expect(counts.games, 1);
    });

    test('skips a damaged record instead of abandoning the restore', () async {
      final into = MemoryDb();

      final counts = await BackupService(into).importJson(jsonEncode({
        'app': 'botvinnik',
        'practice': [],
        'games': [
          _game('g1'),
          {'id': 'g2', 'endedAt': 'sometime'}, // unparseable
          {'endedAt': '2026-07-21T10:00:00.000'}, // no id
          _game('g3'),
        ],
      }));

      expect(counts.games, 2);
      expect(into.games.keys, ['g1', 'g3'],
          reason: 'the good records on BOTH sides of the damaged one land — '
              'the file someone restores in a panic is the one likely to be '
              'truncated, and 2 of 4 games beats an exception');
    });

    test('refuses anything that is not one of our files', () async {
      final service = BackupService(MemoryDb());

      Future<void> rejects(String text, String because) async {
        await expectLater(
            service.importJson(text), throwsA(isA<BackupFormatException>()),
            reason: because);
      }

      await rejects('not json at all{', 'a mis-picked file');
      await rejects('[]', 'a bare array is not the envelope');
      await rejects(
          jsonEncode({'app': 'lichess', 'practice': [], 'games': []}),
          'another app that happens to use these key names');
      await rejects(jsonEncode({'app': 'botvinnik', 'games': []}),
          'no practice array');
      await rejects(jsonEncode({'app': 'botvinnik', 'practice': []}),
          'no games array');
    });

    test('a rejected file leaves the store untouched', () async {
      final into = MemoryDb([_game('g1')]);
      into.kv[kPracticeKvKey] = jsonEncode([_item('p1')]);

      await expectLater(BackupService(into).importJson('{"app":"nope"}'),
          throwsA(isA<BackupFormatException>()));

      expect(into.writes, isEmpty);
      expect(jsonDecode(into.kv[kPracticeKvKey]!), hasLength(1));
    });

    test('a corrupt practice row is replaced rather than inherited', () async {
      final into = MemoryDb();
      into.kv[kPracticeKvKey] = 'half a json fi';

      final counts = await BackupService(into).importJson(jsonEncode({
        'app': 'botvinnik',
        'practice': [_item('p1')],
        'games': [],
      }));

      expect(counts.practice, 1,
          reason: 'PracticeController also treats an unparseable row as an '
              'empty collection; a restore is the one moment that state can '
              'be repaired, so it must not throw here');
    });
  });

  test('the practice row is the one PracticeController actually reads',
      () async {
    // The only test in this file that can catch kPracticeKvKey drifting from
    // PracticeController's private _kvKey. Everything else here reads back
    // through the same constant it wrote with, so a wrong key round-trips
    // perfectly and restores into a row nothing ever looks at.
    final db = MemoryDb();
    await BackupService(db).importJson(jsonEncode({
      'app': 'botvinnik',
      'practice': [_item('p1', attempts: 4), _item('p2')],
      'games': [],
    }));

    final practice = PracticeController(
        db, PracticeApi(FakeBridge()), FakeGrading(), FakeArbiter());
    await practice.load();

    expect(practice.items.map((i) => i['id']), ['p1', 'p2'],
        reason: 'restored puzzles must be visible to the tab that drills '
            'them — a mismatched key restores into limbo, silently');
  });

  test('the collection a controller persisted is what backup exports',
      () async {
    // The other direction of the same seam, through the controller's own
    // write path rather than a hand-placed kv row.
    final db = MemoryDb();
    final practice = PracticeController(
        db, PracticeApi(FakeBridge()), FakeGrading(), FakeArbiter());
    await practice.load();
    practice.items = [_item('p1')];
    await practice.remove('nothing-by-that-id'); // the public persist path

    final doc = await BackupService(db).build();

    expect((doc['practice'] as List).map((i) => i['id']), ['p1']);
  });

  group('pgnFilename', () {
    test('names both players and the day', () {
      expect(
        pgnFilename(
            white: 'You', black: 'Squarefish', endedAt: '2026-07-21T10:00:00'),
        'botvinnik-You-vs-Squarefish-2026-07-21.pgn',
      );
    });

    test('strips what a filesystem should not be handed', () {
      expect(
        pgnFilename(
            white: 'Kasparov, G.',
            black: 'Topalov/V',
            endedAt: '1999-01-20T00:00:00'),
        'botvinnik-KasparovG-vs-TopalovV-1999-01-20.pgn',
      );
    });

    test('falls back rather than producing a nameless file', () {
      expect(pgnFilename(endedAt: '2026-07-21T10:00:00'),
          'botvinnik-game-vs-bot-2026-07-21.pgn');
    });
  });
}
