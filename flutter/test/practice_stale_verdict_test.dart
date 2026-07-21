// #155: a verdict that arrives after the puzzle changed must be dropped, not
// applied to whichever puzzle is on screen when it lands.
//
// checkAttempt awaits ~1.5s of engine search. Two things can serve a different
// puzzle inside that window — Skip/Next, which has been there since the tab
// shipped, and the delete button (#137), which added a second door to the same
// hole. Either way the OLD puzzle's pass/fail used to move the NEW puzzle's
// Leitner box, corrupting the schedule for both and failing nothing.
//
// Pure Dart: the race is entirely in the controller, and holding the check's
// future lets the test resolve the search exactly where it wants to rather
// than negotiating with a widget test's fake clock.
//
//   cd flutter && flutter test test/practice_stale_verdict_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart';
import 'package:botvinnik_mobile/engine/arbiter.dart';

import 'support/game_harness.dart';
import 'support/practice_harness.dart';

const _fenA = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _fenB = 'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2';
const _afterE4Fen =
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

/// A search the test resolves by hand, which is the whole window the bug
/// lives in. [FakeArbiter] can only hang forever or resolve on a timer;
/// neither lets a test stand inside the await.
class ParkedArbiter implements SearchArbiter {
  final _parked = Completer<List<EngineMove>?>();
  int searches = 0;

  void resolve([List<EngineMove>? lines = kFakeLines]) =>
      _parked.complete(lines);

  @override
  Future<List<EngineMove>?> search({
    required String fen,
    String? ownerFen,
    required int depth,
    required int multiPv,
    int? movetimeMs,
    List<List<String>> extraOptions = const [],
    required SearchPriority priority,
    void Function(List<EngineMove>)? onUpdate,
  }) {
    searches++;
    return _parked.future;
  }

  @override
  Future<List<EngineMove>?> analysis(String fen,
          {void Function(List<EngineMove>)? onUpdate}) =>
      Completer<List<EngineMove>?>().future;

  @override
  void bumpGeneration() {}
  @override
  void cancelAnalyses({required String exceptFen}) {}
  @override
  Object? get engineError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  // The control. Without it every assertion below is satisfied by a
  // checkAttempt that records nothing under any circumstances — which is a
  // fix nobody would notice and everybody would suffer.
  test('an uninterrupted check records the result for the item it graded',
      () async {
    final arbiter = ParkedArbiter();
    final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)],
        arbiter: arbiter);
    h.practice.startSession();
    expect(h.practice.current?['id'], _fenA);

    final check = h.practice.checkAttempt('e2e4', 'e4', _afterE4Fen);
    expect(arbiter.searches, 1, reason: 'the check must be inside the await');
    arbiter.resolve();
    await check;

    final recorded =
        h.bridge.calls.where((c) => c.fn == 'recordResult').toList();
    expect(recorded, hasLength(1));
    expect(recorded.single.args[1], _fenA);
    expect(h.practice.attempt?.pass, isFalse,
        reason: 'e4 is not the stored best and FakeGrading scores it a loss');
    // The commit reached the store, not just the in-memory list.
    expect(h.db.kv, isNotEmpty);
  });

  // Three doors onto the same hole. Skip has had it since the tab shipped;
  // delete arrived with #137, and picking a row out of the collection browser
  // is the third — you can open the list while a check is in flight, and the
  // list is the one route to a puzzle the scheduler did not choose.
  for (final door in ['skip', 'delete', 'browser']) {
    test('a $door mid-check drops the verdict instead of landing it on the '
        'next puzzle', () async {
      final arbiter = ParkedArbiter();
      final h = makePractice([practiceItem(_fenA), practiceItem(_fenB)],
          arbiter: arbiter);
      h.practice.startSession();
      expect(h.practice.current?['id'], _fenA);

      final check = h.practice.checkAttempt('e2e4', 'e4', _afterE4Fen);
      expect(h.practice.checking, isTrue);
      expect(arbiter.searches, 1);

      if (door == 'skip') {
        h.practice.nextPuzzle();
      } else if (door == 'delete') {
        await h.practice.remove(_fenA);
      } else {
        h.practice.serveItem(_fenB);
      }
      expect(h.practice.current?['id'], _fenB,
          reason: 'the $door must have served the other puzzle');

      arbiter.resolve();
      await check;

      expect(h.bridge.calls.where((c) => c.fn == 'recordResult'), isEmpty,
          reason: 'the abandoned verdict must not move ANY Leitner box — '
              'not the puzzle that is gone, and not the one now on screen');
      // The freshly served puzzle is untouched by the check that outlived its
      // own puzzle: no verdict on the board, no spinner, nothing pending.
      expect(h.practice.attempt, isNull);
      expect(h.practice.checking, isFalse);
      expect(h.practice.pendingUci, isNull);
      expect(h.practice.sessionSolved, 0);
      expect(
          h.practice.items.firstWhere((i) => i['id'] == _fenB)['box'], 0,
          reason: 'box 0 is where practiceItem starts it');
      expect(h.practice.items.firstWhere((i) => i['id'] == _fenB)['attempts'],
          0);
    });
  }
}

// Not tested here, and deliberately: whether a delete mid-check can resurrect
// the deleted puzzle. Measured with the guard removed, it cannot — recordResult
// re-reads the `items` FIELD rather than a value captured before the await, so
// the map runs over the already-shortened list and finds no id to update. A
// test for it would pass with the bug present and prove nothing.
