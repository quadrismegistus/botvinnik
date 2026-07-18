// The web splash lives in index.html so it paints before any Dart exists.
// Flutter's own first frame arrives long before the app is usable — engine,
// database and brain still have to come up — so the splash is dismissed when
// BOOT finishes, not when Flutter starts drawing.
export 'splash_io.dart' if (dart.library.js_interop) 'splash_web.dart';
