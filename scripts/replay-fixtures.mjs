// Replay the golden fixtures against the BUILT brain.js bundle — catches
// bundling/tree-shaking regressions in seconds. Runs as part of
// `npm run build:brain`. The on-device twin (flutter/integration_test/
// brain_parity_test.dart) replays the same file through the Dart bridge.

import { readFileSync } from 'node:fs';

const root = new URL('..', import.meta.url);
const src = readFileSync(new URL('flutter/assets/brain.js', root), 'utf8');
const g = {};
new Function('globalThis', `${src}; globalThis.brain = brain;`)(g);
const brain = g.brain;

const { fixtures } = JSON.parse(
	readFileSync(new URL('flutter/assets/brain-fixtures.json', root), 'utf8')
);

const TOL = 1e-6;
function deepEqual(a, b, ignore) {
	if (a === b) return true;
	if (typeof a === 'number' && typeof b === 'number') {
		return Math.abs(a - b) <= TOL * Math.max(1, Math.abs(a), Math.abs(b));
	}
	if (a === null || b === null || typeof a !== typeof b) return false;
	if (Array.isArray(a)) {
		if (!Array.isArray(b) || a.length !== b.length) return false;
		return a.every((v, i) => deepEqual(v, b[i], ignore));
	}
	if (typeof a === 'object') {
		const ka = Object.keys(a).filter((k) => !ignore.has(k) && a[k] !== undefined);
		const kb = Object.keys(b).filter((k) => !ignore.has(k) && b[k] !== undefined);
		if (ka.length !== kb.length) return false;
		return ka.every((k) => deepEqual(a[k], b[k], ignore));
	}
	return false;
}

let failed = 0;
for (const [i, f] of fixtures.entries()) {
	const args = f.args.map((a) => (a === '__OMIT__' ? undefined : a));
	let actual;
	try {
		actual = brain[f.fn](...args);
	} catch (e) {
		console.error(`✗ [${i}] ${f.fn}: threw ${e.message}`);
		failed++;
		continue;
	}
	const ignore = new Set(f.ignore ?? []);
	if (!deepEqual(actual ?? null, f.expected ?? null, ignore)) {
		console.error(`✗ [${i}] ${f.fn}:\n  expected ${JSON.stringify(f.expected)}\n  actual   ${JSON.stringify(actual)}`);
		failed++;
	}
}

if (failed > 0) {
	console.error(`fixture replay FAILED: ${failed}/${fixtures.length}`);
	process.exit(1);
}
console.log(`fixture replay OK — ${fixtures.length}/${fixtures.length} against built brain.js`);
