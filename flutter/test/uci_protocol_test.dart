// The UCI dialogue itself: line parsing, and the option bookkeeping that
// decides how strong the engine actually is. A regression in the reset path
// is invisible in play — the bot just quietly plays at the wrong strength —
// so it is worth pinning even though no engine is involved here.
//
//   cd flutter && flutter test

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/types.dart' show EngineMove;
import 'package:botvinnik_mobile/engine/uci_protocol.dart';

/// A transport that records commands instead of writing to an engine.
class RecordingProtocol extends UciProtocol {
  final List<String> sent = [];
  @override
  void send(String command) => sent.add(command);
  @override
  void dispose() {}

  List<String> get options => sent.where((c) => c.startsWith('setoption')).toList();
  void clear() => sent.clear();
}

void main() {
  late RecordingProtocol uci;
  setUp(() => uci = RecordingProtocol());

  test('parses multipv lines, sorts them, resolves on bestmove', () async {
    final result = uci.search('fen', go: 'depth 12', multiPv: 2);
    uci.handleLine('info depth 12 multipv 2 score cp -35 pv d2d4 d7d5');
    uci.handleLine('info depth 12 multipv 1 score cp 41 pv e2e4 e7e5');
    uci.handleLine('bestmove e2e4');

    final lines = await result;
    expect(lines.map((l) => l.multipv), [1, 2]); // sorted, not arrival order
    expect(lines.first.pv, ['e2e4', 'e7e5']);
    expect(lines.first.score, closeTo(0.41, 1e-9));
    expect(lines[1].score, closeTo(-0.35, 1e-9));
    expect(lines.first.depth, 12);
  });

  // Everything downstream that SUBTRACTS two of these lines — refuse-blunders
  // reads the best move off line 1 and the played move off line 2..N — is
  // comparing two different searches unless a snapshot holds one iteration.
  group('streamed snapshots hold ONE iteration', () {
    test('does not stream until the last multipv line of a depth', () async {
      final snaps = <List<EngineMove>>[];
      final result =
          uci.search('fen', go: 'depth 3', multiPv: 3, onUpdate: snaps.add);

      // iteration 1 streams as each line lands: with nothing else in the map
      // yet, a one-line snapshot is uniform trivially
      uci.handleLine('info depth 1 multipv 1 score cp 10 pv e2e4');
      uci.handleLine('info depth 1 multipv 2 score cp 5 pv d2d4');
      uci.handleLine('info depth 1 multipv 3 score cp 0 pv g1f3');
      snaps.clear();

      uci.handleLine('info depth 2 multipv 1 score cp 300 pv e2e4');
      expect(snaps, isEmpty,
          reason: 'line 1 of a new depth is the START of an iteration');
      uci.handleLine('info depth 2 multipv 2 score cp 20 pv d2d4');
      expect(snaps, isEmpty);
      uci.handleLine('info depth 2 multipv 3 score cp 10 pv g1f3');
      expect(snaps, hasLength(1), reason: 'the last line completes it');
      expect(snaps.single.map((l) => l.depth), [2, 2, 2],
          reason: 'no line left behind at the previous depth');
      expect(snaps.single.map((l) => l.score), [3.0, 0.2, 0.1]);

      uci.handleLine('bestmove e2e4');
      await result;
    });

    test('and streams at the real ceiling when the position has fewer moves',
        () async {
      // MultiPV 5 asked for, three legal moves available: waiting for a line 5
      // that never arrives would mean never streaming at all.
      final snaps = <List<EngineMove>>[];
      final result =
          uci.search('fen', go: 'depth 3', multiPv: 5, onUpdate: snaps.add);
      for (final d in [1, 2, 3]) {
        for (final mpv in [1, 2, 3]) {
          uci.handleLine('info depth $d multipv $mpv score cp $mpv pv e2e4');
        }
      }
      // One per iteration. The first is a single line — iteration 1's line 1
      // arrives with nothing else in the map yet, which is uniform trivially
      // and far below every consumer's depth floor.
      expect(snaps, hasLength(3), reason: 'one per iteration, not none');
      expect(snaps.map((s) => s.length), [1, 3, 3]);
      expect(snaps.last.map((l) => l.depth), [3, 3, 3]);

      uci.handleLine('bestmove e2e4');
      await result;
    });

    test('and RESOLVES with one iteration too, not the half-finished map',
        () async {
      // The other door into the same bug. Streaming was fixed; the value the
      // search resolves with was not, and that is the half a settled analysis
      // hands to grading. A search stopped mid-iteration — the ordinary end
      // for one, on the movetime backstop — leaves line 1 an iteration ahead
      // of the rest, with a score never compared against them.
      final result =
          uci.search('fen', go: 'depth 22', multiPv: 3, onUpdate: (_) {});
      for (final d in [1, 2, 3]) {
        for (final mpv in [1, 2, 3]) {
          uci.handleLine('info depth $d multipv $mpv score cp $mpv pv e2e4');
        }
      }
      // iteration 4 is cut off after its first line, which is the one that
      // moved: +9.00 against alternatives last seen at +0.02
      uci.handleLine('info depth 4 multipv 1 score cp 900 pv e2e4');
      uci.handleLine('bestmove e2e4');

      final lines = await result;
      expect(lines.map((l) => l.depth), [3, 3, 3],
          reason: 'the last COMPLETE iteration, not [4, 3, 3]');
      expect(lines.first.score, closeTo(0.01, 1e-9),
          reason: 'and its own line 1, not the orphaned +9.00');
    });

    test('but never trades away candidates to get there', () async {
      // Stopped before any full iteration: the only coherent thing on hand is
      // the one-line snapshot from before the ceiling was known, and the map
      // holds two. A bot searching MultiPV 12 that got back a single line
      // would play its top move deterministically, which is a worse failure
      // than the mixed depths — and the mixed list is refused anyway by the
      // one caller that subtracts these numbers.
      final result =
          uci.search('fen', go: 'depth 22', multiPv: 3, onUpdate: (_) {});
      uci.handleLine('info depth 5 multipv 1 score cp 20 pv e2e4');
      uci.handleLine('info depth 5 multipv 2 score cp 10 pv d2d4');
      uci.handleLine('info depth 6 multipv 1 score cp 25 pv e2e4');
      uci.handleLine('bestmove e2e4');

      final lines = await result;
      expect(lines, hasLength(2), reason: 'both candidates survive');
      expect(lines.first.depth, 6);
    });

    test('a skipped depth is streamed, not treated as an anomaly', () async {
      // Engines do not always advance depth by exactly one. An earlier
      // version of this gate had an escape hatch that fired on `depth >=
      // last + 2` — on the FIRST line of the new depth — so a plain skip
      // produced `[6, 4, 4]`: the mixed snapshot this whole group exists to
      // prevent, emitted by the code meant to prevent it.
      final snaps = <List<EngineMove>>[];
      final result =
          uci.search('fen', go: 'depth 9', multiPv: 3, onUpdate: snaps.add);
      for (final mpv in [1, 2, 3]) {
        uci.handleLine('info depth 4 multipv $mpv score cp $mpv pv e2e4');
      }
      snaps.clear();
      uci.handleLine('info depth 6 multipv 1 score cp 900 pv e2e4');
      expect(snaps, isEmpty, reason: 'that is the first line of depth 6');
      uci.handleLine('info depth 6 multipv 2 score cp 2 pv d2d4');
      uci.handleLine('info depth 6 multipv 3 score cp 3 pv g1f3');
      expect(snaps.single.map((l) => l.depth), [6, 6, 6]);

      uci.handleLine('bestmove e2e4');
      await result;
    });

    test('a ceiling that DROPS stalls the stream — coherently', () async {
      // The accepted limitation, pinned so it is a decision rather than a
      // surprise. An engine that reports three lines and then permanently two
      // leaves the third entry stale, so the map never becomes uniform again
      // and this search streams nothing further. No engine in the catalogue
      // was shown to do this, and the failure is frozen-but-COHERENT:
      // consumers keep the last good snapshot, the depth floor ages it out,
      // and nothing downstream is handed two depths to subtract. The escape
      // hatch that used to cover this stayed live by emitting mixed
      // snapshots, which is the worse of the two failures.
      final snaps = <List<EngineMove>>[];
      final result =
          uci.search('fen', go: 'depth 9', multiPv: 3, onUpdate: snaps.add);
      for (final d in [1, 2]) {
        for (final mpv in [1, 2, 3]) {
          uci.handleLine('info depth $d multipv $mpv score cp $mpv pv e2e4');
        }
      }
      expect(snaps.last.map((l) => l.depth), [2, 2, 2],
          reason: 'precondition: streaming normally up to here');
      snaps.clear();
      for (final d in [3, 4, 5, 6]) {
        for (final mpv in [1, 2]) {
          uci.handleLine('info depth $d multipv $mpv score cp $mpv pv e2e4');
        }
      }
      expect(snaps, isEmpty, reason: 'stalls rather than emitting a mixed one');

      uci.handleLine('bestmove e2e4');
      final resolved = await result;
      expect(resolved.map((l) => l.depth), [2, 2, 2],
          reason: 'and the resolution stays comparable, which is the point');
    });

    test('nothing carries from one search into the next', () async {
      // One UciProtocol serves every priority on one engine: analysis at
      // MultiPV 5, bot moves at 12, the refusal check at 1. Two searches on
      // ONE instance is the only way to see per-search state that failed to
      // reset; every other test here gets a fresh protocol from setUp.
      //
      // (This was called "the ceiling is per SEARCH" while the gate learned a
      // multipv ceiling. That design is gone — the gate now tests the
      // invariant directly — and the name outlived it by one commit.)
      final first =
          uci.search('fen', go: 'depth 2', multiPv: 3, onUpdate: (_) {});
      for (final mpv in [1, 2, 3]) {
        uci.handleLine('info depth 1 multipv $mpv score cp $mpv pv e2e4');
      }
      uci.handleLine('bestmove e2e4');
      await first;

      final snaps = <List<EngineMove>>[];
      final second =
          uci.search('fen2', go: 'depth 3', multiPv: 1, onUpdate: snaps.add);
      uci.handleLine('info depth 1 multipv 1 score cp 10 pv d2d4');
      uci.handleLine('info depth 2 multipv 1 score cp 12 pv d2d4');
      expect(snaps.map((s) => s.single.depth), [1, 2],
          reason: 'the narrower search streams on its own terms');

      uci.handleLine('bestmove d2d4');
      await second;

      // And the resolved lines are this search's. A search whose info lines
      // carry no `depth` token at all parses as depth 0, so nothing streams
      // and _lastStreamedLines is never assigned — if it still held the
      // PREVIOUS search's lines, this would resolve with a completely
      // different position's moves.
      final third = uci.search('fen3', go: 'depth 3', multiPv: 3);
      uci.handleLine('info multipv 1 score cp 5 pv h2h4');
      uci.handleLine('info multipv 2 score cp 4 pv h2h3');
      uci.handleLine('bestmove h2h4');
      expect((await third).map((l) => l.pv.first), ['h2h4', 'h2h3']);
    });

    test('a single-line search still streams every depth', () async {
      // MultiPV 1 is the refusal check's own shape, and the ceiling is 1, so
      // "wait for the last line" and "stream on the first" coincide.
      final snaps = <List<EngineMove>>[];
      final result =
          uci.search('fen', go: 'depth 2', multiPv: 1, onUpdate: snaps.add);
      uci.handleLine('info depth 1 multipv 1 score cp 10 pv e2e4');
      uci.handleLine('info depth 2 multipv 1 score cp 12 pv e2e4');
      expect(snaps.map((s) => s.single.depth), [1, 2]);

      uci.handleLine('bestmove e2e4');
      await result;
    });
  });

  test('a mate score survives as mate, not as a centipawn score', () async {
    final result = uci.search('fen', go: 'depth 12', multiPv: 1);
    uci.handleLine('info depth 20 multipv 1 score mate -3 pv h7h8 g1g2');
    uci.handleLine('bestmove h7h8');
    expect((await result).first.mate, -3);
  });

  test('weakening options are reset before an unweakened search', () async {
    uci.search('fen', go: 'depth 6', multiPv: 1,
        extraOptions: [['Skill Level', '3']]);
    uci.handleLine('bestmove e2e4');
    uci.clear();

    uci.search('fen2', go: 'depth 22', multiPv: 5);
    uci.handleLine('bestmove d2d4');
    expect(uci.options, contains('setoption name Skill Level value 20'));
  });

  test('switching weakening styles resets the one being dropped', () async {
    // UCI_Elo left enabled makes Skill Level inert in Stockfish: the skill
    // persona would silently play at the Elo persona's strength.
    uci.search('fen', go: 'depth 6', multiPv: 1, extraOptions: [
      ['UCI_LimitStrength', 'true'],
      ['UCI_Elo', '1600'],
    ]);
    uci.handleLine('bestmove e2e4');
    uci.clear();

    uci.search('fen2', go: 'depth 6', multiPv: 1,
        extraOptions: [['Skill Level', '3']]);
    uci.handleLine('bestmove d2d4');

    expect(uci.options, contains('setoption name UCI_LimitStrength value false'));
    expect(uci.options, contains('setoption name Skill Level value 3'));
  });

  test('MultiPV is only re-sent when it changes', () async {
    uci.search('fen', go: 'depth 22', multiPv: 5);
    uci.handleLine('bestmove e2e4');
    expect(uci.options, contains('setoption name MultiPV value 5'));
    uci.clear();

    uci.search('fen2', go: 'depth 22', multiPv: 5);
    uci.handleLine('bestmove d2d4');
    expect(uci.options, isEmpty);
  });

  test('engine death fails the search instead of hanging forever', () async {
    final result = uci.search('fen', go: 'depth 22', multiPv: 5);
    uci.failSearch(StateError('engine exited (139)'));
    await expectLater(result, throwsStateError);
    expect(uci.busy, isFalse); // and the transport is reusable
  });
}
