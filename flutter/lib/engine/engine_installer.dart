// Downloads and installs a catalogued engine binary. Native desktop only — a
// browser cannot save or run an executable — so the web side is a stub, and the
// Engines screen hides the download UI where `supported` is false.
export 'engine_installer_io.dart'
    if (dart.library.js_interop) 'engine_installer_web.dart';
