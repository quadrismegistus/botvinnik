// Native ORT NaN regression (issue #221 live-inference bug): the app threw
// "Converting object to an encodable object failed: NaN" — jsonEncode choking
// on NaN in the raw logits the native FFI engine returned. Root cause: on
// this native ORT build the SECOND run on a reused session returns all-NaN
// logits for the Maia-3 model, with byte-identical inputs (wasm is fine,
// Maia-1's convnet is fine; arena flags and graph-optimization levels change
// nothing). Fix: Maia3Engine builds a single-use session per inference.
//
// Test 1 is the regression: repeated engine.analyze calls all finite.
// Test 2 is a CANARY on the underlying ORT bug: it asserts the reused raw
// session still NaNs. If the canary ever FAILS, the vendored ORT was fixed —
// revert the single-use-session workaround and reclaim ~330ms per inference.
//
//   cd flutter && flutter test integration_test/maia3_nan_probe_test.dart -d macos

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'package:botvinnik_mobile/brain/js_bridge.dart';
import 'package:botvinnik_mobile/brain/maia3_api.dart';
import 'package:botvinnik_mobile/engine/maia3_engine_io.dart';

// The live-failure positions (a d4/Nc3/Bg5 game) plus the one that worked.
const _cases = <MapEntry<String, String>>[
  MapEntry('white-to-move',
      'rnbqkb1r/ppp1pppp/5n2/3p4/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 2 3'),
  MapEntry('black-to-move after Bg5',
      'rnbqkb1r/ppp1pppp/5n2/3p2B1/3P4/2N5/PPP1PPPP/R2QKBNR b KQkq - 3 3'),
  MapEntry('black-to-move after dxe5',
      'rnbqkb1r/ppp2ppp/5n2/3pP1B1/8/2N5/PPP1PPPP/R2QKBNR b KQkq - 0 4'),
];

int _nanCount(Maia3Raw raw) {
  var n = 0;
  for (final rung in raw.policyByElo) {
    n += rung.where((v) => v.isNaN).length;
  }
  for (final rung in raw.wdlByElo) {
    n += rung.where((v) => v.isNaN).length;
  }
  return n;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final ladder = [for (var e = 600; e <= 2600; e += 100) e];

  testWidgets('repeated analyze calls on one engine stay finite',
      (tester) async {
    final bridge = await JsBridge.load();
    final engine = Maia3Engine(bridge);
    for (final entry in _cases) {
      final raw = await engine.analyze(entry.value, ladder);
      expect(raw, isNotNull, reason: '${entry.key}: analyze returned null');
      expect(_nanCount(raw!), 0, reason: '${entry.key}: NaN in logits');
    }
    engine.dispose();
    bridge.dispose();
  });

  testWidgets('CANARY: a reused raw native session still NaNs on run #2',
      (tester) async {
    final bridge = await JsBridge.load();
    // The engine test above has downloaded/cached the model.
    final dir = await getApplicationSupportDirectory();
    final bytes = await File('${dir.path}/maia3/maia3.onnx').readAsBytes();
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1);
    final session = OrtSession.fromBuffer(bytes, options);
    options.release();

    final encoded = (bridge.call('encodeBoardArray', args: [_cases.first.value])
            as List)
        .cast<num>();
    int runOnce() {
      final batch = ladder.length;
      final tokens = Float32List(batch * 768);
      for (var b = 0; b < batch; b++) {
        for (var i = 0; i < 768; i++) {
          tokens[b * 768 + i] = encoded[i].toDouble();
        }
      }
      final elos =
          Float32List.fromList([for (final e in ladder) e.toDouble()]);
      final tokensT =
          OrtValueTensor.createTensorWithDataList(tokens, [batch, 64, 12]);
      final selfT = OrtValueTensor.createTensorWithDataList(elos, [batch]);
      final oppoT = OrtValueTensor.createTensorWithDataList(
          Float32List.fromList(elos), [batch]);
      final ro = OrtRunOptions();
      final outs = session.run(
        ro,
        {'tokens': tokensT, 'elo_self': selfT, 'elo_oppo': oppoT},
        ['logits_move', 'logits_value'],
      );
      var nan = 0;
      void scan(Object? v) {
        if (v is num) {
          if (v.toDouble().isNaN) nan++;
        } else if (v is List) {
          for (final x in v) {
            scan(x);
          }
        }
      }

      for (final o in outs) {
        scan(o?.value);
        o?.release();
      }
      tokensT.release();
      selfT.release();
      oppoT.release();
      ro.release();
      return nan;
    }

    expect(runOnce(), 0, reason: 'first run must be clean');
    expect(runOnce(), greaterThan(0),
        reason: 'ORT bug fixed? Revert the single-use-session workaround '
            'in maia3_engine_io.dart and reclaim the rebuild cost.');
    session.release();
    bridge.dispose();
  });
}
