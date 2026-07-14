import { describe, it, expect } from 'vitest';
import { shapedBotMove, shapedParams } from './bot';
import type { EngineMove } from './engine/stockfish';

// Build a MultiPV line. `score` is pawns from the mover's POV; the first token
// of `uci` is the move played.
function line(uci: string, score: number, multipv: number, mate: number | null = null): EngineMove {
	return { pv: [uci], score, mate, depth: 18, multipv };
}

function tally(fn: () => string | null, n = 4000): Map<string, number> {
	const counts = new Map<string, number>();
	for (let i = 0; i < n; i++) {
		const mv = fn()!;
		counts.set(mv, (counts.get(mv) ?? 0) + 1);
	}
	return counts;
}

describe('shapedBotMove', () => {
	it('returns the only move when there is one', () => {
		expect(shapedBotMove([line('e2e4', 0.3, 1)], 800)).toBe('e2e4');
	});

	it('plays best in an EASY position — best towers over the rest', () => {
		// best +5.0 (win ~86%), alternatives ~50% → gap ≫ easyGap ⇒ never gamble
		const lines = [line('d1h5', 5.0, 1), line('b1c3', 0.0, 2), line('a2a3', -0.2, 3)];
		const counts = tally(() => shapedBotMove(lines, 700)); // weakest band
		expect(counts.get('d1h5')).toBe(4000);
	});

	it('plays best when the game is already decided (winning huge)', () => {
		const lines = [line('f3g5', 8.0, 1), line('c1e3', 6.0, 2), line('h2h3', 5.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 800));
		expect(counts.get('f3g5')).toBe(4000);
	});

	it('is spiky: plays best the large majority of moves, slips a minority (weakest band)', () => {
		// best +1.0 (~59%), near-equal alternatives + a real blunder in-window
		const lines = [
			line('g1f3', 1.0, 1), // best  ~59%
			line('b1c3', 0.5, 2), // ~55%  drop ~4.5
			line('d2d4', 0.2, 3), // ~52%  drop ~7
			line('d1h5', -1.5, 4) // ~36%  drop ~23  ← a genuine blunder, allowed but rare
		];
		const counts = tally(() => shapedBotMove(lines, 800));
		// near-perfect most of the time (median move is best) …
		expect(counts.get('g1f3')! / 4000).toBeGreaterThan(0.65);
		// … but it does slip, and the fat tail means the real blunder DOES occur
		// (unlike the old model, a weak human at this level hangs sometimes)
		expect(counts.get('d1h5') ?? 0).toBeGreaterThan(0);
		expect(counts.get('d1h5')! / 4000).toBeLessThan(0.15); // rare
	});

	it('never hangs in an EASY position — blunders cluster in complex ones', () => {
		// best towers (+5 vs 0 ⇒ gap ≫ easyGap): a hanging alternative must never
		// be chosen here, even though the band is weak and slips are allowed.
		const lines = [line('g1f3', 5.0, 1), line('b1c3', 0.0, 2), line('d1h5', -4.0, 3)];
		const counts = tally(() => shapedBotMove(lines, 700));
		expect(counts.get('g1f3')).toBe(4000);
	});

	it('biases toward the smaller slip, but keeps a real tail', () => {
		const lines = [
			line('g1f3', 1.0, 1),
			line('b1c3', 0.7, 2), // small drop
			line('d2d4', -0.5, 3) // bigger drop (still in window)
		];
		const counts = tally(() => shapedBotMove(lines, 800));
		expect((counts.get('b1c3') ?? 0)).toBeGreaterThan(counts.get('d2d4') ?? 0);
	});

	it('plays best the vast majority at club strength (slipProb ~5% by 1500)', () => {
		expect(shapedParams(1500).slipProb).toBeCloseTo(0.05, 5);
		const lines = [line('g1f3', 1.0, 1), line('b1c3', 0.6, 2), line('e2e4', 0.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 1500));
		expect(counts.get('g1f3')! / 4000).toBeGreaterThan(0.9);
	});

	it('converts a forced mate (win 100% ⇒ easy)', () => {
		const lines = [line('d1h5', 0, 1, 1), line('b1c3', 0.2, 2)];
		expect(shapedBotMove(lines, 700)).toBe('d1h5');
	});

	it('weaker bands slip more, give up more, and have a fatter tail', () => {
		expect(shapedParams(800).slipProb).toBeGreaterThan(shapedParams(1200).slipProb);
		expect(shapedParams(800).windowPct).toBeGreaterThan(shapedParams(1200).windowPct);
		// lower tailBias at the weak band ⇒ catastrophes are relatively more common
		expect(shapedParams(800).tailBias).toBeLessThan(shapedParams(1200).tailBias);
	});
});
