// Retro through the REAL c-archive on iOS.
//
// The macOS twin of this (retro_native_test.dart) spawns a binary; there is no
// spawning here, so this exercises the other half of #80: a Go static archive
// linked into the app binary, its symbols found by DynamicLibrary.process(),
// and UCI lines coming back over a NativeCallable.listener from a goroutine on
// a thread Dart knows nothing about.
//
// It matters for the same reason the macOS one does: every failure path in
// RetroEngine returns null and the bot falls back to Stockfish, so a broken
// archive still plays — as somebody else. Only watching real moves come back
// proves it.
//
//   cd flutter && ./stage-ios-engines.sh     # build the xcframework once
//   (cd ios && pod install)                  # first staging only
//   flutter test integration_test/retro_ios_test.dart -d <simulator-id>

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/engine/retro_engine.dart';

/// Every legal move from the initial position, in UCI.
const _opening = {
  'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4', 'd2d3', 'd2d4', //
  'e2e3', 'e2e4', 'f2f3', 'f2f4', 'g2g3', 'g2g4', 'h2h3', 'h2h4',
  'b1a3', 'b1c3', 'g1f3', 'g1h3',
};

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Mate in one for white, and the ONLY one — verified with chess.js rather
/// than described from the board, which is how the first version of this got
/// it wrong (Qb7 leaves f8 and h8; Qb8 covers the whole rank). An engine that
/// is really searching finds it at any ply, which is a sharper check than
/// "returned something legal".
const _mateInOne = '6k1/5ppp/8/8/8/8/8/1Q4K1 w - - 0 1';
const _theMate = 'b1b8';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the archive is linked and its symbols survived dead-stripping', () {
    // The failure this catches is specific: a static archive nothing in
    // Objective-C references is stripped, and the app then reports itself as
    // "retro not supported" while containing the entire engine.
    expect(RetroEngine.supported, isTrue);
  });

  for (final engine in ['turochamp', 'bernstein', 'sargon']) {
    test('$engine answers from the initial position', () async {
      final e = RetroEngine(engine, engine == 'bernstein' ? 4 : 2);
      try {
        expect(_opening, contains(await e.move(_start, movetimeMs: 1000)));
      } finally {
        e.dispose();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  }

  test('turochamp finds mate in one', () async {
    final e = RetroEngine('turochamp', 2);
    try {
      expect(await e.move(_mateInOne, movetimeMs: 1000), _theMate);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('two engines run at once without crossing wires', () async {
    // Each session has its own handle and its own NativeCallable; the archive
    // routes lines by handle. Getting that wrong would show up as one engine
    // answering for the other, or as a line delivered to a freed callback.
    final a = RetroEngine('turochamp', 2);
    final b = RetroEngine('sargon', 1);
    try {
      final moves = await Future.wait([
        a.move(_mateInOne, movetimeMs: 1000),
        b.move(_start, movetimeMs: 1000),
      ]);
      expect(moves[0], _theMate);
      expect(_opening, contains(moves[1]));
    } finally {
      a.dispose();
      b.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a disposed engine answers null rather than hanging', () async {
    final e = RetroEngine('turochamp', 2);
    e.dispose();
    expect(await e.move(_start), isNull);
  });

  test('disposing DURING a search does not take the app down', () async {
    // This is the one that was crashing. Ending the session by closing the
    // engine's input made morlock return through its "input stream broken"
    // branch, which closes the output channel without clearing the
    // active-search flag — so the search still finishing sent its bestmove on
    // a closed channel and panicked. In a Worker or a child process that is an
    // invisible engine death; in a c-archive it is SIGABRT in this process.
    //
    // Reachable by tapping a different bot while a retro bot is thinking. The
    // test therefore does exactly that, repeatedly and at several offsets into
    // the search, because the window is sub-millisecond at these plies.
    for (final delay in [0, 1, 5, 20]) {
      for (var i = 0; i < 3; i++) {
        final e = RetroEngine('turochamp', 2);
        unawaited(e.move(_start, movetimeMs: 2000));
        await Future<void>.delayed(Duration(milliseconds: delay));
        e.dispose();
      }
    }
    // Still here, and still able to play — a crash would have taken the test
    // process with it, and a wedged archive would answer null.
    final after = RetroEngine('turochamp', 2);
    try {
      expect(_opening, contains(await after.move(_start, movetimeMs: 500)));
    } finally {
      after.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('an unknown engine name is refused, not silently substituted', () async {
    // macOS answers null for a name it has no binary for. The archive holds
    // all three engines, so the equivalent here is the name check in
    // retro_start — without it, build()'s default clause plays TUROCHAMP under
    // whatever persona asked.
    final e = RetroEngine('nonesuch', 2);
    try {
      expect(await e.move(_start), isNull);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
