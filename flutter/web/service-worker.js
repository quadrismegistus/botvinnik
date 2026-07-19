// Tombstone for the Svelte app's service worker.
//
// This file exists only to remove its predecessor. SvelteKit registered
// `/service-worker.js` at scope `/`, and that worker is **cache-first for the
// app shell** — so after this deploy a returning browser would keep serving
// the CACHED SVELTE index.html from its own cache, the new app would never
// load, and its worker would never get a chance to register. The site would
// look like the deploy silently failed.
//
// Deleting the file instead would rely on a 404 during the browser's update
// check to evict the registration. That does generally work, but it is
// undefined-ish, differs by browser, and the check itself is throttled. A
// worker that removes itself is deterministic and immediate.
//
// The browser fetches worker scripts OUTSIDE the fetch handler, so the old
// worker cannot serve its own cached copy of this and keep itself alive.
//
// Delete this file once nobody could plausibly still hold the Svelte worker —
// it costs one request per deploy and nothing else.

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // The Svelte worker's caches are `botvinnik-${version}`. The Flutter
      // one's are `botvinnik-flutter-${hash}` — same prefix, so it MUST be
      // excluded here or this would evict the new app's cache too, on a deploy
      // where both workers are briefly alive.
      const keys = await caches.keys();
      await Promise.all(
        keys
          .filter((k) => k.startsWith('botvinnik-') && !k.startsWith('botvinnik-flutter-'))
          .map((k) => caches.delete(k))
      );
      await self.registration.unregister();
      // Reload whatever is open: with the registration gone these navigations
      // hit the network and get the new app.
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) client.navigate(client.url);
    })()
  );
});

// Deliberately no fetch handler — everything goes straight to the network for
// the short time this is alive.
