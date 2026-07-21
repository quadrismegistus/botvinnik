// What ExplorerApi actually sends across the bridge.
//
// Every widget test of the Book pane injects a fake ExplorerApi, so the real
// one is never instantiated and its argument list is asserted nowhere. Two
// mutations proved that: swapping `lichess`/`masters`, and swapping `fen` and
// `lines` — the latter hands `engine.forEach` a string and throws on every
// Book pane build — both left the whole suite green.
//
// `scripts/smoke-brain.mjs` covers the JS side of this call, but nothing
// covered the Dart side. This is the same shape as the marshalling pin in
// practice_motif_test.dart, which is what caught the equivalent mutation there.
//
//   cd flutter && flutter test test/explorer_api_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/explorer_api.dart';
import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/types.dart';

typedef _Call = ({String fn, List<Object?> args});

/// Records what crossed the bridge and answers with a canned reply. `implements`
/// rather than extends: the real JsBridge owns a runtime handle.
class _RecordingBridge implements JsBridge {
  _RecordingBridge(this.reply);
  final Object? reply;
  final List<_Call> calls = [];

  @override
  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    calls.add((fn: fn, args: args));
    return reply;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  test('unifyMoves sends fen, lines, lichess, masters — in that order', () {
    final bridge = _RecordingBridge(<dynamic>[]);
    const lines = [
      EngineMove(pv: ['e2e4'], score: 0.4, mate: null, depth: 18, multipv: 1),
    ];
    const book = {'total': 10, 'moves': <dynamic>[]};

    ExplorerApi(bridge)
        .unifyMoves(fen: _fen, lines: lines, lichess: book, masters: null);

    final call = bridge.calls.single;
    expect(call.fn, 'unifyMoves');
    expect(call.args, hasLength(4));
    // Positional and order-sensitive: the brain reads args[0] as a FEN string
    // and args[1] as the engine lines, so a swap type-errors at runtime while
    // every fake-backed test stays green.
    expect(call.args[0], _fen, reason: 'fen first');
    expect(jsonEncode(call.args[1]), jsonEncode([lines.first.toJson()]),
        reason: 'lines second, as JSON maps');
    expect(call.args[2], book, reason: 'lichess third');
    expect(call.args[3], isNull, reason: 'masters fourth');
  });

  test('position() sums the book node into the shape the brain wants', () {
    // The brain reads {total, moves}; BookStore stores {white, draws, black,
    // moves}. A wrong total silently reweights every share in the table.
    final p = ExplorerApi.position(
        {'white': 3, 'draws': 2, 'black': 5, 'moves': <dynamic>[]});
    expect(p['total'], 10);
    expect(p['moves'], isEmpty);
  });
}
