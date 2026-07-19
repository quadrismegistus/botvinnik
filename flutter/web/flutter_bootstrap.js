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
    navigator.serviceWorker.register('sw.js').then(watchForUpdate).catch((e) => {
      // no offline support, but the app itself is unaffected
      console.warn('[sw] registration failed:', e);
    });
  });

  // Reload once the new worker takes over, so every tab lands on the same
  // build rather than half the app running against a purged cache.
  let reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloading) return;
    reloading = true;
    window.location.reload();
  });
}

/**
 * Offer the update instead of waiting for every tab to close.
 *
 * There is no skipWaiting in the worker, deliberately — so an installed PWA
 * that is never fully shut serves the old build forever. This surfaces the
 * waiting worker and lets the user take it.
 */
function watchForUpdate(reg) {
  const offer = () => {
    if (!reg.waiting || document.getElementById('sw-update')) return;
    const bar = document.createElement('div');
    bar.id = 'sw-update';
    bar.setAttribute('role', 'status');
    bar.style.cssText =
      'position:fixed;left:50%;bottom:84px;transform:translateX(-50%);z-index:9999;' +
      'display:flex;gap:12px;align-items:center;padding:10px 14px;border-radius:8px;' +
      'background:#1f1e1b;color:#e8e6e3;border:1px solid #3a3733;font:13px system-ui,sans-serif;' +
      'box-shadow:0 6px 24px rgba(0,0,0,.45)';
    const msg = document.createElement('span');
    msg.textContent = 'A new version is ready.';
    const btn = document.createElement('button');
    btn.textContent = 'Reload';
    btn.style.cssText =
      'cursor:pointer;border:0;border-radius:5px;padding:5px 11px;' +
      'background:#81B64C;color:#12210a;font:600 13px system-ui,sans-serif';
    // controllerchange above does the reloading, once the new worker is in
    btn.onclick = () => reg.waiting && reg.waiting.postMessage('botvinnik:skip-waiting');
    bar.append(msg, btn);
    document.body.appendChild(bar);
  };

  if (reg.waiting) offer(); // already waiting when this tab opened
  reg.addEventListener('updatefound', () => {
    const sw = reg.installing;
    if (!sw) return;
    sw.addEventListener('statechange', () => {
      // "installed" with a controller present means an UPDATE, not a first
      // install — a first install has nothing to replace and no prompt to show
      if (sw.state === 'installed' && navigator.serviceWorker.controller) offer();
    });
  });
}
