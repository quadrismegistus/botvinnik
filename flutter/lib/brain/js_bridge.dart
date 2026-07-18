// The one owner of the embedded JS runtime (JavaScriptCore on iOS/macOS via
// flutter_js) and the brain.js bundle — the web app's pure-TS layer running
// verbatim. All calls marshal through JSON; facades (bot_api, grading_api,
// chess_api) wrap this with types. Calls are synchronous and ms-scale; engine
// searches are the slow part and live elsewhere (engine/arbiter.dart).

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

/// Bump in lockstep with BRAIN_VERSION in src/lib/brain-entry.ts.
/// Boot fails loudly on mismatch instead of skewing silently.
const int kExpectedBrainVersion = 1;

class JsBridge {
  final JavascriptRuntime _js;

  JsBridge._(this._js);

  static Future<JsBridge> load() async {
    final js = getJavascriptRuntime();
    final src = await rootBundle.loadString('assets/brain.js');
    final result = js.evaluate(src);
    if (result.isError) {
      throw StateError('brain.js failed to evaluate: ${result.stringResult}');
    }
    final bridge = JsBridge._(js);
    final version = bridge.call('BRAIN_VERSION', isProperty: true);
    if (version != kExpectedBrainVersion) {
      throw StateError(
          'brain.js version $version, app expects $kExpectedBrainVersion — '
          'run `npm run build:brain` and rebuild');
    }
    return bridge;
  }

  /// Calls `brain.fn(...args)` (or reads `brain.fn` when [isProperty]) and
  /// returns the JSON-decoded result. Args must be json-encodable; Dart null
  /// becomes JS null (the brain treats null and undefined alike).
  dynamic call(String fn, {List<Object?> args = const [], bool isProperty = false}) {
    final expr = isProperty
        ? 'JSON.stringify(brain.$fn)'
        : 'JSON.stringify(brain.$fn(${args.map(jsonEncode).join(',')}) ?? null)';
    final r = _js.evaluate(expr);
    if (r.isError) {
      throw StateError('brain.$fn failed: ${r.stringResult}');
    }
    final s = r.stringResult;
    // JSON.stringify(undefined) yields the string "undefined"
    if (s == 'undefined' || s == 'null') return null;
    return jsonDecode(s);
  }

  void dispose() => _js.dispose();
}
