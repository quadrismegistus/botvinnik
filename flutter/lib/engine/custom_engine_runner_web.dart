// A player-added engine on the web: not runnable today, because a browser
// cannot spawn a binary. Phase 2 (issue #183) replaces this stub with a
// RemoteEngine that talks to a UCI service on the VPS over wss://; until then
// `supported` is false, so the roster never offers a custom engine on the web.

class CustomEngineRunner {
  static bool get supported => false;

  final String path;
  CustomEngineRunner(this.path);

  Future<String?> move(String fen, {int? elo, int movetimeMs = 1000}) async =>
      null;

  void dispose() {}
}
