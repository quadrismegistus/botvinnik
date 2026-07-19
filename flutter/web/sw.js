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

/**
 * A board asset we do not have, offline: serve a DIFFERENT one we do.
 *
 * Only the piece set and board texture in use get cached, but Settings offers
 * all 40 sets. Picking an uncached one with no network left the board with no
 * pieces at all — 13 failed image loads — and it persisted across reloads
 * until the network came back, because nothing retries. A board wearing the
 * wrong pieces is strictly better than a board wearing none.
 *
 * Matched on the trailing segments so a piece is replaced by the SAME piece at
 * the same resolution from another set (`3.0x/wQ.webp`), and a board texture by
 * any cached board.
 */
async function boardAssetFallback(url) {
  const p = url.pathname;
  const isPiece = p.includes('/piece_sets/');
  if (!isPiece && !p.includes('/boards/')) return null;
  const cache = await caches.open(CACHE);
  const keys = await cache.keys();
  // pieces: same filename, and same resolution folder when there is one
  const parts = p.split('/');
  const file = parts[parts.length - 1];
  const scale = /^\d+(\.\d+)?x$/.test(parts[parts.length - 2] ?? '')
    ? parts[parts.length - 2]
    : null;
  const sameFile = (q) => q.includes('/piece_sets/') && q.endsWith(`/${file}`);
  const paths = keys.map((r) => [r, new URL(r.url).pathname]);
  // Prefer the same piece at the same resolution; accept any resolution
  // rather than nothing. Chessground caches some sets WITHOUT a scale folder
  // (`cburnett/wQ.webp`) and others with (`merida/3.0x/wQ.webp`), so
  // insisting on a scale match found nothing and left the board empty.
  const hit = isPiece
      ? (scale !== null &&
              paths.find(([, q]) => sameFile(q) && q.includes(`/${scale}/`))) ||
          paths.find(([, q]) => sameFile(q))
      : paths.find(([, q]) => q.includes('/boards/'));
  return hit ? cache.match(hit[0]) : null;
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
      // `cache: 'reload'` on every fetch this worker makes, here and below:
      // the DEFAULT mode lets the browser's HTTP cache answer, so a worker
      // installing for build N could fill N's cache with build N-1's bytes.
      // The cache name being a content hash does NOT prevent that — it names
      // the cache after the build it was made FOR, not what went into it.
      // Demonstrated: a new main.dart.js beside a stale brain.js, which trips
      // the BRAIN_VERSION assert and refuses to boot, unrecoverable by reload.
      await Promise.all(
        MANIFEST.precache.map(async (url) => {
          const res = await fetch(url, { cache: 'reload' });
          if (!res.ok) throw new Error(`precache ${url}: ${res.status}`);
          await cache.put(url, res);
        })
      );
    })()
  );
});

// No skipWaiting, deliberately. A new version waits until every old tab is
// gone. Activating immediately would claim pages that were loaded against the
// PREVIOUS build and then purge the cache those pages are still fetching from
// — and here that is worse than a missing chunk: a new brain.js under an old
// main.dart.js trips the version assert and the app refuses to boot.
// The page asks for the update when the user accepts it. Without this a new
// version waits for every tab to close, which for an installed PWA that is
// never fully closed means indefinitely — verified: a waiting worker stayed
// waiting across reloads and new tabs, serving the old build throughout.
//
// This does not undo the no-skipWaiting stance below. The difference is
// consent plus an immediate reload: activate claims every client, and each one
// reloads on controllerchange, so no page keeps running against the old cache.
self.addEventListener('message', (event) => {
  if (event.data === 'botvinnik:skip-waiting') self.skipWaiting();
});

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
      // 'reload' bypasses the HTTP cache — see the note in install. Without
      // it this is the line that mixes builds.
      let res;
      try {
        res = await fetch(req, { cache: 'reload' });
      } catch (e) {
        const fallback = await boardAssetFallback(url);
        if (fallback) return fallback;
        throw e;
      }
      if (!res.ok) {
        const fallback = await boardAssetFallback(url);
        if (fallback) return fallback;
      }
      // opaque responses (cross-origin fonts) have status 0 and cache fine; a
      // real error would too, which is the accepted cost of not being able to
      // see across origins. Same-origin misses are checked properly.
      //
      // status === 200 rather than res.ok: a 206 is "ok" but Cache.put rejects
      // partial responses, and an unawaited put would reject unhandled.
      if (res && (res.type === 'opaque' || res.status === 200)) {
        const cache = await caches.open(CACHE);
        cache.put(req, res.clone()).catch(() => {});
      }
      return res;
    })()
  );
});
