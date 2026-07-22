// Picks the transport for a player-added engine. Native desktop spawns the
// binary as a child process (custom_engine_runner_io.dart); the web has no way
// to run a binary, so its stub is unsupported today and becomes the Phase 2
// server transport (a RemoteEngine to the VPS) later.
//
// Both sides expose `supported`, so the roster refuses to OFFER a custom engine
// on a platform that cannot run it — the same honesty the retro/maia families
// get — rather than showing it and standing in.
export 'custom_engine_runner_io.dart'
    if (dart.library.js_interop) 'custom_engine_runner_web.dart';
