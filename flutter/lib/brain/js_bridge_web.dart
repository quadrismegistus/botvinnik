// Web bridge: the browser IS the JS runtime, so there is no embedded engine
// to marshal through — brain.js is loaded by a <script> tag in web/index.html
// and hangs off globalThis as `brain`, exactly as the IIFE bundle intends.
//
// The expression strings are identical to js_bridge_io.dart's, so both hosts
// exercise the same brain surface and the golden fixtures mean the same thing
// on either. Kept in lockstep by hand: there is no shared base, because the
// native side cannot import dart:js_interop at all.

import 'dart:convert';
import 'dart:js_interop';

const int kExpectedBrainVersion = 1;

@JS('eval')
external JSAny? _jsEval(String code);

class JsBridge {
  JsBridge._();

  static Future<JsBridge> load() async {
    // index.html loads brain.js before main.dart.js, so it is already here
    final probe = _jsEval('typeof brain');
    if ((probe?.dartify() as String?) != 'object') {
      throw StateError(
          'brain.js is not loaded — web/index.html must script-tag it before '
          'main.dart.js (and web/brain.js must be a copy of assets/brain.js)');
    }
    final bridge = JsBridge._();
    final version = bridge.call('BRAIN_VERSION', isProperty: true);
    if (version != kExpectedBrainVersion) {
      throw StateError(
          'brain.js version $version, app expects $kExpectedBrainVersion — '
          'run `npm run build:brain` and refresh');
    }
    return bridge;
  }

  static const Object omit = _Omit();

  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final encoded = args
        .map((a) => identical(a, omit) ? 'undefined' : jsonEncode(a))
        .join(',');
    final expr = isProperty
        ? 'JSON.stringify(brain.$fn)'
        : 'JSON.stringify(brain.$fn($encoded) ?? null)';
    final s = _jsEval(expr)?.dartify() as String?;
    if (s == null || s == 'undefined' || s == 'null') return null;
    return jsonDecode(s);
  }
}

class _Omit {
  const _Omit();
}
