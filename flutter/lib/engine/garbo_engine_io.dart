// Garbochess on native: not yet. [GarboEngine.supported] is false, so the
// roster picker does not offer the Garbo persona here.
//
// This one is harder than retro's native gap, not easier, despite Garbo being
// plain JavaScript rather than compiled Go. Two problems, both in flutter_js:
//
//   * **No Worker.** garbochess.js is written as a worker — it assigns
//     `self.onmessage` and calls `postMessage`. Running it under flutter_js
//     needs a shim providing both, which is small but has to be exactly right
//     about message ordering.
//   * **It would block the UI.** The brain bridge is synchronous and runs on
//     the UI isolate. Garbo searches for ~1s per move, which is a frozen app
//     for ~1s. So it also needs a background isolate with its own JS runtime,
//     which nothing else in the app currently needs.
//
// Neither is exotic, but together they are more work than the whole web
// implementation was, for one persona. Deferred deliberately.

class GarboEngine {
  static bool get supported => false;

  Future<String?> move(String fen, {int movetimeMs = 1000}) async => null;

  void dispose() {}
}
