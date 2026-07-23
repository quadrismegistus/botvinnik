import { build } from 'esbuild';
import { Miniflare } from 'miniflare';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

// Drive the real Worker through Miniflare (workerd + an in-memory R2 bucket), so
// the conditional-PUT (CAS) semantics under test are the ones R2 enforces in
// production, not a hand-rolled stand-in.
let mf: Miniflare;

const BASE = 'https://sync.test';
const url = (id: string) => `${BASE}/b/${id}`;

// Unique 16+ char ids per call so blobs never collide across tests.
let counter = 0;
const freshId = () => `blob${'x'.repeat(16)}${counter++}`;

function fetch(input: string, init?: RequestInit) {
  // Miniflare's dispatchFetch returns an undici Response; the shapes we use
  // (status, headers.get, text) match the DOM types closely enough.
  return mf.dispatchFetch(input, init as never) as unknown as Promise<Response>;
}

function create(id: string, body: BodyInit) {
  return fetch(url(id), { method: 'PUT', headers: { 'If-None-Match': '*' }, body });
}
function update(id: string, etag: string, body: BodyInit) {
  return fetch(url(id), { method: 'PUT', headers: { 'If-Match': etag }, body });
}

// Build the Worker once, reused across Miniflare instances (the main one and the
// rate-limiting one below).
let _code: string | undefined;
async function workerCode(): Promise<string> {
  if (_code) return _code;
  const entry = fileURLToPath(new URL('../src/index.ts', import.meta.url));
  const bundled = await build({
    entryPoints: [entry],
    bundle: true,
    format: 'esm',
    platform: 'neutral',
    target: 'es2022',
    write: false,
  });
  return (_code = bundled.outputFiles[0].text);
}

beforeAll(async () => {
  mf = new Miniflare({
    modules: [{ type: 'ESModule', path: 'index.mjs', contents: await workerCode() }],
    r2Buckets: ['BUCKET'],
    compatibilityDate: '2024-11-01',
  });
  await mf.ready;
});

afterAll(async () => {
  await mf?.dispose();
});

describe('GET /b/:id', () => {
  it('404s for a blob that does not exist', async () => {
    expect((await fetch(url(freshId()))).status).toBe(404);
  });

  it('round-trips ciphertext written by create, with a matching ETag', async () => {
    const id = freshId();
    const put = await create(id, 'ciphertext-one');
    expect(put.status).toBe(201);
    const etag = put.headers.get('ETag');
    expect(etag).toBeTruthy();

    const got = await fetch(url(id));
    expect(got.status).toBe(200);
    expect(await got.text()).toBe('ciphertext-one');
    expect(got.headers.get('ETag')).toBe(etag);
    expect(got.headers.get('Content-Type')).toBe('application/octet-stream');
  });
});

describe('PUT /b/:id — create (If-None-Match: *)', () => {
  it('creates a new blob and returns 201', async () => {
    const res = await create(freshId(), 'hello');
    expect(res.status).toBe(201);
    expect(res.headers.get('ETag')).toBeTruthy();
  });

  it('412s when the blob already exists (create-conflict)', async () => {
    const id = freshId();
    expect((await create(id, 'first')).status).toBe(201);
    expect((await create(id, 'second')).status).toBe(412);
    expect(await (await fetch(url(id))).text()).toBe('first'); // original untouched
  });
});

describe('PUT /b/:id — update (If-Match: <etag>)', () => {
  it('updates when the etag is current and returns 200 + a new etag', async () => {
    const id = freshId();
    const etag1 = (await create(id, 'v1')).headers.get('ETag')!;

    const second = await update(id, etag1, 'v2');
    expect(second.status).toBe(200);
    expect(second.headers.get('ETag')).not.toBe(etag1);
    expect(await (await fetch(url(id))).text()).toBe('v2');
  });

  it('412s on a stale etag and leaves the blob unchanged', async () => {
    const id = freshId();
    const staleEtag = (await create(id, 'v1')).headers.get('ETag')!;

    expect((await update(id, staleEtag, 'v2')).status).toBe(200); // a writer moves it on
    const loser = await update(id, staleEtag, 'v3-should-lose');
    expect(loser.status).toBe(412);
    expect(await (await fetch(url(id))).text()).toBe('v2');
  });
});

describe('PUT /b/:id — precondition discipline', () => {
  it('428s when no precondition is supplied (blind PUT is refused)', async () => {
    expect((await fetch(url(freshId()), { method: 'PUT', body: 'x' })).status).toBe(428);
  });

  it('400s when both preconditions are supplied', async () => {
    const res = await fetch(url(freshId()), {
      method: 'PUT',
      headers: { 'If-None-Match': '*', 'If-Match': '"abc"' },
      body: 'x',
    });
    expect(res.status).toBe(400);
  });
});

describe('limits & routing', () => {
  it('413s a body over the 10 MB cap', async () => {
    const res = await create(freshId(), new Uint8Array(10 * 1024 * 1024 + 1));
    expect(res.status).toBe(413);
  });

  it('accepts a body exactly at the 10 MB cap', async () => {
    const res = await create(freshId(), new Uint8Array(10 * 1024 * 1024));
    expect(res.status).toBe(201);
  });

  it('405s an unsupported method', async () => {
    expect((await fetch(url(freshId()), { method: 'DELETE' })).status).toBe(405);
  });

  it('400s an id outside the allowed charset/length', async () => {
    expect((await fetch(`${BASE}/b/short`)).status).toBe(400); // < 16 chars
  });

  it('404s an unknown path', async () => {
    expect((await fetch(`${BASE}/nope`)).status).toBe(404);
  });

  it('serves a health check at /', async () => {
    const res = await fetch(`${BASE}/`);
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('botvinnik-sync');
  });
});

describe('CORS', () => {
  it('answers preflight with 204 and the expected headers', async () => {
    const res = await fetch(url(freshId()), { method: 'OPTIONS' });
    expect(res.status).toBe(204);
    expect(res.headers.get('Access-Control-Allow-Methods')).toContain('PUT');
    expect(res.headers.get('Access-Control-Allow-Headers')).toContain('If-Match');
  });

  it('exposes ETag to browser JS on real responses', async () => {
    const res = await fetch(url(freshId()));
    expect(res.headers.get('Access-Control-Expose-Headers')).toContain('ETag');
  });
});

describe('rate limiting', () => {
  // A dedicated Miniflare with a low limit — the main suite has no RATE_LIMITER
  // binding, so its many requests are never throttled.
  let rlmf: Miniflare;
  const rlFetch = () =>
    rlmf.dispatchFetch(url('r'.repeat(20))) as unknown as Promise<Response>;

  beforeAll(async () => {
    rlmf = new Miniflare({
      modules: [{ type: 'ESModule', path: 'index.mjs', contents: await workerCode() }],
      r2Buckets: ['BUCKET'],
      ratelimits: {
        RATE_LIMITER: { namespace_id: 'test', simple: { limit: 3, period: 60 } },
      },
      compatibilityDate: '2024-11-01',
    });
    await rlmf.ready;
  });

  afterAll(async () => {
    await rlmf?.dispose();
  });

  it('429s once the per-window limit is exceeded', async () => {
    const codes: number[] = [];
    for (let i = 0; i < 5; i++) codes.push((await rlFetch()).status);
    expect(codes[0]).toBe(404); // early requests still served (blob absent)
    expect(codes.filter((c) => c === 429).length).toBeGreaterThan(0);
  });
});
