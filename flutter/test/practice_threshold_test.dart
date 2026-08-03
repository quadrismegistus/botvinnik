// Where the practice bar lives, and what it is allowed to govern (#213).
//
// Three claims, and the second one is a bug the issue did not know about:
//
//  1. the bar filters the queue, and 5% means "everything" because 5 is
//     [kCollectMin], the floor everything is collected at;
//  2. the bar does NOT decide when a rated game refuses a move. Those were one
//     number, and the only control that set it was labelled "Practice mistakes
//     losing at least" and said nothing about rated games — so lowering your
//     practice bar to 5% made refuse-blunders reject every 5% mistake in a
//     rated game, from a screen that never mentioned it. #213 moves that
//     control to the Practice tab, which would have buried the coupling
//     further;
//  3. a "practise this game's mistakes" session ignores the bar by default —
//     #197's rule, unchanged — but that is now a setting rather than an
//     implication, because it is defensible rather than obvious.
//
// Pure Dart: all three are controller/store behaviour. The banner that states
// (3) is asserted in test/vm/practice_tab_test.dart, where the real Roboto is.
//
//   cd flutter && flutter test test/practice_threshold_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/stores/practice_controller.dart';

import 'support/game_harness.dart' show loadSettings;
import 'support/practice_harness.dart';

const _aFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _bFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the bar filters the queue', () {
    test('and 5% means everything, because 5 is the collection floor', () async {
      final settings = await loadSettings();
      final h = makePractice([
        practiceItem(_aFen, drop: 6),
        practiceItem(_bFen, drop: 25),
      ]);
      h.practice.settings = settings;

      settings.collectThreshold = 20;
      expect(h.practice.servable.map((i) => i['drop']), [25]);

      settings.collectThreshold = kCollectMin.round();
      expect(h.practice.servable, hasLength(2),
          reason: 'the menu offers 5% as "Everything collected" — it must be');
    });
  });

  group('the bar does not reach a rated game', () {
    test('refuseThreshold is its own number', () async {
      // The coupling #213 found. One `expect` per direction, because a split
      // that moved BOTH names to one field would satisfy either alone.
      final settings = await loadSettings();
      settings.collectThreshold = 5;
      settings.refuseThreshold = 30;

      expect(settings.collectThreshold, 5);
      expect(settings.refuseThreshold, 30,
          reason: 'the practice bar moved the refusal bar with it');

      settings.refuseThreshold = 10;
      expect(settings.collectThreshold, 5,
          reason: 'and the refusal bar moved the practice bar with it');
    });

    test('an upgrade keeps the refusal bar the player had chosen', () async {
      // Migration, and it is not cosmetic: the two were one setting, so a
      // player who moved their bar to 5% chose that for refusals too, whether
      // they knew it or not. Defaulting the new key to 15 would silently
      // loosen refusal for them on the first launch after the split.
      final settings = await loadSettings(prefs: {
        'botvinnik-collect-threshold': '5',
        // no botvinnik-refuse-threshold — this is the upgrade case
      });

      expect(settings.collectThreshold, 5);
      expect(settings.refuseThreshold, 5,
          reason: 'refusal silently loosened to the default on upgrade');
    });

    test('and a stored refusal bar wins once it exists', () async {
      final settings = await loadSettings(prefs: {
        'botvinnik-collect-threshold': '5',
        'botvinnik-refuse-threshold': '30',
      });

      expect(settings.collectThreshold, 5);
      expect(settings.refuseThreshold, 30);
    });
  });

  group('a game session and the bar', () {
    Future<PracticeController> session({required bool allDrops}) async {
      final settings = await loadSettings();
      settings.collectThreshold = 20;
      settings.gameSessionAllDrops = allDrops;
      final h = makePractice([
        practiceItem(_aFen, drop: 6), // under the bar
        practiceItem(_bFen, drop: 25), // over it
      ]);
      h.practice.settings = settings;
      h.practice.startGameSession({_aFen: 'a2a3', _bFen: 'a2a3'});
      return h.practice;
    }

    test('drills every mistake by default — #197 unchanged', () async {
      final p = await session(allDrops: true);
      final seen = <num>[];
      while (p.current != null) {
        seen.add(p.current!['drop'] as num);
        p.nextPuzzle();
      }
      expect(seen, hasLength(2),
          reason: 'you picked the game, so the queue bar is not the question');
      expect(seen, contains(6));
    });

    test('but honours the bar when asked to', () async {
      final p = await session(allDrops: false);
      final seen = <num>[];
      while (p.current != null) {
        seen.add(p.current!['drop'] as num);
        p.nextPuzzle();
      }
      expect(seen, [25]);
    });

    test('and a filtered session still ENDS rather than looping', () async {
      // The failure mode a naive filter would produce: an item that is in
      // scope, never served, and never servable is a `remaining` list that
      // never empties. `_gameServed` is marked for the skipped ones too.
      final p = await session(allDrops: false);
      for (var i = 0; i < 10 && p.current != null; i++) {
        p.nextPuzzle();
      }
      expect(p.current, isNull, reason: 'the session looped');
      expect(p.gameDoneNote, isNotNull);
    });
  });
}
