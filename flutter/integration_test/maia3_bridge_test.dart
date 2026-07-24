// The Maia-3 brain surface through the REAL JsBridge (issue #221): the
// ladder property, encodeBoard's shape, and computeMoveCurves round-tripped
// with synthetic logits. This is the wire-gap guard — brain/maia3/ has its
// own vitest suite; what THIS catches is the marshalling (91k floats of
// JSON) and the Dart typing in Maia3Api.
//
//   cd flutter && flutter test integration_test/maia3_bridge_test.dart -d macos

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/maia3_api.dart';

const _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('maia3 brain surface marshals through the bridge',
      (tester) async {
    final bridge = await JsBridge.load();
    final api = Maia3Api(bridge);

    final ladder = api.eloLadder();
    expect(ladder.first, 600);
    expect(ladder.last, 2600);
    expect(ladder.length, 21);

    final encoded = bridge.call('encodeBoardArray', args: [_startFen]) as List;
    expect(encoded.length, 64 * 12);

    // Synthetic logits over the full ladder: uniform policy, one WDL vector
    // per rung. Checks the shape and the probability laws, not the model.
    final vocab = bridge.call('POLICY_VOCAB_SIZE', isProperty: true) as num;
    final raw = Maia3Raw(
      elos: ladder,
      policyByElo: [
        for (final _ in ladder) List.filled(vocab.toInt(), 0.0),
      ],
      wdlByElo: [
        for (final _ in ladder) [0.0, 1.0, 2.0], // L, D, W logits
      ],
    );
    final curves = api.computeMoveCurves(_startFen, raw);

    expect(curves.perElo.length, 21);
    for (final rung in curves.perElo) {
      // 20 legal moves from the start position, uniform under equal logits.
      expect(rung.moveProbabilities.length, 20);
      final sum =
          rung.moveProbabilities.values.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
      expect(rung.moveProbabilities['e4'], closeTo(0.05, 1e-9));
    }
    expect(curves.wdlByElo.length, 21);
    for (final rung in curves.wdlByElo) {
      // Softmax of [0,1,2] in L/D/W order: win is the largest.
      expect(rung.win + rung.draw + rung.loss, closeTo(1.0, 1e-9));
      expect(rung.win, greaterThan(rung.draw));
      expect(rung.draw, greaterThan(rung.loss));
      expect(rung.expectedScore, closeTo(rung.win + 0.5 * rung.draw, 1e-12));
    }

    bridge.dispose();
  });
}
