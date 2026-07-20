// Garbo through the REAL native path: garbochess.js loaded into a
// JavaScriptCore on a background isolate.
//
// A unit test cannot reach it — the engine is an asset, the runtime is FFI,
// and the whole point is that it runs somewhere other than here. And the
// failure mode is silent: every path in GarboEngine returns null and the bot
// falls back to Stockfish, so a broken Garbo still plays, as somebody else.
//
//   cd flutter && flutter test integration_test/garbo_native_test.dart -d macos
//   flutter test integration_test/garbo_native_test.dart -d <simulator-id>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/engine/garbo_engine.dart';

/// Every legal move from the initial position, in UCI.
const _opening = {
  'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4', 'd2d3', 'd2d4', //
  'e2e3', 'e2e4', 'f2f3', 'f2f4', 'g2g3', 'g2g4', 'h2h3', 'h2h4',
  'b1a3', 'b1c3', 'g1f3', 'g1h3',
};

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Mate in one for white, and the only one — chess.js agrees, which is how
/// this is known rather than read off the board.
const _mateInOne = '6k1/5ppp/8/8/8/8/8/1Q4K1 w - - 0 1';
const _theMate = 'b1b8';

/// Black to move, and the white queen on e1 is undefended (the king on g1 does
/// not reach it). Rxe1+ wins a queen for nothing, so any depth finds it. This
/// pins the side-to-move handling, which is what a FEN-parsing bug gets wrong
/// quietly — and the position is checked with chess.js rather than eyeballed,
/// which is how the first draft of it turned out to be illegal.
const _blackTakesQueen = '4k3/8/8/8/8/8/4r3/4Q1K1 b - - 0 1';
const _theCapture = 'e2e1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('is offered on this platform', () {
    expect(GarboEngine.supported, isTrue);
  });

  test('answers from the initial position', () async {
    final e = GarboEngine();
    try {
      expect(_opening, contains(await e.move(_start, movetimeMs: 500)));
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('finds mate in one', () async {
    final e = GarboEngine();
    try {
      expect(await e.move(_mateInOne, movetimeMs: 500), _theMate);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('plays the black side of a position', () async {
    final e = GarboEngine();
    try {
      expect(await e.move(_blackTakesQueen, movetimeMs: 500), _theCapture);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('the isolate is reused across moves', () async {
    // The engine is 82KB of JavaScript to parse and a JSC context to build;
    // doing that per move would be visible. Three searches on one instance
    // also prove ResetGame between positions actually resets — a leaked board
    // would show up as a move that is illegal in the new position.
    final e = GarboEngine();
    try {
      expect(_opening, contains(await e.move(_start, movetimeMs: 300)));
      expect(await e.move(_mateInOne, movetimeMs: 300), _theMate);
      expect(await e.move(_blackTakesQueen, movetimeMs: 300), _theCapture);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('a search does not block the main isolate', () async {
    // The whole reason this runs off the UI isolate. A 1500ms search that ran
    // here would starve the timer below completely; running elsewhere, the
    // ticks keep coming. Ten in 1.5s is a low bar deliberately — the assertion
    // is "the main isolate stayed alive", not a frame-rate measurement.
    final e = GarboEngine();
    var ticks = 0;
    final timer =
        Stream.periodic(const Duration(milliseconds: 50)).listen((_) => ticks++);
    try {
      await e.move(_start, movetimeMs: 1500);
      expect(ticks, greaterThan(10));
    } finally {
      await timer.cancel();
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('a disposed engine answers null rather than hanging', () async {
    final e = GarboEngine();
    e.dispose();
    expect(await e.move(_start), isNull);
  });

  test('a disposed engine gives its JavaScriptCore back', () async {
    // Isolate.kill reclaims the Dart heap and nothing else: the JSC context
    // group is native memory that only JavascriptRuntime.dispose() releases,
    // and garbochess allocates a 4M-slot hash table inside it. Killing rather
    // than asking measured ~167MB per disposed engine, monotone — which is
    // jetsam territory on a phone after a few bot changes.
    //
    // RSS is a blunt instrument, deliberately: the signal here is ~800MB
    // against a few tens, so the threshold does not have to be delicate to
    // separate the two.
    final before = ProcessInfo.currentRss;
    for (var i = 0; i < 5; i++) {
      final e = GarboEngine();
      await e.move(_start, movetimeMs: 200);
      e.dispose();
      // the child takes its shutdown after the search returns, so give it a
      // moment to actually run js.dispose() before measuring
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final grew = (ProcessInfo.currentRss - before) / (1024 * 1024);
    expect(grew, lessThan(250),
        reason: 'five create/dispose cycles grew RSS by ${grew.round()}MB; '
            'leaking the JSC context costs ~167MB each');
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('an illegal FEN answers null rather than throwing', () async {
    final e = GarboEngine();
    try {
      expect(await e.move('not a fen at all', movetimeMs: 300), isNull);
    } finally {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
