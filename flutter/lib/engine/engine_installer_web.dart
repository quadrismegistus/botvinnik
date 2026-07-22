// No engine download on the web: a browser cannot save or run a binary. The
// Engines screen hides the download UI where `supported` is false; the throwing
// methods exist only so the two platforms share one type.

import '../stores/engine_catalog.dart';

class EngineInstaller {
  static bool get supported => false;
  static String? get platformKey => null;

  static Future<String> homeDir(String catalogId) async =>
      throw UnsupportedError('engine download is desktop only');

  static Future<String> installedPath(String catalogId,
          {bool ownDir = false}) async =>
      throw UnsupportedError('engine download is desktop only');

  static Future<String> install(
    String catalogId,
    EngineBuild build, {
    void Function(int received, int total)? onProgress,
    bool ownDir = false,
  }) async =>
      throw UnsupportedError('engine download is desktop only');

  static Future<void> writeStyleFiles(
          String catalogId, Map<String, List<int>> files) async =>
      throw UnsupportedError('engine download is desktop only');

  static Future<void> uninstall(String catalogId, {bool ownDir = false}) async {}
}
