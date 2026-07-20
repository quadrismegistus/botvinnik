// Post-build smoke test for flutter/assets/maia-brain.js: evaluate the IIFE in
// a bare context (no require/window/DOM, approximating the JavaScriptCore the
// Flutter app embeds) and replay the golden fixtures through it.
//
// This is the step that was missing. `git diff --exit-code` proves the bundle
// matches its TypeScript; `npm run check:flutter-ts` proves the TypeScript
// type-checks. Neither noticed a source edit that decoded the policy from the
// wrong side — the bundle matched, the types held, and the app played the
// opponent's move. Regenerating the fixtures (`npm run fixtures:maia`) is now
// the deliberate act that records such a change.
//
// No ONNX and no network: the fixtures pin the encode digest and a decode
// against a fixed synthetic policy, which is all of the bundle's own logic.
import { readFileSync } from 'node:fs';

import { CASES, digest, syntheticPolicy } from './maia-brain-cases.mjs';

const src = readFileSync(
	new URL('../flutter/assets/maia-brain.js', import.meta.url),
	'utf8'
);
const g = {};
new Function('globalThis', `${src}; globalThis.maiaBrain = maiaBrain;`)(g);
const maia = g.maiaBrain;

const golden = JSON.parse(
	readFileSync(new URL('./maia-brain-fixtures.json', import.meta.url), 'utf8')
);

const fail = (msg) => {
	console.error(`maia-brain smoke FAILED: ${msg}`);
	console.error('if this change was intended, run: npm run fixtures:maia');
	process.exit(1);
};

if (typeof maia?.MAIA_BRAIN_VERSION !== 'number') fail('MAIA_BRAIN_VERSION missing');
if (golden.cases.length !== CASES.length)
	fail(`fixtures hold ${golden.cases.length} cases, the source has ${CASES.length}`);

const policy = Array.from(syntheticPolicy());

for (const want of golden.cases) {
	const fen = want.history[want.history.length - 1];

	const planes = maia.maiaPlanes(want.history);
	if (!Array.isArray(planes)) fail(`${want.name}: maiaPlanes returned ${planes}`);
	if (planes.length !== 7168) fail(`${want.name}: ${planes.length} planes, expected 7168`);
	const got = digest(planes);
	if (got !== want.planes) fail(`${want.name}: planes ${got}, expected ${want.planes}`);

	const pick = maia.maiaPick(policy, fen, 0);
	if (pick !== want.pick) fail(`${want.name}: picked ${pick}, expected ${want.pick}`);
}

// A position with no legal moves must cost no inference at all.
if (maia.maiaPlanes(['7k/5KQ1/8/8/8/8/8/8 b - - 0 1']) !== null)
	fail('a mated position returned planes');

console.log(`maia-brain smoke OK (${golden.cases.length} cases)`);
