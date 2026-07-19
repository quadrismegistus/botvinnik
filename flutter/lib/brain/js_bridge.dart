// Picks the JS host for the platform: an embedded runtime via flutter_js on
// native, and the browser's own engine on web. Both evaluate the SAME
// brain.js bundle and the same expression strings — see js_bridge_io.dart for
// what the bridge is and why calls are synchronous.
//
// The conditional export keeps dart:ffi (flutter_js) out of the web compile.
//
// UNVERIFIED BEYOND JAVASCRIPTCORE. The only native targets that exist today
// are ios/ and macos/, where flutter_js is JavaScriptCore; the runtime is
// QuickJS on Android, and nothing here has ever run there. That is not a
// footnote: brain.js contains BigInt literals (`0n`) — chess.js has always
// contributed some, via its Zobrist hashing, and bundling js-chess-engine for
// the Horizon personas added many more — and QuickJS gates BigInt behind
// CONFIG_BIGNUM. A build without it fails to PARSE the bundle, so
// JsBridge.load() would throw and the whole app would fail to boot, rather
// than merely lose a bot family. Predates M5; check before adding Android.
export 'js_bridge_io.dart' if (dart.library.js_interop) 'js_bridge_web.dart';
