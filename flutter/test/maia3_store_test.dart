// Maia3Store's lifecycle decisions (issue #221): what earns an inference,
// what answers from cache, and which reply is allowed to draw. The engine
// and brain are faked through the store's debug seams — the real transports
// have their own tests (maia3_bridge_test.dart, brain/maia3/maia3.test.ts).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/stores/maia3_store.dart';

const _ladder = [600, 1600, 2600];
const _fenA = 'A w - - 0 1';
const _fenB = 'B b - - 0 1';

Maia3Raw _raw(List<int> elos) => Maia3Raw(
      elos: elos,
      policyByElo: [for (final _ in elos) const [0.0]],
      wdlByElo: [for (final _ in elos) const [0.0, 0.0, 0.0]],
    );

Maia3MoveCurves _curvesFor(String fen) => Maia3MoveCurves(
      perElo: [
        for (final e in _ladder) Maia3RungCurve(e, {'e4': fen.length / 100})
      ],
      wdlByElo: const [],
    );

Maia3Store _store({
  required Future<Maia3Raw?> Function(String, List<int>) analyze,
}) {
  final store = Maia3Store.test();
  store.debugLadder = _ladder;
  store.debugDecode = (fen, _) => _curvesFor(fen);
  store.debugAnalyze = analyze;
  return store;
}

void main() {
  test('debounce coalesces browsing into one inference for the survivor', () {
    fakeAsync((async) {
      final analyzed = <String>[];
      final store = _store(analyze: (fen, elos) async {
        analyzed.add(fen);
        return _raw(elos);
      });

      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 100));
      store.setPosition(_fenB); // supersedes A inside the window
      expect(store.loading, isTrue);
      async.elapse(const Duration(milliseconds: 300));

      expect(analyzed, [_fenB]);
      expect(store.shownFen, _fenB);
      expect(store.curves, isNotNull);
      expect(store.loading, isFalse);
      store.dispose();
    });
  });

  test('revisited positions answer from cache without a second inference', () {
    fakeAsync((async) {
      var calls = 0;
      final store = _store(analyze: (fen, elos) async {
        calls++;
        return _raw(elos);
      });

      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 300));
      store.setPosition(_fenB);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 2);

      store.setPosition(_fenA); // back — cache, instant, no debounce
      expect(store.shownFen, _fenA);
      expect(store.loading, isFalse);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 2);
      store.dispose();
    });
  });

  test('a slow reply for a superseded position never draws', () {
    fakeAsync((async) {
      final store = _store(analyze: (fen, elos) async {
        if (fen == _fenA) {
          // A's inference outlives B's whole request
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        return _raw(elos);
      });

      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 300)); // A's run starts, slow
      store.setPosition(_fenB);
      async.elapse(const Duration(milliseconds: 300)); // B answers
      expect(store.shownFen, _fenB);
      async.elapse(const Duration(seconds: 10)); // A's reply finally lands
      expect(store.shownFen, _fenB, reason: 'stale reply must be dropped');
      store.dispose();
    });
  });

  test('failure sets the flag; asking again retries and clears it', () {
    fakeAsync((async) {
      var fail = true;
      final store = _store(analyze: (fen, elos) async {
        return fail ? null : _raw(elos);
      });

      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 300));
      expect(store.failed, isTrue);
      expect(store.curves, isNull);

      fail = false;
      store.setPosition(_fenB);
      expect(store.failed, isFalse, reason: 'a new request clears the flag');
      async.elapse(const Duration(milliseconds: 300));
      expect(store.shownFen, _fenB);
      expect(store.failed, isFalse);
      store.dispose();
    });
  });

  test('same position re-asked while shown is a no-op', () {
    fakeAsync((async) {
      var calls = 0;
      final store = _store(analyze: (fen, elos) async {
        calls++;
        return _raw(elos);
      });
      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 300));
      store.setPosition(_fenA);
      async.elapse(const Duration(milliseconds: 300));
      expect(calls, 1);
      store.dispose();
    });
  });
}
