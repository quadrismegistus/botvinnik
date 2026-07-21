// Where a Maia band's weights are, per platform: a file under Application
// Support that native prefetches, or the worker's IndexedDB on the web, which
// it does not. Both answer the one question the roster picker asks — is this
// band ready to play offline — and the web's honest answer is "unknown".
export 'maia_weights_io.dart'
    if (dart.library.js_interop) 'maia_weights_web.dart';
