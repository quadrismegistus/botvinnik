// Offline shell for the Flutter web build.
//
// MANIFEST is written in by tool/gen-sw-manifest.mjs after `flutter build web`
// — this file is a template, and the placeholder below is replaced with the
// real precache list and a content-derived version. Shipping it unreplaced is
// a build error, not a silent no-op; see the guard in install.
const MANIFEST = /*__MANIFEST__*/ null;

// What goes in the precache and what does not, decided by measuring an actual
// boot (28 requests, 16.8MB uncompressed):
//
//   PRECACHED — needed every session regardless of browser or settings:
//     the shell, main.dart.js, brain.js, sqlite3.wasm, and wasm/ (Stockfish,
//     7.1MB, the single biggest item and the one you cannot play without).
//
//   CACHE ON FIRST USE — real but conditional, so precaching them would mean
//   downloading things most users never touch:
//     canvaskit/ — Flutter ships several renderer variants and the browser
//       picks one at runtime (Chrome takes canvaskit/chromium/, 5.6MB).
//       Precaching every variant is ~12.6MB of which one is used.
//     assets/packages/chessground/ — 14.6MB of 40 piece sets and the board
//       textures, of which a session uses one set and one board.
//     fonts.gstatic.com — Flutter fetches Roboto and Noto from Google at
//       runtime. Cross-origin, so these cache opaquely: we cannot tell a 404
//       from a hit, which is exactly why they are not precached. Missing them
//       offline costs the intended typeface, not the app.
//
// So: full offline after one complete online visit; the heavy shared parts
// are there from the first install.

const CACHE = `botvinnik-flutter-${MANIFEST ? MANIFEST.version : 'dev'}`;

/** Cache on first use rather than at install. */
function runtimeCacheable(url) {
  if (url.origin === 'https://fonts.gstatic.com' || url.origin === 'https://fonts.googleapis.com') {
    return true;
  }
  if (url.origin !== self.location.origin) return false;
  return (
    url.pathname.includes('/canvaskit/') ||
    url.pathname.includes('/assets/packages/chessground/') ||
    url.pathname.endsWith('/assets/NOTICES')
  );
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      if (!MANIFEST) {
        // the template shipped unprocessed: fail loudly rather than install an
        // empty cache that looks like working offline support
        throw new Error('sw.js: manifest placeholder was never replaced');
      }
      const cache = await caches.open(CACHE);
      // addAll is all-or-nothing, which is the property we want: a cache
      // holding a new main.dart.js next to a stale brain.js would hard-fail
      // the BRAIN_VERSION assert at boot rather than degrade
      await cache.addAll(MANIFEST.precache);
    })()
  );
});

// No skipWaiting, deliberately. A new version waits until every old tab is
// gone. Activating immediately would claim pages that were loaded against the
// PREVIOUS build and then purge the cache those pages are still fetching from
// — and here that is worse than a missing chunk: a new brain.js under an old
// main.dart.js trips the version assert and the app refuses to boot.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Navigations: serve the cached shell so a cold offline start works. The app
  // is a single page, so any navigation resolves to index.html.
  if (req.mode === 'navigate') {
    event.respondWith(
      (async () =>
        (await caches.match('index.html')) ||
        (await caches.match('./')) ||
        fetch(req))()
    );
    return;
  }

  const precached = MANIFEST && MANIFEST.precache.includes(url.pathname.replace(/^\//, ''));
  if (precached) {
    // immutable for the life of this cache version — the version changes when
    // the bytes do, so there is nothing to revalidate
    event.respondWith((async () => (await caches.match(req)) || fetch(req))());
    return;
  }

  if (runtimeCacheable(url)) {
    event.respondWith(
      (async () => {
        const hit = await caches.match(req);
        if (hit) return hit;
        const res = await fetch(req);
        // opaque responses (cross-origin fonts) have status 0 and cache fine;
        // a real error would too, which is the accepted cost of not being able
        // to see across origins. Same-origin misses are checked properly.
        if (res && (res.type === 'opaque' || res.ok)) {
          const cache = await caches.open(CACHE);
          cache.put(req, res.clone());
        }
        return res;
      })()
    );
  }
});
