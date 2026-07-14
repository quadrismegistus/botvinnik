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

	it('no conversion gate: even winning positions get mushy play at weak bands', () => {
		// +8 vs +6 vs +5.5 all saturate near 95% win ⇒ reads as quiet ⇒ sampled.
		// The old model forced best here (decided-position gate), which made every
		// won game a perfect depth-12 conversion — a beginner superpower.
		const lines = [line('f3g5', 8.0, 1), line('c1e3', 6.0, 2), line('h2h3', 5.5, 3)];
		const counts = tally(() => shapedBotMove(lines, 600));
		expect(counts.size).toBeGreaterThan(1);
	});

	it('takes a forced mate reliably at strong bands', () => {
		// mate (win 100) vs +8 (win ~95): gap ~5 ⇒ quiet, but at 1600 the low
		// temperature makes the mate the overwhelming choice.
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
