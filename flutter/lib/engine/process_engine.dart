// Desktop transport: a UCI engine running as a child process.
//
// The stockfish pub package is iOS/Android only (it embeds the engine via
// FFI), so on macOS/Linux/Windows we talk to a real engine binary over
// stdin/stdout instead. The UCI dialogue is identical — everything shared
// lives in uci_protocol.dart — so desktop and mobile cannot drift.
//
// Threads stays at 1, matching mobile: the shaped bots sample from the
// engine's lines, and letting desktop search wider would quietly make the
// same persona play stronger than its calibration.

import 'dart:convert';
import 'dart:io';

import 'uci_protocol.dart';

class ProcessEngine extends UciProtocol {
  final Process _proc;

  ProcessEngine._(this._proc) {
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine);
  }

  static Future<ProcessEngine> start() async {
    final path = resolveBinary();
    if (path == null) {
      throw StateError(
        'No UCI engine binary found. Install one (brew install stockfish), '
        'bundle it in the app Resources, or set BOTVINNIK_STOCKFISH to its path.',
      );
    }
    final proc = await Process.start(path, const []);
    final engine = ProcessEngine._(proc);
    engine.send('uci');
    engine.send('setoption name Threads value 1');
    engine.send('isready');
    return engine;
  }

  /// Where to find an engine, most-shippable first: bundled with the app,
  /// then an explicit override, then whatever is installed on this machine.
  /// Only the bundled case works under the macOS sandbox.
  static String? resolveBinary() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      // macOS: Contents/MacOS/<app> → Contents/Resources/stockfish
      '${exeDir.parent.path}/Resources/stockfish',
      // Linux/Windows: alongside the executable
      '${exeDir.path}/stockfish${Platform.isWindows ? '.exe' : ''}',
      if (Platform.environment['BOTVINNIK_STOCKFISH'] != null)
        Platform.environment['BOTVINNIK_STOCKFISH']!,
      '/opt/homebrew/bin/stockfish',
      '/usr/local/bin/stockfish',
      '/usr/bin/stockfish',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    return null;
  }

  @override
  void send(String command) => _proc.stdin.writeln(command);

  @override
  void dispose() {
    try {
      send('quit');
    } catch (_) {/* pipe already closed */}
    _proc.kill();
  }
}
