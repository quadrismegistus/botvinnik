// The Web Worker interop, in one place.
//
// Three engines now reach for a Worker on the web — Stockfish
// (web_engine.dart), the retro engines (retro_engine_web.dart) and Garbochess
// (garbo_engine_web.dart) — and each had declared its own private copy of
// these extension types. They are pure JS bindings with nothing to disagree
// about, so three copies could only ever drift, never differ usefully.
//
// Web-only: import it from a *_web.dart file, never from anything the native
// build compiles.

import 'dart:js_interop';

@JS('Worker')
extension type JsWorker._(JSObject _) implements JSObject {
  external factory JsWorker(String scriptUrl);
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction? handler);
  external set onerror(JSFunction? handler);
  external void terminate();
}

extension type WorkerMessage._(JSObject _) implements JSObject {
  external JSAny? get data;
}

/// A worker's error event carries the actual failure — a 404 for the script,
/// or a thrown exception. Without reading `message` every failure reports as
/// the same useless string.
extension type WorkerError._(JSObject _) implements JSObject {
  external String? get message;
}
