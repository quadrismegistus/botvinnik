import { afterEach, describe, expect, it, vi } from 'vitest';
import { encodeFenHistory, flipUci } from './encoding';
import { decodePolicyOutput } from './decoding';
import { POLICY_INDEX_MAP } from './policyIndex';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const AFTER_E4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

const PLANE = 64;
function plane(t: Float32Array, i: number): Float32Array {
	return t.slice(i * PLANE, (i + 1) * PLANE);
}
const allOnes = (p: Float32Array) => p.every((v) => v === 1);
const allZero = (p: Float32Array) => p.every((v) => v === 0);

describe('encodeFenHistory', () => {
	it('produces the [1,112,8,8] tensor with the fixed auxiliary planes', () => {
		const t = encodeFenHistory([START]);
		expect(t.length).toBe(112 * 64);
		expect(allOnes(plane(t, 111))).toBe(true); // all-ones plane
		expect(allZero(plane(t, 110))).toBe(true); // move-count disabled
		expect(allZero(plane(t, 108))).toBe(true); // white to move → 0
	});

	it('flags black to move and relabels pieces to us/them', () => {
		const t = encodeFenHistory([AFTER_E4]);
		expect(allOnes(plane(t, 108))).toBe(true); // black to move → 1
		// with black to move, "us" (planes 0-5) are the black pieces: 8 pawns
		const ownPawns = plane(t, 0).reduce((a, b) => a + b, 0);
		expect(ownPawns).toBe(8);
	});

	it('places white pawns on our-pawn plane at rank 2 (white to move)', () => {
		const t = encodeFenHistory([START]);
		const p = plane(t, 0); // us pawns
		// rank 2 = squares 8..15 in the a1=0 layout
		for (let sq = 8; sq <= 15; sq++) expect(p[sq]).toBe(1);
		expect(p.reduce((a, b) => a + b, 0)).toBe(8);
	});
});

describe('flipUci', () => {
	it('vertically flips ranks, keeps files and promotion', () => {
		expect(flipUci('e2e4')).toBe('e7e5');
		expect(flipUci('a7a8q')).toBe('a2a1q');
	});
});

describe('decodePolicyOutput', () => {
	it('returns the highest-policy legal move (white)', () => {
		const policy = new Float32Array(1858);
		policy[POLICY_INDEX_MAP.get('d2d4')!] = 5;
		policy[POLICY_INDEX_MAP.get('e2e4')!] = 1;
		const { best } = decodePolicyOutput(policy, ['e2e4', 'd2d4', 'g1f3'], false, 0);
		expect(best.move).toBe('d2d4');
	});

	it('maps black moves through the white-POV policy index', () => {
		// Every legal move here must score differently through the FLIPPED
		// lookup and through the un-flipped one, or the test passes on a tie.
		//
		// The earlier version of this set only the flipped index and left the
		// rest at zero, so deleting the flip in decodePolicyOutput scored both
		// moves 0 and the sort returned the first — which happened to be the
		// expected answer. It passed against a broken decoder. Verified: with
		// `canonicalMove = uci`, this now returns c7c5 and fails.
		const policy = new Float32Array(1858);
		policy[POLICY_INDEX_MAP.get('e2e4')!] = 5; // flipUci('e7e5') — the right answer
		policy[POLICY_INDEX_MAP.get('c2c4')!] = 1; // flipUci('c7c5')
		policy[POLICY_INDEX_MAP.get('c7c5')!] = 9; // what a BROKEN decoder would pick
		policy[POLICY_INDEX_MAP.get('e7e5')!] = 0;
		const { best } = decodePolicyOutput(policy, ['e7e5', 'c7c5'], true, 0);
		expect(best.move).toBe('e7e5'); // returned in the original (un-flipped) orientation
	});
});

describe('temperature — the sampled Maia personas', () => {
	// Three of the six Maia personas set maiaTemp: 1 and are otherwise
	// identical to the argmax three. Nothing exercised this branch, so
	// hardcoding temperature to 0 anywhere in the stack — the Dart client, the
	// worker, here — would have collapsed six personas into three silently.
	//
	// Math.random is stubbed so the sampling is deterministic rather than
	// flaky; the point is that temperature CHANGES the choice, not which
	// choice a particular draw makes.
	const policy = new Float32Array(1858);
	policy[POLICY_INDEX_MAP.get('e2e4')!] = 2;
	policy[POLICY_INDEX_MAP.get('d2d4')!] = 0;
	const legal = ['e2e4', 'd2d4'];

	afterEach(() => vi.restoreAllMocks());

	it('temperature 0 ignores the draw and plays the consensus move', () => {
		vi.spyOn(Math, 'random').mockReturnValue(0.99);
		expect(decodePolicyOutput(policy, legal, false, 0).best.move).toBe('e2e4');
	});

	it('temperature 1 samples, so an unlucky draw takes the second move', () => {
		// probabilities are ~0.88 / ~0.12; a draw of 0.95 falls in the tail
		vi.spyOn(Math, 'random').mockReturnValue(0.95);
		expect(decodePolicyOutput(policy, legal, false, 1).best.move).toBe('d2d4');
	});

	it('a higher temperature flattens the distribution, not just the draw', () => {
		// The same draw that keeps e2e4 at temperature 1 gives it away at 100,
		// which is what pins `temp` as a DIVISOR of the logits rather than a
		// bare on/off for sampling.
		vi.spyOn(Math, 'random').mockReturnValue(0.6);
		expect(decodePolicyOutput(policy, legal, false, 1).best.move).toBe('e2e4');
		expect(decodePolicyOutput(policy, legal, false, 100).best.move).toBe('d2d4');
	});
});
