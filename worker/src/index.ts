/**
 * botvinnik-sync — a dumb, end-to-end-encrypted blob store on Cloudflare R2.
 *
 * The server holds only ciphertext, addressed by an opaque `blobId` that the
 * client derives from the user's sync phrase (HKDF). Knowing the id is the only
 * capability; there are no accounts and no auth. All crypto and all merge logic
 * live on the device — see issue #203 and `flutter/lib/stores/backup.dart`.
 *
 * Two routes:
 *   GET  /b/:id  -> 200 {ciphertext, ETag} | 404
 *   PUT  /b/:id  -> 201 (created) | 200 (updated) | 412 | 413 | 428
 *
 * Compare-and-swap is HTTP-native: the client sends `If-None-Match: *` to
 * create (fails 412 if the blob already exists) or `If-Match: <etag>` to update
 * (fails 412 if someone wrote first → the client re-GETs, re-merges, retries).
 * R2's conditional `put` enforces both against the stored object atomically, so
 * no Durable Object is needed.
 */

export interface Env {
  BUCKET: R2Bucket;
}

// 10 MB ciphertext cap. The backup JSON gzips ~10x, so this is generous; a
// client that somehow exceeds it gets a clean 413 rather than an opaque failure.
const MAX_BYTES = 10 * 1024 * 1024;

// blobId is base64url-encoded HKDF output (~43 chars for 32 bytes). Constrain
// the key space so a stray path can never address a weird R2 object.
const ID_RE = /^[A-Za-z0-9_-]{16,128}$/;

const CORS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, OPTIONS',
  'Access-Control-Allow-Headers': 'If-Match, If-None-Match, Content-Type',
  // Without this the browser JS cannot read the ETag it needs for the next CAS PUT.
  'Access-Control-Expose-Headers': 'ETag',
  'Access-Control-Max-Age': '86400',
};

function reply(body: BodyInit | null, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
  return new Response(body, { ...init, headers });
}

function text(status: number, message: string): Response {
  return reply(message + '\n', {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (request.method === 'OPTIONS') return reply(null, { status: 204 });

    // Health check — cheap "is the Worker up" probe for curl / uptime.
    if (pathname === '/' && request.method === 'GET') {
      return text(200, 'botvinnik-sync');
    }

    const match = pathname.match(/^\/b\/([^/]+)$/);
    if (!match) return text(404, 'not found');

    const id = decodeURIComponent(match[1]);
    if (!ID_RE.test(id)) return text(400, 'bad blob id');

    if (request.method === 'GET') return handleGet(id, env);
    if (request.method === 'PUT') return handlePut(id, request, env);
    return text(405, 'method not allowed');
  },
} satisfies ExportedHandler<Env>;

async function handleGet(id: string, env: Env): Promise<Response> {
  const object = await env.BUCKET.get(id);
  if (object === null) return text(404, 'no such blob');

  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set('ETag', object.httpEtag);
  headers.set('Content-Type', 'application/octet-stream');
  return reply(object.body, { status: 200, headers });
}

async function handlePut(id: string, request: Request, env: Env): Promise<Response> {
  const ifNoneMatch = request.headers.get('If-None-Match');
  const ifMatch = request.headers.get('If-Match');

  // CAS is mandatory: exactly one precondition. This prevents a blind PUT from
  // clobbering a concurrent write. `If-None-Match: *` = create-only;
  // `If-Match: <etag>` = update-only.
  if (!ifNoneMatch && !ifMatch) {
    return text(428, 'precondition required (If-None-Match: * or If-Match: <etag>)');
  }
  if (ifNoneMatch && ifMatch) {
    return text(400, 'send only one of If-None-Match or If-Match');
  }

  // Reject oversized bodies before buffering when we can; enforce hard after.
  const declared = request.headers.get('Content-Length');
  if (declared && Number(declared) > MAX_BYTES) {
    return text(413, `ciphertext exceeds ${MAX_BYTES} bytes`);
  }
  const body = await request.arrayBuffer();
  if (body.byteLength > MAX_BYTES) {
    return text(413, `ciphertext exceeds ${MAX_BYTES} bytes`);
  }

  // Forward the client's conditional header to R2 verbatim. R2 evaluates it
  // against the stored object atomically and returns null if it fails.
  const onlyIf = new Headers();
  if (ifNoneMatch) onlyIf.set('If-None-Match', ifNoneMatch);
  if (ifMatch) onlyIf.set('If-Match', ifMatch);

  const object = await env.BUCKET.put(id, body, { onlyIf });
  if (object === null) {
    return text(412, 'precondition failed (blob changed or already exists)');
  }

  const created = Boolean(ifNoneMatch);
  return reply(null, {
    status: created ? 201 : 200,
    headers: { ETag: object.httpEtag },
  });
}
