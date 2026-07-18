// The shaping layer: bot.ts running verbatim in an embedded JS engine
// (JavaScriptCore on iOS/macOS via flutter_js). No Dart port — the exact
// code the web app ships picks the move here too, which is the whole
// point: behavioral parity by construction.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

class ShapingLayer {
  final JavascriptRuntime _js;

  ShapingLayer._(this._js);

  static Future<ShapingLayer> load() async {
    final js = getJavascriptRuntime();
    final src = await rootBundle.loadString('assets/bot.js');
    final result = js.evaluate(src);
    if (result.isError) {
      throw StateError('bot.js failed to evaluate: ${result.stringResult}');
    }
    return ShapingLayer._(js);
  }

  /// The calibrated search depth for a label (bot.ts shapedSearchDepth).
  int searchDepth(int label) {
    final r = _js.evaluate('botvinnik.shapedSearchDepth($label)');
    return int.parse(r.stringResult);
  }

  /// shapedBotMove over MultiPV lines — returns the UCI move or null.
  /// [lines] entries: {pv: [uci...], score: double, mate: int?, depth: int,
  /// multipv: int} — the same EngineMove shape the web app uses.
  String? pickMove({
    required List<Map<String, dynamic>> lines,
    required int label,
    required String seed,
    required String fen,
    String? lastMoveTo,
  }) {
    final call = 'JSON.stringify(botvinnik.shapedBotMove('
        '${jsonEncode(lines)}, $label, {scan: true}, ${jsonEncode(seed)}, '
        '${jsonEncode(fen)}, undefined, ${jsonEncode(lastMoveTo)}))';
    final r = _js.evaluate(call);
    if (r.isError) {
      throw StateError('shapedBotMove failed: ${r.stringResult}');
    }
    final decoded = jsonDecode(r.stringResult);
    return decoded as String?;
  }

  void dispose() => _js.dispose();
}
