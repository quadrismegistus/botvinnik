// The service worker's caching, run as the REAL shipped file.
//
// sw.js had no tests at all, and the thing it now claims — that a deploy stops
// evicting 7MB of vendored engines — is invisible until someone plays a game
// straight after a release and gets a Stockfish stand-in, which is how the
// cost of NOT having it was found. So the worker is loaded here the same way
// the retro probe loads its worker: the real file, with the browser bits
// faked, driven through two deploys.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

const SW = fileURLToPath(new URL('../web/sw.js', import.meta.url));
const ORIGIN = 'https://botvinnik.app';

/** A Cache/CacheStorage pair, enough of one for what sw.js actually calls. */
function makeCaches() {
  const stores = new Map();
  const open = async (name) => {
    if (!stores.has(name)) stores.set(name, new Map());
    const store = stores.get(name);
    return {
      match: async (k) => store.get(String(k)),
      put: async (k, v) => void store.set(String(k), v),
      delete: async (k) => store.delete(String(k?.url ?? k)),
      keys: async () => [...store.keys()].map((url) => ({ url })),
    };
  };
  return {
    stores,
    api: {
      open,
      keys: async () => [...stores.keys()],
      delete: async (name) => stores.delete(name),
      match: async (k) => {
        for (const store of stores.values()) if (store.has(String(k))) return store.get(String(k));
        return undefined;
      },
    },
  };
}

/** Boot the real sw.js against a manifest, and return handles to drive it. */
function bootWorker(manifest, { caches: sharedCaches, fetched = [] } = {}) {
  const src = readFileSync(SW, 'utf8').replace(
    '/*__MANIFEST__*/ null',
    JSON.stringify(manifest)
  );
  const handlers = {};
  const c = sharedCaches ?? makeCaches();
  const self = {
    location: { origin: ORIGIN },
    addEventListener: (name, fn) => void (handlers[name] = fn),
    clients: { claim: async () => {} },
    skipWaiting: () => {},
    caches: c.api,
  };
  const fetchImpl = async (req) => {
    fetched.push(String(req.url ?? req));
    return { status: 200, type: 'basic', clone: () => ({ body: String(req.url ?? req) }) };
  };
  // eslint-disable-next-line no-new-func
  new Function('self', 'caches', 'fetch', 'location', src)(
    self,
    c.api,
    fetchImpl,
    self.location
  );

  const fire = async (name, event) => {
    let awaited;
    const e = {
      ...event,
      waitUntil: (p) => void (awaited = p),
      respondWith: (p) => void (awaited = p),
    };
    handlers[name]?.(e);
    return awaited;
  };
  return { fire, caches: c, fetched };
}

const ENGINE = `${ORIGIN}/retro/retro.wasm`;
const manifest = (version, wasmHash) => ({
  version,
  precache: [],
  stable: { 'retro/retro.wasm': wasmHash },
});
const get = (url) => ({ request: { method: 'GET', url, mode: 'no-cors' } });

describe('the engine cache survives a deploy', () => {
  it('fetches a vendored engine once, then serves it from cache', async () => {
    const w = bootWorker(manifest('v1', 'aaaa'));
    await w.fire('fetch', get(ENGINE));
    await w.fire('fetch', get(ENGINE));
    expect(w.fetched).toEqual([ENGINE]); // once, not twice
  });

  it('keeps it across a NEW APP VERSION — the whole point', async () => {
    // Deploy 1: the asset is fetched and cached.
    const shared = makeCaches();
    const first = bootWorker(manifest('v1', 'aaaa'), { caches: shared });
    await first.fire('fetch', get(ENGINE));
    expect(first.fetched).toEqual([ENGINE]);

    // Deploy 2: a different app version — every other cache is evicted — but
    // the engine is byte-identical, so its hash and therefore its key are the
    // same. Before this change the cache NAME carried the app version, so this
    // was a guaranteed re-download of 4.4MB.
    const second = bootWorker(manifest('v2', 'aaaa'), { caches: shared });
    await second.fire('activate', {});
    await second.fire('fetch', get(ENGINE));
    expect(second.fetched).toEqual([]);
  });

  it('re-fetches when the asset itself changes, and drops the old copy', async () => {
    const shared = makeCaches();
    const first = bootWorker(manifest('v1', 'aaaa'), { caches: shared });
    await first.fire('fetch', get(ENGINE));

    const second = bootWorker(manifest('v2', 'bbbb'), { caches: shared });
    await second.fire('activate', {});
    await second.fire('fetch', get(ENGINE));
    expect(second.fetched).toEqual([ENGINE]);

    // and the superseded entry is gone rather than accumulating one dead 4.4MB
    // copy per engine update
    const engines = await shared.api.open('botvinnik-engines');
    const keys = (await engines.keys()).map((r) => r.url);
    expect(keys).toEqual([`${ENGINE}?v=bbbb`]);
  });

  it('leaves our own bundle on the cache that rotates', async () => {
    // brain.js has a version contract with main.dart.js — a stale one trips
    // the BRAIN_VERSION assert and the app refuses to boot. It must NOT get a
    // deploy-proof cache, and the manifest is what decides that.
    const w = bootWorker(manifest('v1', 'aaaa'));
    await w.fire('fetch', get(`${ORIGIN}/brain.js`));
    const engines = await w.caches.api.open('botvinnik-engines');
    expect(await engines.keys()).toEqual([]);
  });
});
