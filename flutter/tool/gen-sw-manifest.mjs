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

/** Needed every session regardless of browser or settings. */
function isPrecache(p) {
  if (p === 'index.html' || p === 'flutter_bootstrap.js' || p === 'flutter.js') return true;
  if (p === 'main.dart.js' || p === 'brain.js' || p === 'sqlite3.wasm') return true;
  if (p === 'manifest.json' || p === 'favicon.png' || p === 'version.json') return true;
  if (p.startsWith('wasm/')) return true; // Stockfish — no engine, no game
  if (p.startsWith('icons/')) return true;
  // note the doubled prefix: a font declared in pubspec as assets/fonts/X is
  // emitted at assets/assets/fonts/X, so match the segment rather than a
  // literal path — anchoring on 'assets/fonts/' silently dropped bundled
  // Roboto into cache-on-first-use, i.e. absent on a first offline load
  if (p.startsWith('assets/') && /(^|\/)fonts\//.test(p)) return true;
  if (p.startsWith('assets/packages/cupertino_icons/')) return true;
  if (p.startsWith('assets/AssetManifest') || p === 'assets/FontManifest.json') return true;
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
const precache = all.filter(isPrecache).sort();

if (!precache.includes('main.dart.js') || !precache.includes('brain.js')) {
  // a rename upstream would otherwise produce a cheerful, useless cache
  throw new Error('gen-sw-manifest: precache is missing the app or the brain — check isPrecache');
}

const hash = createHash('sha256');
for (const p of precache) {
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
  `sw manifest: ${precache.length} files precached, ` +
    `${(bytes / 1048576).toFixed(1)}MB, version ${version}\n` +
    `             ${all.length - precache.length} more cache on first use`
);
