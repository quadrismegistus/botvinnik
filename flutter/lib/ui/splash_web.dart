import 'dart:js_interop';

@JS('eval')
external JSAny? _jsEval(String code);

/// Tells index.html the app is ready. Guarded so a missing hook (a stripped
/// or customised index.html) is a no-op rather than a crash on boot.
void dismissSplash() =>
    _jsEval('window.botvinnikReady && window.botvinnikReady()');
