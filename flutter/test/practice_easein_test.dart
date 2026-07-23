// Ease-in threading (#143): the web's `botvinnik-practice-easein` setting,
// which the Flutter port dropped by hardcoding `easyFirst: true` at every
// selection call. This pins that the SettingsStore bool actually reaches the
// brain's `nextItem` — the last positional argument — through each route that
// serves a puzzle.
//
//   cd flutter && flutter test test/practice_easein_test.dart

import 'package:botvinnik_mobile/stores/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/practice_harness.dart';

const _forkFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _pinFen = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';

/// A SettingsStore over mock prefs — the injected source the controller reads
/// `easeIn` from.
Future<SettingsStore> settings([Map<String, Object> initial = const {}]) {
  SharedPreferences.setMockInitialValues(initial);
  return SettingsStore.load();
}

/// The `easyFirst` value the LAST recorded `nextItem` handed the brain — its
/// sixth positional argument (items, excludeId, now, motif, rand, easyFirst).
bool lastEasyFirst(FakeBridge bridge) => bridge.nextItemArgs.last[5] as bool;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('with no settings injected it defaults on, as before the setting',
      () async {
    final h = makePractice([practiceItem(_forkFen)]);
    h.practice.startSession();
    expect(lastEasyFirst(h.bridge), isTrue);
  });

  test('ease-in off reaches nextItem through startSession', () async {
    final h = makePractice([practiceItem(_forkFen)]);
    h.practice.settings = await settings({'flutter.botvinnik-practice-easein': '0'});

    h.practice.startSession();
    expect(lastEasyFirst(h.bridge), isFalse,
        reason: 'a strict-due-order session must not ask the brain to ease in');
  });

  test('ease-in on reaches nextItem through startSession', () async {
    final h = makePractice([practiceItem(_forkFen)]);
    h.practice.settings = await settings(); // default on

    h.practice.startSession();
    expect(lastEasyFirst(h.bridge), isTrue);
  });

  test('nextPuzzle honours the setting', () async {
    final h = makePractice([practiceItem(_forkFen), practiceItem(_pinFen)]);
    final s = await settings();
    h.practice.settings = s;

    s.easeIn = false;
    h.practice.startSession();
    expect(lastEasyFirst(h.bridge), isFalse);

    h.practice.nextPuzzle();
    expect(lastEasyFirst(h.bridge), isFalse,
        reason: 'the same setting must ride every serve, not just the first');

    // Flip it live and the very next serve reflects it — the controller reads
    // through to settings each call rather than caching at session start.
    s.easeIn = true;
    h.practice.nextPuzzle();
    expect(lastEasyFirst(h.bridge), isTrue);
  });

  test('the motif filter path threads it too', () async {
    final h = makePractice([practiceItem(_forkFen, motifs: ['fork'])]);
    h.practice.settings = await settings({'flutter.botvinnik-practice-easein': '0'});

    h.practice.setMotifFilter('fork');
    expect(lastEasyFirst(h.bridge), isFalse);
  });
}
