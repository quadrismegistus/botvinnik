import { describe, it, expect } from 'vitest';
import { shapedBotMove, shapedParams, shapedLabelFor, shapedSearchDepth } from './bot';
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

// A clearly tactical position: best +5.0 (~86% win) towers over ~50% alternatives.
const TACTICAL = [line('d1h5', 5.0, 1), line('b1c3', 0.0, 2), line('a2a3', -0.2, 3)];

describe('shapedBotMove', () => {
	it('returns the only move when there is one', () => {
		expect(shapedBotMove([line('e2e4', 0.3, 1)], 800)).toBe('e2e4');
	});

	it('sees the tactic almost always at strong bands', () => {
		const counts = tally(() => shapedBotMove(TACTICAL, 1900));
		// missProb floors at 4% above 1600
		expect(counts.get('d1h5')! / 4000).toBeGreaterThan(0.9);
	});

	it('MISSES the tactic a real fraction of the time at weak bands', () => {
		// This is the inversion of the old model: tactical positions are where
		// the weak bot blunders, not where it is protected.
		const counts = tally(() => shapedBotMove(TACTICAL, 600));
		const bestRate = counts.get('d1h5')! / 4000;
		expect(bestRate).toBeGreaterThan(0.3); // still sees it a fair amount
		expect(bestRate).toBeLessThan(0.55); // …but misses ~60% of the time
		expect(counts.get('b1c3') ?? 0).toBeGreaterThan(0); // and plays on obliviously
	});

	it('a miss picks the plausible-looking alternative, catastrophe possible but rare', () => {
		// When it misses +5.0, it should usually play the reasonable 0.0 move;
		// the outright lost move is possible (no severity cap on misses) but rare.
		const lines = [line('d1h5', 5.0, 1), line('b1c3', 0.0, 2), line('h2h4', -4.0, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('b1c3') ?? 0).toBeGreaterThan(counts.get('h2h4') ?? 0);
	});

	it('fails to punish too — a hanging piece is just a tactic from our side', () => {
		// Opponent hung a queen: capturing is +9, everything else ~equal. A real
		// beginner sometimes doesn't notice. The old model ALWAYS captured (its
		// easy-gap gate forced best) which is why it crushed numeric-900 100-0.
		const lines = [line('d1d8', 9.0, 1), line('g1f3', 0.1, 2), line('b1c3', 0.0, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('g1f3') ?? 0).toBeGreaterThan(0);
	});

	it('quiet positions: mushy sound play — spreads over near-equal moves', () => {
		const lines = [line('g1f3', 0.5, 1), line('b1c3', 0.3, 2), line('d2d4', 0.1, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		// samples all of the close moves, not locked to best
		expect(counts.size).toBe(3);
		expect(counts.get('g1f3')! / 4000).toBeLessThan(0.9);
	});

	it('never plays a howler in a QUIET position (window excludes it)', () => {
		// All reasonable moves are close; d1h5 hangs (-4.5 ⇒ drop ≈ 39% > window 30).
		// Quiet howlers are what made the old softmax sampler feel broken.
		const lines = [
			line('g1f3', 0.5, 1),
			line('b1c3', 0.3, 2),
			line('d1h5', -4.5, 3)
		];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('d1h5')).toBeUndefined();
	});

	it('quiet play sharpens with ELO (temperature ramp)', () => {
		const lines = [line('g1f3', 0.5, 1), line('b1c3', 0.2, 2), line('d2d4', 0.0, 3)];
		const weak = tally(() => shapedBotMove(lines, 600));
		const strong = tally(() => shapedBotMove(lines, 1600));
		expect(strong.get('g1f3')! / 4000).toBeGreaterThan(weak.get('g1f3')! / 4000);
	});

	it('won positions: sloppy but DIRECTIONAL conversion, not perfect play', () => {
		// +8 vs +6 vs +5.5 all saturate near 95% win. Progress mode samples over
		// the unclamped evals: usually the most-winning move, but spread — not
		// the old perfect-conversion superpower, not an aimless shuffle either.
		const lines = [line('f3g5', 8.0, 1), line('c1e3', 6.0, 2), line('h2h3', 5.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.size).toBeGreaterThan(1); // still imperfect
		expect(counts.get('f3g5')! / 4000).toBeGreaterThan(0.4); // but directional
	});

	it('converts toward mate instead of shuffling, even at the weakest band', () => {
		// mate-in-3 vs +9 cp: in win% both read ~95-100 (the 118-move Q-vs-K+P
		// repetition draw). Progress mode scores the mate line by mate distance,
		// so the bot heads for it.
		const lines = [line('d1h5', 0, 1, 3), line('f3g5', 9.0, 2), line('h2h3', 8.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('d1h5')! / 4000).toBeGreaterThan(0.9);
	});

	it('progress mode never gambles the win itself away', () => {
		// Genuine conversion: several winning moves (+9, +8) and one that throws
		// it all away (+0.5 ⇒ ~equal). The throwaway is outside the keep-the-win
		// window and must never be sampled, even at the weakest band.
		const lines = [line('f3g5', 9.0, 1), line('c1e3', 8.0, 2), line('g1f3', 0.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('g1f3')).toBeUndefined();
		expect(counts.size).toBe(2); // both winning moves get play
	});

	it('a single winning move is a TACTIC, not a conversion — missable', () => {
		// +9 vs +0.5: only one move keeps the win, so this is see-it-or-miss-it —
		// the weak bot must sometimes fail to convert by missing it (that's the
		// human blunder), NOT auto-play it via progress mode.
		const lines = [line('f3g5', 9.0, 1), line('g1f3', 0.5, 2)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.get('g1f3') ?? 0).toBeGreaterThan(0);
	});

	it('takes a forced mate reliably at strong bands', () => {
		const lines = [line('d1h5', 0, 1, 1), line('f3g5', 8.0, 2)];
		const counts = tally(() => shapedBotMove(lines, 1600));
		expect(counts.get('d1h5')! / 4000).toBeGreaterThan(0.9);
	});

	it('sticky misses: with a seed, the same tactic stays seen or unseen all game', () => {
		// Without a seed the per-move re-roll makes eventually-capturing a hanging
		// piece a certainty; with a per-game seed the decision is a function of
		// (seed, focal square) — miss it once, stay blind while it sits there.
		const decide = (seed: string) =>
			shapedBotMove(TACTICAL, 600, undefined, seed) === 'd1h5' ? 'sees' : 'blind';
		for (const seed of ['g1', 'g2', 'g3', 'g4', 'g5']) {
			const first = decide(seed);
			for (let i = 0; i < 20; i++) expect(decide(seed)).toBe(first); // stable within a game
		}
		// …and across many games the miss rate still reflects missProb (~60% at 600)
		const games = 400;
		let blind = 0;
		for (let g = 0; g < games; g++) if (decide(`game-${g}`) === 'blind') blind++;
		expect(blind / games).toBeGreaterThan(0.45);
		expect(blind / games).toBeLessThan(0.75);
	});

	it('weaker bands miss more and play mushier', () => {
		expect(shapedParams(600).missProb).toBeGreaterThan(shapedParams(1000).missProb);
		expect(shapedParams(1000).missProb).toBeGreaterThan(shapedParams(1600).missProb);
		expect(shapedParams(600).temperature).toBeGreaterThan(shapedParams(1600).temperature);
		expect(shapedParams(600).quietWindowPct).toBeGreaterThan(shapedParams(1600).quietWindowPct);
	});
});

describe('shapedLabelFor', () => {
	it('inverts the measured curve at the knots', () => {
		expect(shapedLabelFor(770)).toBe(600);
		expect(shapedLabelFor(1330)).toBe(1200);
		expect(shapedLabelFor(1935)).toBe(1500);
	});

	it('interpolates between knots and clamps outside the measured range', () => {
		// halfway 1000→1156 strength ⇒ halfway 900→1050 label
		expect(shapedLabelFor(1078)).toBe(975);
		expect(shapedLabelFor(200)).toBe(600); // below floor
		expect(shapedLabelFor(2500)).toBe(1500); // above ceiling
	});

	it('is monotonic across the covered range', () => {
		let prev = -Infinity;
		for (let e = 800; e <= 2000; e += 50) {
			const l = shapedLabelFor(e);
			expect(l).toBeGreaterThanOrEqual(prev);
			prev = l;
		}
	});
});

describe('shapedSearchDepth', () => {
	it('ramps 4→12 over labels 600→1500 (must match the harness)', () => {
		expect(shapedSearchDepth(600)).toBe(4);
		expect(shapedSearchDepth(1050)).toBe(8);
		expect(shapedSearchDepth(1500)).toBe(12);
		expect(shapedSearchDepth(2000)).toBe(12); // capped
	});
});
