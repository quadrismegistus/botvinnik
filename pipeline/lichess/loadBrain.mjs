// Evaluate the built flutter/assets/brain.js in a bare context — the
// scripts/smoke-brain.mjs pattern (no require/window/DOM, approximating the
// embedded JS engine the Flutter app runs it in).
//
// The commensurability invariant (README): every win-chance number this
// pipeline produces must come from THIS bundle's brain.winChance, never a
// reimplementation. If a table ever needs a function the brain does not
// export (the phase function for T5, the motif detectors' sampling budget
// for T7), the function is added to the brain first — not stubbed out here
// with a local formula.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const DEFAULT_BRAIN_PATH = fileURLToPath(new URL('../../flutter/assets/brain.js', import.meta.url));

export function loadBrain(brainPath = DEFAULT_BRAIN_PATH) {
	const src = readFileSync(brainPath, 'utf8');
	const g = {};
	new Function('globalThis', `${src}; globalThis.brain = brain;`)(g);
	const brain = g.brain;
	if (typeof brain?.winChance !== 'function') {
		throw new Error(`loadBrain: brain.winChance missing after evaluating ${brainPath}`);
	}
	if (typeof brain.BRAIN_VERSION !== 'number') {
		throw new Error(`loadBrain: brain.BRAIN_VERSION missing after evaluating ${brainPath}`);
	}
	return brain;
}
