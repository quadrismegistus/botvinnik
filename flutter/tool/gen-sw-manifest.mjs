// Writes the precache list and a content-derived version into build/web/sw.js.
// Run after `flutter build web` — see build-web.sh, which is the entry point.
//
// The version is a hash of the precached BYTES, not a timestamp or the app
// version. That is the load-bearing property: a cache name changes exactly
// when its contents change, so a cache can never hold a new main.dart.js
// beside a stale brain.js. That specific mismatch does not degrade — it trips
// the BRAIN_VERSION assert in js_bridge and the app refuses to boot.

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const root = process.argv[2] ?? 'build/web';

/**
 * The SHELL: just enough to answer an offline navigation, which is what makes
 * the app installable — Chrome checks that the worker returns a valid response
 * for the start URL with no network. ~150KB.
 *
 * Everything else caches on first use instead of being precached. Precaching
 * it cost a measured ~12MB of DUPLICATE transfer on every first visit and
 * every deploy: the page fetches the engine and the Dart bundle while the
 * worker's cache.addAll fetches them again, concurrently, so no HTTP cache can
 * dedupe the pair (verified with Cache-Control set, not just on a bare test
 * server). Offline capability is unchanged in practice — CanvasKit was always
 * cache-on-first-use, so full offline already needed one real visit.
 */
function isShell(p) {
  if (p === 'index.html' || p === 'flutter_bootstrap.js' || p === 'flutter.js') return true;
  if (p === 'manifest.json' || p === 'favicon.png' || p === 'version.json') return true;
  if (p.startsWith('icons/')) return true;
  return false;
}

/** Never cache: our own worker, and Flutter's deprecated one. */
function isExcluded(p) {
  return p === 'sw.js' || p === 'flutter_service_worker.js' || p.endsWith('.map');
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) walk(full, out);
    else out.push(relative(root, full).split(sep).join('/'));
  }
  return out;
}

const all = walk(root).filter((p) => !isExcluded(p));
const precache = all.filter(isShell).sort();

if (!precache.includes('index.html') || !precache.includes('flutter_bootstrap.js')) {
  // without these the worker cannot answer an offline navigation, which
  // silently costs installability as well as offline
  throw new Error('gen-sw-manifest: shell is missing index.html or the bootstrap');
}
// A missing staged asset is silent at runtime — the retro personas would just
// fall back to Stockfish after a 30s boot timeout, once, in someone else's
// browser. Fail the build instead.
for (const required of [
  'main.dart.js',
  'brain.js',
  'wasm/stockfish.wasm',
  'retro/retro.wasm',
  'retro/retro-worker.js',
  'garbo/garbochess.js',
  'maia/maia-worker.js',
  'maia/ort-wasm-simd-threaded.wasm',
  'maia/ort-wasm-simd-threaded.mjs',
]) {
  if (!all.includes(required)) {
    throw new Error(`gen-sw-manifest: ${required} is missing from the build`);
  }
}

// Hash EVERY shipped file, not just the shell. The cache name is the only
// thing keeping one build's entries away from another's, and most entries now
// arrive by runtime caching — a version derived from the shell alone would not
// change when main.dart.js did, and a stale brain.js beside a new app trips
// the BRAIN_VERSION assert rather than degrading.
const hash = createHash('sha256');
for (const p of all.slice().sort()) {
  hash.update(p);
  hash.update(readFileSync(join(root, p)));
}
const version = hash.digest('hex').slice(0, 12);

const swPath = join(root, 'sw.js');
const src = readFileSync(swPath, 'utf8');
const token = '/*__MANIFEST__*/ null';
if (!src.includes(token)) {
  throw new Error(`gen-sw-manifest: placeholder not found in ${swPath}`);
}
writeFileSync(
  swPath,
  src.replace(token, JSON.stringify({ version, precache }, null, 2))
);

const bytes = precache.reduce((n, p) => n + statSync(join(root, p)).size, 0);
console.log(
  `sw manifest: shell ${precache.length} files / ${(bytes / 1024).toFixed(0)}KB, ` +
    `version ${version}\n` +
    `             ${all.length - precache.length} more cache on first use`
);
