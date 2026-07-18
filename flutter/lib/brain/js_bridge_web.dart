// Web bridge: the browser IS the JS runtime, so there is no embedded engine
// to marshal through — brain.js is loaded by a <script> tag in web/index.html
// and hangs off globalThis as `brain`, exactly as the IIFE bundle intends.
//
// The two transports cannot share a base class — native cannot import
// dart:js_interop and web cannot import dart:ffi — but everything that would
// otherwise drift (the expression strings, the omit sentinel, the expected
// brain version) lives in js_bridge_shared.dart, so both hosts exercise the
// same brain surface and the golden fixtures mean the same thing on either.

import 'dart:js_interop';

import 'js_bridge_shared.dart';

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

  static const Object omit = kOmit;

  dynamic call(String fn,
      {List<Object?> args = const [], bool isProperty = false}) {
    final expr = buildBrainExpr(fn, args, isProperty);
    return decodeBrainResult(_jsEval(expr)?.dartify() as String?);
  }

  /// Nothing to tear down — the browser owns the JS context. Present so this
  /// class keeps the same surface as js_bridge_io's: nothing makes the twins
  /// agree, so a teardown call added later would compile on native, pass every
  /// test, and break only the web build.
  void dispose() {}
}

