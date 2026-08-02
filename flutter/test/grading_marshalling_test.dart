// What crosses the brain↔Flutter boundary for engineCorrelation (#276).
//
// The widget tests stub `GradingApi` itself, so they prove the drawing and
// nothing about the marshalling: with them alone, `engineCorrelation` could
// return null unconditionally, swap its two numbers, or call a different brain
// function entirely, and the whole suite stayed green. This is the recurring
// brain/Flutter wire gap — the brain implements it, the widget draws it, and
// nothing checks what passes between them.
//
//   cd flutter && flutter test test/grading_marshalling_test.dart

import 'package:botvinnik_mobile/brain/grading_api.dart';
import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bridge that answers with whatever the test says, and records the call.
class _FakeBridge implements JsBridge {
  _FakeBridge(this._reply);
  final Object? _reply;

  String? fn;
  List<Object?>? args;

  @override
  Object? call(String fn, {List<Object?> args = const [], bool isProperty = false}) {
    this.fn = fn;
    this.args = args;
    return _reply;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final moves = [
    {'ply': 1, 'uci': 'e2e4', 'color': 'w'},
    {'ply': 2, 'uci': 'e7e5', 'color': 'b'},
  ];

  test('asks the brain for engineCorrelation, with the moves and the colour', () {
    final bridge = _FakeBridge({'played': 1, 'total': 2});
    GradingApi(bridge).engineCorrelation(moves, 'w');

    expect(bridge.fn, 'engineCorrelation',
        reason: 'a different brain function would answer plausibly and wrongly');
    expect(bridge.args, [moves, 'w']);
  });

  test('reads the two numbers in the right order', () {
    // swapping them is the mutation a "did it draw something" test cannot see
    final r = GradingApi(_FakeBridge({'played': 3, 'total': 40})).engineCorrelation(moves, 'w');
    expect(r, isNotNull);
    expect(r!.played, 3);
    expect(r.total, 40);
  });

  test('accepts the doubles a JSON bridge may hand back', () {
    final r = GradingApi(_FakeBridge({'played': 3.0, 'total': 40.0})).engineCorrelation(moves, 'w');
    expect(r, (played: 3, total: 40));
  });

  test('returns null when the brain says null', () {
    // the honest answer for a game nothing could be counted in
    expect(GradingApi(_FakeBridge(null)).engineCorrelation(moves, 'w'), isNull);
  });

  test('returns null rather than throwing on a shape it did not expect', () {
    // this call is made during a widget build: a throw here is a red screen
    for (final reply in <Object?>[
      'not a map',
      42,
      <String, Object?>{},
      {'played': 1},
      {'total': 2},
      {'played': 'one', 'total': 'two'},
      [1, 2],
    ]) {
      expect(GradingApi(_FakeBridge(reply)).engineCorrelation(moves, 'w'), isNull,
          reason: 'reply: $reply');
    }
  });
}
