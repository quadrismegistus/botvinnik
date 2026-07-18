// The UCI dialogue itself: line parsing, and the option bookkeeping that
// decides how strong the engine actually is. A regression in the reset path
// is invisible in play — the bot just quietly plays at the wrong strength —
// so it is worth pinning even though no engine is involved here.
//
//   cd flutter && flutter test

import 'package:flutter_test/flutter_test.dart';

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
