import { describe, expect, it } from 'vitest';
import { confidences, unifyMoves, type ExplorerPosition } from './explorer';
import type { EngineMove } from './engine/types';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

function line(uci: string, score: number, mate: number | null = null, multipv = 1): EngineMove {
	return { pv: [uci], score, mate, depth: 20, multipv };
}

/** A book node in the shape book.json stores: counts, never percentages. */
function book(
	total: number,
	moves: [uci: string, san: string, w: number, d: number, b: number][]
): ExplorerPosition {
	return {
		total,
		moves: moves.map(([uci, san, white, draws, black]) => ({ uci, san, white, draws, black }))
	};
}

describe('confidences', () => {
	it('is empty for no lines, and certain about the only line', () => {
		expect(confidences([])).toEqual([]);
		expect(confidences([line('e2e4', 0.3)])).toEqual([100]);
	});

	it('normalises to 100 across the lines', () => {
		const c = confidences([line('e2e4', 0.5), line('d2d4', 0.2), line('g1f3', -0.4)]);
		expect(c.reduce((a, b) => a + b, 0)).toBeCloseTo(100, 9);
		// and it is ordered by evaluation, which is the whole claim
		expect(c[0]).toBeGreaterThan(c[1]);
		expect(c[1]).toBeGreaterThan(c[2]);
	});

	it('is a softmax at one pawn: a pawn apart is about 73/27', () => {
		const [best, other] = confidences([line('e2e4', 1), line('d2d4', 0)]);
		expect(best).toBeCloseTo((Math.E / (Math.E + 1)) * 100, 9);
		expect(best).toBeCloseTo(73.1, 1);
		expect(other).toBeCloseTo(26.9, 1);
	});

	it('clamps at ±15 pawns, so a won position is not reported as certainty', () => {
		// +100 and +50 are both "winning by any road" — without the clamp the
		// first exponentiates to everything and the second rounds to 0%.
		expect(confidences([line('e2e4', 100), line('d2d4', 50)])).toEqual([50, 50]);
		expect(confidences([line('e2e4', -50), line('d2d4', -100)])).toEqual([50, 50]);
	});

	it('puts a mate above any evaluation, and a closer mate above a further one', () => {
		const [mate, huge] = confidences([line('e2e4', 0, 5), line('d2d4', 99)]);
		expect(mate).toBeGreaterThan(99.99);
		expect(huge).toBeLessThan(0.01);

		const [near, far] = confidences([line('e2e4', 0, 1), line('d2d4', 0, 8)]);
		expect(near / far).toBeCloseTo(Math.exp(7), 3); // 39 vs 32 on the mate scale
		expect(near).toBeGreaterThan(99.9);

		// mate in 20 is the floor — further mates are all worth the same, and
		// still beat the +15 clamp
		const [m20, m40] = confidences([line('e2e4', 0, 20), line('d2d4', 0, 40)]);
		expect(m20).toBeCloseTo(m40, 9);
		expect(confidences([line('e2e4', 0, 40), line('d2d4', 15)])[0]).toBeGreaterThan(99);
	});

	it('sinks a mate AGAINST the mover below every evaluation', () => {
		const [mated, bad] = confidences([line('e2e4', 0, -3), line('d2d4', -15)]);
		expect(mated).toBeLessThan(bad);
		expect(bad).toBeGreaterThan(99.99);
	});
});

describe('unifyMoves', () => {
	const lichess = book(1600, [
		['e2e4', 'e4', 400, 200, 400], // 1000 games, 40/20/40
		['d2d4', 'd4', 300, 100, 100] //   500 games, 60/20/20
	]);

	it('sorts by popularity and drops engine-only moves to the bottom', () => {
		// the engine's own order is g1f3, e2e4, b1c3 — nothing like the book's
		const rows = unifyMoves(
			START,
			[line('g1f3', 0.4, null, 1), line('e2e4', 0.3, null, 2), line('b1c3', 0.1, null, 3)],
			lichess,
			null
		);
		expect(rows.map((r) => r.san)).toEqual(['e4', 'd4', 'Nf3', 'Nc3']);
		// the two with no games keep ENGINE rank at the bottom, not book rank
		expect(rows[2].engine!.score).toBeGreaterThan(rows[3].engine!.score);
		expect(rows[2].lichess).toBeUndefined();
		expect(rows[3].lichess).toBeUndefined();
	});

	it('merges a move both sources have into ONE row', () => {
		const rows = unifyMoves(START, [line('e2e4', 0.3)], lichess, null);
		expect(rows.filter((r) => r.uci === 'e2e4')).toHaveLength(1);
		const e4 = rows[0];
		expect(e4.engine).toEqual({ score: 0.3, mate: null, confidence: 100 });
		expect(e4.lichess).toEqual({ games: 1000, pct: 62.5, white: 40, draws: 20, black: 40 });
	});

	it('reports shares, not counts: pct of the position, W/D/L of the move', () => {
		const rows = unifyMoves(START, [], lichess, null);
		expect(rows.map((r) => r.lichess!.pct)).toEqual([62.5, 31.25]); // 1000/1600, 500/1600
		expect(rows[1].lichess).toEqual({ games: 500, pct: 31.25, white: 60, draws: 20, black: 20 });
		// the shares of one move's own games always total 100
		for (const r of rows) {
			expect(r.lichess!.white + r.lichess!.draws + r.lichess!.black).toBeCloseTo(100, 9);
		}
	});

	it('skips a book move with no games rather than dividing by zero', () => {
		const rows = unifyMoves(START, [], book(1000, [['a2a3', 'a3', 0, 0, 0]]), null);
		expect(rows).toEqual([]);
	});

	it('survives a node whose total is zero', () => {
		const rows = unifyMoves(START, [], book(0, [['e2e4', 'e4', 1, 0, 1]]), null);
		expect(rows[0].lichess).toEqual({ games: 2, pct: 0, white: 50, draws: 0, black: 50 });
	});

	it('names engine moves through chess.js and book moves from the book', () => {
		const rows = unifyMoves(START, [line('g1f3', 0.4)], lichess, null);
		expect(rows.map((r) => r.san)).toEqual(['e4', 'd4', 'Nf3']);
		// an illegal move still gets a row — the uci stands in for the san
		expect(unifyMoves(START, [line('e2e5', 0)], null, null)[0].san).toBe('e2e5');
	});

	it('keeps one row per move when the engine repeats itself', () => {
		const rows = unifyMoves(START, [line('e2e4', 0.9, null, 1), line('e2e4', 0.1, null, 2)], null, null);
		expect(rows).toHaveLength(1);
		expect(rows[0].engine!.score).toBe(0.9); // the first (better-ranked) line wins
	});

	it('ranks by masters when that is the only book with the move', () => {
		const masters = book(200, [['c2c4', 'c4', 60, 20, 20]]); // 100 games
		const rows = unifyMoves(START, [], book(1600, [['d2d4', 'd4', 30, 10, 10]]), masters);
		// 100 masters games outranks 50 lichess games
		expect(rows.map((r) => r.san)).toEqual(['c4', 'd4']);
		expect(rows[0].masters!.games).toBe(100);
		expect(rows[0].lichess).toBeUndefined();
	});

	it('is engine-order alone when there is no book at all', () => {
		const rows = unifyMoves(
			START,
			[line('g1f3', 0.4, null, 1), line('e2e4', 0.3, null, 2)],
			null,
			null
		);
		expect(rows.map((r) => r.san)).toEqual(['Nf3', 'e4']);
		expect(rows.map((r) => r.engine!.confidence).reduce((a, b) => a + b, 0)).toBeCloseTo(100, 9);
	});
});
