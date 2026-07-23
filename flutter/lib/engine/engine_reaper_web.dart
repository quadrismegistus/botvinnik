// The web build spawns no subprocesses (a browser can't run a binary), so there
// is nothing to reap or guard. See engine_reaper_io.dart for the desktop guard.

void installEngineExitGuards() {}

Future<void> reapOrphanedEngines() async {}
