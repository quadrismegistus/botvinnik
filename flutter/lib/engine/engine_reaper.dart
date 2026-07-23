// Keeps engine subprocesses from outliving the app (see engine_reaper_io.dart).
// The web build has no subprocesses, so it gets a no-op stub — matching the
// custom_engine_runner split.

export 'engine_reaper_io.dart'
    if (dart.library.js_interop) 'engine_reaper_web.dart';
