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

	it('never plays a free-hang (a move outside the win% window) even at the weakest band', () => {
		// best +1.0 (~59%), two near-equal alternatives (in-window), one blunder
		// that drops ~34% win → outside the ~32% window at ELO 800 ⇒ excluded.
		const lines = [
			line('g1f3', 1.0, 1), // best  ~59%
			line('b1c3', 0.5, 2), // ~55%  drop ~4.5
			line('d2d4', 0.2, 3), // ~52%  drop ~7
			line('d1h5', -3.0, 4) // ~25%  drop ~34  ← hanging move, must never appear
		];
		const counts = tally(() => shapedBotMove(lines, 800));
		expect(counts.get('d1h5')).toBeUndefined();
		// it does gamble sometimes (coherent, not deterministic) and it does keep
		// playing best a large share of the time (anti-swing)
		expect(counts.get('g1f3')!).toBeGreaterThan(1200);
		expect(counts.get('g1f3')!).toBeLessThan(3600);
		expect((counts.get('b1c3') ?? 0) + (counts.get('d2d4') ?? 0)).toBeGreaterThan(400);
	});

	it('biases toward the smaller mistake when it errs', () => {
		const lines = [
			line('g1f3', 1.0, 1),
			line('b1c3', 0.7, 2), // small drop
			line('d2d4', -0.5, 3) // bigger drop (still in window)
		];
		const counts = tally(() => shapedBotMove(lines, 800));
		expect((counts.get('b1c3') ?? 0)).toBeGreaterThan(counts.get('d2d4') ?? 0);
	});

	it('plays pure best at club strength (blunderProb 0 by ~1500)', () => {
		expect(shapedParams(1500).blunderProb).toBe(0);
		const lines = [line('g1f3', 0.3, 1), line('b1c3', 0.25, 2), line('e2e4', 0.2, 3)];
		const counts = tally(() => shapedBotMove(lines, 1500));
		expect(counts.get('g1f3')).toBe(4000);
	});

	it('converts a forced mate (win 100% ⇒ easy)', () => {
		const lines = [line('d1h5', 0, 1, 1), line('b1c3', 0.2, 2)];
		expect(shapedBotMove(lines, 700)).toBe('d1h5');
	});

	it('weaker bands gamble more and give up more', () => {
		expect(shapedParams(800).blunderProb).toBeGreaterThan(shapedParams(1200).blunderProb);
		expect(shapedParams(800).windowPct).toBeGreaterThan(shapedParams(1200).windowPct);
	});
});
