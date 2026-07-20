// Golden fixtures for the native Maia bundle, emitted from brain/maia/ itself.
//
//   npm run fixtures:maia
//
// The point is brain-fixtures.json's point: `git diff --exit-code` on the
// built bundle proves it MATCHES its source, and nothing else proved the
// source was still right. A reviewer demonstrated the gap by decoding the
// policy from the wrong side — type-correct, bundle-consistent, green through
// every CI step, and a Maia playing as its opponent.
//
// So these are the behaviour record: regenerate them deliberately, and the git
// diff of the JSON IS the review of what changed.
//
// Deliberately no ONNX and no network — that is what the macOS/iOS integration
// test is for. These pin the two PURE halves: the encoding by digest, and the
// decoding by feeding a fixed synthetic policy and recording which legal move
// comes back.

import { writeFileSync } from 'node:fs';

import { decodePolicyOutput } from '../brain/maia/decoding';
import { encodeFenHistory } from '../brain/maia/encoding';
import { CASES, digest, legalUcis, syntheticPolicy } from './maia-brain-cases.mjs';

const cases = CASES.map((c) => {
	const fen = c.history[c.history.length - 1];
	const isBlack = fen.split(' ')[1] === 'b';
	return {
		name: c.name,
		history: c.history,
		planes: digest(encodeFenHistory(c.history)),
		pick: decodePolicyOutput(syntheticPolicy(), legalUcis(fen), isBlack, 0).best.move
	};
});

writeFileSync(
	new URL('./maia-brain-fixtures.json', import.meta.url),
	JSON.stringify({ version: 1, cases }, null, '\t') + '\n'
);
console.log(`wrote ${cases.length} cases to scripts/maia-brain-fixtures.json`);
