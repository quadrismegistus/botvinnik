// Picks the JS host for the platform: an embedded runtime (JavaScriptCore /
// QuickJS via flutter_js) on native, and the browser's own engine on web.
// Both evaluate the SAME brain.js bundle and the same expression strings —
// see js_bridge_io.dart for what the bridge is and why calls are synchronous.
//
// The conditional export keeps dart:ffi (flutter_js) out of the web compile.
export 'js_bridge_io.dart' if (dart.library.js_interop) 'js_bridge_web.dart';
