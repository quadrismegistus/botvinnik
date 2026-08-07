// The two halves of the skill report ship as separate committed artifacts:
// flutter/assets/peer-tables.json (built by the pipeline, months ago is fine)
// and flutter/assets/brain.js (rebuilt every brain change). The screen
// REFUSES tables whose brainVersion differs from the running brain's — the
// right behavior at runtime, and a shipped outage if the committed pair ever
// drifts: bump BRAIN_VERSION, rebuild the bundle, forget the tables, and
// every suite stays green while the report errors on open for every user
// (#294 review, run-proven — the fixtures pin the two sides to each other,
// not to the shipped files).
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { BRAIN_VERSION } from './brain-entry';

const read = (rel: string) => readFileSync(new URL(rel, import.meta.url), 'utf8');

describe('shipped assets agree on the brain version', () => {
	it('peer-tables.json was built by the brain this source IS', () => {
		const tables = JSON.parse(read('../flutter/assets/peer-tables.json'));
		expect(tables.brainVersion).toBe(BRAIN_VERSION);
	});

	it('the committed bundle is the brain this source IS', () => {
		// A stale bundle is the flutter-web memory's oldest hazard (esbuild
		// does not typecheck and nothing diffs the artifact against source).
		const src = read('../flutter/assets/brain.js');
		const g: Record<string, any> = {};
		new Function('globalThis', `${src}; globalThis.brain = brain;`)(g);
		expect(g.brain.BRAIN_VERSION).toBe(BRAIN_VERSION);
	});
});
