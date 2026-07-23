import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'process_engine.dart';

// Keep engine subprocesses from outliving the app. dispose() handles a clean
// shutdown, but a force-quit, hot-restart, or crash never reaches it — and
// macOS has no "kill my children when I die", so an engine mid-search gets
// reparented to launchd (PPID 1) and spins forever. Two guards close that:
// exit hooks that kill on the way out, and a startup sweep that reaps whatever
// a previous run still leaked. Desktop only; the web build gets the no-op stub.

bool _guardsInstalled = false;

/// Kill the app's engines on the way out: on a signal (Ctrl-C / `kill` under
/// `flutter run`) and on the graceful app-detach (Cmd-Q). Idempotent.
void installEngineExitGuards() {
  if (_guardsInstalled) return;
  _guardsInstalled = true;

  // POSIX signals — not on Windows, which has no SIGTERM.
  if (Platform.isMacOS || Platform.isLinux) {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signal.watch().listen((_) {
        ProcessEngine.killAll();
        exit(0);
      });
    }
  }
  WidgetsBinding.instance.addObserver(_ReaperObserver());
}

class _ReaperObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) ProcessEngine.killAll();
  }
}

/// Reap engine binaries a previous run left orphaned — best-effort, at startup.
Future<void> reapOrphanedEngines() async {
  if (!(Platform.isMacOS || Platform.isLinux)) return;
  try {
    final enginesDir =
        '${(await getApplicationSupportDirectory()).path}/engines';
    final ps = await Process.run('ps', ['-axo', 'pid=,ppid=,command=']);
    if (ps.exitCode != 0) return;
    for (final target in orphanEnginePids(ps.stdout as String, enginesDir, pid)) {
      Process.killPid(target, ProcessSignal.sigkill);
    }
  } catch (_) {
    // No `ps`, no permission, etc. — the exit guards still cover the rest.
  }
}

/// Pure: from `ps -axo pid=,ppid=,command=` output, the PIDs that are orphaned
/// engine processes safe to kill — parent gone (reparented to PID 1), running a
/// binary under [enginesDir], and not us. A live engine has the app as its
/// parent, so it never matches.
List<int> orphanEnginePids(String psOutput, String enginesDir, int selfPid) {
  final targets = <int>[];
  for (final line in const LineSplitter().convert(psOutput)) {
    final m = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.*)$').firstMatch(line);
    if (m == null) continue;
    final procPid = int.parse(m.group(1)!);
    final ppid = int.parse(m.group(2)!);
    final command = m.group(3)!;
    if (procPid != selfPid && ppid == 1 && command.contains(enginesDir)) {
      targets.add(procPid);
    }
  }
  return targets;
}
