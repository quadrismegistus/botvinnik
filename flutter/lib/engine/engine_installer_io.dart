// Download → verify → install a catalogued engine, on native desktop.
//
// The SHA-256 check is the whole safety story: we are fetching an executable
// and about to run it, so a download that does not match the pinned hash is
// deleted, not installed. On macOS the freshly-downloaded binary carries a
// `com.apple.quarantine` xattr that Gatekeeper uses to block it; we strip that,
// which is the one step between "it plays" and "it silently stands in".

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../stores/engine_catalog.dart';

class EngineInstaller {
  static bool get supported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// The catalog key for this machine, or null when it is one no catalog build
  /// targets. `Abi.current()` carries both OS and CPU arch, which is what
  /// separates an Apple-Silicon build from an Intel one.
  static String? get platformKey => switch (Abi.current()) {
        Abi.macosArm64 => 'macos-arm64',
        Abi.macosX64 => 'macos-x64',
        Abi.linuxX64 => 'linux-x64',
        Abi.linuxArm64 => 'linux-arm64',
        Abi.windowsX64 => 'windows-x64',
        _ => null,
      };

  static Future<Directory> _enginesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/engines');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Where a catalog engine's binary lives once installed.
  static Future<String> installedPath(String catalogId) async =>
      '${(await _enginesDir()).path}/$catalogId${Platform.isWindows ? '.exe' : ''}';

  /// Download [build], verify its SHA-256, install it executable, strip the
  /// macOS quarantine, and return the path. Throws on a non-200 response or a
  /// checksum mismatch — a corrupt or tampered binary is deleted, never left
  /// where a game could launch it.
  static Future<String> install(
    String catalogId,
    EngineBuild build, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dest = await installedPath(catalogId);
    final part = File('$dest.part');

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(build.url));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw StateError('download failed: HTTP ${resp.statusCode}');
      }
      final total =
          resp.contentLength >= 0 ? resp.contentLength : build.sizeBytes;
      final out = part.openWrite();
      var received = 0;
      onProgress?.call(0, total);
      await resp.forEach((chunk) {
        out.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      });
      await out.close();
    } finally {
      client.close();
    }

    final digest = sha256.convert(await part.readAsBytes()).toString();
    if (digest != build.sha256) {
      if (part.existsSync()) part.deleteSync();
      throw StateError(
          'checksum mismatch — refusing to install a binary that does not '
          'match the catalog (expected ${build.sha256}, got $digest)');
    }

    final destFile = File(dest);
    if (destFile.existsSync()) destFile.deleteSync();
    part.renameSync(dest);

    if (Platform.isMacOS || Platform.isLinux) {
      // Checked: a chmod that failed would leave a non-executable binary the
      // caller would then mark "Installed" while it silently stands in. Better
      // to fail the install and surface it.
      final chmod = await Process.run('chmod', ['+x', dest]);
      if (chmod.exitCode != 0) {
        throw StateError('could not make the engine executable: ${chmod.stderr}');
      }
    }
    if (Platform.isMacOS) {
      // Harmless if the attribute is absent; the point is that when it is
      // present, Gatekeeper would otherwise refuse to launch the engine. Not
      // checked for that reason.
      await Process.run('xattr', ['-d', 'com.apple.quarantine', dest]);
    }
    return dest;
  }

  /// Delete an installed binary. The store entry is removed separately.
  static Future<void> uninstall(String catalogId) async {
    final f = File(await installedPath(catalogId));
    if (f.existsSync()) f.deleteSync();
  }
}
