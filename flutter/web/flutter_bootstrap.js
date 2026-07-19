// Custom bootstrap, replacing the one `flutter build web` generates, for one
// reason: to stop Flutter registering ITS service worker.
//
// The generated bootstrap calls the loader with serviceWorkerSettings, which
// registers `flutter_service_worker.js` — 784 bytes whose entire body calls
// `self.registration.unregister()` and reloads every client. Flutter's own
// source calls it deprecated. Left in place it would fight ours for the root
// scope, and the loser is decided by registration order, which is racy.
//
// So: load Flutter with no serviceWorker settings, then register `sw.js`
// ourselves. See sw.js for what it caches and why.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();

if ('serviceWorker' in navigator) {
  // after load, so the worker install never competes with the boot fetches it
  // is about to cache — the app should come up at first-visit speed
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch((e) => {
      // no offline support, but the app itself is unaffected
      console.warn('[sw] registration failed:', e);
    });
  });
}
