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

import 'package:flutter/foundation.dart';

import 'uci_protocol.dart';

class ProcessEngine extends UciProtocol {
  final Process _proc;

  bool _alive = true;

  ProcessEngine._(this._proc) {
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleLine, onError: _died, onDone: () {
      if (_alive) _died('engine stdout closed');
    });
    // stderr must be drained: a full pipe (~64KB) blocks the child mid-search,
    // and engine startup complaints are otherwise invisible
    _proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) => debugPrint('[engine] $l'), onError: (_) {});
    _proc.exitCode.then((code) => _died('engine exited ($code)'));
    // writes fail asynchronously; without this a write to a dead engine
    // surfaces as an unhandled zone error
    _proc.stdin.done.catchError((Object _) => _proc.stdin);
  }

  /// The engine is gone. Fail the search in flight so the arbiter recovers
  /// instead of waiting on a bestmove that will never arrive.
  void _died(Object reason) {
    if (!_alive) return;
    _alive = false;
    failSearch(StateError('$reason'));
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
      // Beside the executable — Contents/MacOS on macOS, the app directory on
      // Linux/Windows. First because that is where a NOTARIZABLE macOS bundle
      // keeps it: executable code in Contents/Resources is a rejection, since
      // the hardened runtime treats Resources as data.
      '${exeDir.path}/stockfish${Platform.isWindows ? '.exe' : ''}',
      // Where the bundle used to put it. Kept so a stale build still runs.
      '${exeDir.parent.path}/Resources/stockfish',
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
  void send(String command) {
    if (!_alive) return; // a dead engine's search has already been failed
    _proc.stdin.writeln(command);
  }

  @override
  void dispose() {
    send('quit'); // no-op once _alive is false
    _alive = false;
    _proc.kill();
  }
}
