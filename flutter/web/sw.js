// Offline shell for the Flutter web build.
//
// MANIFEST is written in by tool/gen-sw-manifest.mjs after `flutter build web`
// — this file is a template, and the placeholder below is replaced with the
// real precache list and a content-derived version. Shipping it unreplaced is
// a build error, not a silent no-op; see the guard in install.
const MANIFEST = /*__MANIFEST__*/ null;

// PRECACHE THE SHELL ONLY (~150KB); everything else caches on first use.
//
// Precaching the heavy files was measurably worse than not: the page fetches
// main.dart.js, brain.js, sqlite3.wasm and the 7MB engine during boot while
// `cache.addAll` fetches the same files again, CONCURRENTLY — so no HTTP cache
// can dedupe the pair. Measured at ~12MB of duplicate transfer on every first
// visit and every deploy, and reproduced with Cache-Control set, so it is not
// an artifact of a bare test server.
//
// What the shell buys is the thing that actually needs guaranteeing: a valid
// response for an offline navigation. That is what makes the app INSTALLABLE —
// Chrome checks it — and it is not something runtime caching can bootstrap,
// since the navigate handler below only reads.
//
// Offline capability is unchanged in practice. CanvasKit (the browser picks
// one of several renderer variants at runtime) was always cache-on-first-use,
// so "fully offline" already required one real visit; now the rest arrives the
// same way, from the fetches the app was making anyway.

const CACHE = `botvinnik-flutter-${MANIFEST ? MANIFEST.version : 'dev'}`;

/** Everything we serve, plus fonts if any ever come from Google again. */
function cacheable(url) {
  if (url.origin === self.location.origin) return true;
  // Defence only: Roboto is bundled now and a sweep found no cross-origin
  // requests. If a glyph outside the bundled fonts ever reappears, Flutter
  // will fetch a fallback from here, and offline should degrade to the wrong
  // typeface rather than a failed load.
  return (
    url.origin === 'https://fonts.gstatic.com' ||
    url.origin === 'https://fonts.googleapis.com'
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

  if (!cacheable(url)) return;

  // Cache-first, filling on miss. Entries are immutable for the life of this
  // cache version — the version is a hash of every shipped file, so it changes
  // whenever any of them does and there is nothing to revalidate.
  event.respondWith(
    (async () => {
      const hit = await caches.match(req);
      if (hit) return hit;
      const res = await fetch(req);
      // opaque responses (cross-origin fonts) have status 0 and cache fine; a
      // real error would too, which is the accepted cost of not being able to
      // see across origins. Same-origin misses are checked properly.
      if (res && (res.type === 'opaque' || res.ok)) {
        const cache = await caches.open(CACHE);
        cache.put(req, res.clone());
      }
      return res;
    })()
  );
});
