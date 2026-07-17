/// <reference types="@sveltejs/kit" />
/// <reference lib="webworker" />

// Offline shell: the whole app is client-side (engine included), so caching
// the build + the WASM engine makes botvinnik fully offline-capable. Big
// optional data (commentary.json 4MB, retro/garbo avatars) is deliberately
// NOT precached — it caches on first use so install stays light.

import { build, files, prerendered, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `botvinnik-${version}`;

const PRECACHE = [
	...build,
	...prerendered,
	...files.filter((f) => f.startsWith('/wasm/') || f.startsWith('/icons/') || f === '/manifest.webmanifest')
];
const PRECACHED = new Set(PRECACHE);

sw.addEventListener('install', (event) => {
	event.waitUntil(
		caches
			.open(CACHE)
			.then((c) => c.addAll(PRECACHE))
			.then(() => sw.skipWaiting())
	);
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches
			.keys()
			.then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
			.then(() => sw.clients.claim())
	);
});

sw.addEventListener('fetch', (event) => {
	const { request } = event;
	if (request.method !== 'GET') return;
	const url = new URL(request.url);
	if (url.origin !== sw.location.origin) return;

	event.respondWith(
		(async () => {
			const cache = await caches.open(CACHE);
			// precached build/engine files are immutable per version — cache-first
			if (PRECACHED.has(url.pathname)) {
				const hit = await cache.match(url.pathname);
				if (hit) return hit;
			}
			try {
				const res = await fetch(request);
				// runtime-cache successful same-origin GETs (commentary, avatars)
				// so they survive offline after first sight
				if (res.ok) cache.put(request, res.clone());
				return res;
			} catch {
				const hit = await cache.match(request);
				if (hit) return hit;
				// offline navigation falls back to the app shell
				if (request.mode === 'navigate') {
					const shell = (await cache.match('/')) ?? (await cache.match('/index.html'));
					if (shell) return shell;
				}
				return new Response('offline', { status: 503, statusText: 'offline' });
			}
		})()
	);
});
