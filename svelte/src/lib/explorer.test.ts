import { describe, expect, it } from 'vitest';
import { confidences, formatGames, unifyMoves, type ExplorerPosition } from './explorer';
import type { EngineMove } from './engine/stockfish';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const line = (uci: string, score: number, multipv: number, mate: number | null = null): EngineMove => ({
	pv: [uci],
	score,
	mate,
	depth: 20,
	multipv
});

const book = (
	moves: { uci: string; san: string; w: number; d: number; b: number }[]
): ExplorerPosition => {
	const total = moves.reduce((s, m) => s + m.w + m.d + m.b, 0);
	return {
		total,
		moves: moves.map((m) => ({ uci: m.uci, san: m.san, white: m.w, draws: m.d, black: m.b })),
		opening: null
	};
};

describe('confidences', () => {
	it('sums to 100 and ranks better moves higher', () => {
		const c = confidences([line('e2e4', 0.36, 1), line('g1f3', 0.23, 2), line('b1a3', -1.5, 3)]);
		expect(c.reduce((a, b) => a + b, 0)).toBeCloseTo(100, 5);
		expect(c[0]).toBeGreaterThan(c[1]);
		expect(c[1]).toBeGreaterThan(c[2]);
	});

	it('a mate dominates any cp score, and closer mates dominate further ones', () => {
		const c = confidences([line('a1a2', 0, 1, 2), line('b1b2', 0, 2, 8), line('c1c2', 14, 3)]);
		expect(c[0]).toBeGreaterThan(90);
		expect(c[0]).toBeGreaterThan(c[1]);
		expect(c[1]).toBeGreaterThan(c[2]);
	});

	it('clamps huge cp gaps instead of overflowing', () => {
		const c = confidences([line('a1a2', 99, 1), line('b1b2', -99, 2)]);
		expect(c[0]).toBeGreaterThan(99);
		expect(Number.isFinite(c[1])).toBe(true);
	});
});

describe('unifyMoves', () => {
	const engine = [line('e2e4', 0.36, 1), line('g1f3', 0.23, 2), line('a2a3', -0.4, 3)];
	const lichess = book([
		{ uci: 'e2e4', san: 'e4', w: 500, d: 100, b: 400 },
		{ uci: 'd2d4', san: 'd4', w: 300, d: 100, b: 200 }
	]);
	const masters = book([{ uci: 'd2d4', san: 'd4', w: 40, d: 50, b: 10 }]);

	it('unions engine and book moves; book popularity sorts first, engine-only rows keep rank order at the bottom', () => {
		const rows = unifyMoves(START, engine, lichess, masters);
		expect(rows.map((r) => r.san)).toEqual(['e4', 'd4', 'Nf3', 'a3']);
	});

	it('computes pct of position total and per-move W/D/L shares', () => {
		const rows = unifyMoves(START, engine, lichess, masters);
		const e4 = rows.find((r) => r.san === 'e4')!;
		expect(e4.lichess!.games).toBe(1000);
		expect(e4.lichess!.pct).toBeCloseTo(62.5); // 1000 of 1600
		expect(e4.lichess!.white).toBeCloseTo(50);
		expect(e4.lichess!.draws).toBeCloseTo(10);
		expect(e4.lichess!.black).toBeCloseTo(40);
		expect(e4.engine!.confidence).toBeGreaterThan(0);
		expect(e4.masters).toBeUndefined();
	});

	it('book-only moves get SAN from the API and no engine cell', () => {
		const rows = unifyMoves(START, engine, lichess, null);
		const d4 = rows.find((r) => r.san === 'd4')!;
		expect(d4.engine).toBeUndefined();
		expect(d4.lichess!.games).toBe(600);
	});

	it('derives SAN for engine-only moves', () => {
		const rows = unifyMoves(START, [line('b1c3', 0.1, 1)], null, null);
		expect(rows[0].san).toBe('Nc3');
	});

	it('handles both books missing (engine only) and empty everything', () => {
		expect(unifyMoves(START, engine, null, null)).toHaveLength(3);
		expect(unifyMoves(START, [], null, null)).toHaveLength(0);
	});
});

describe('formatGames', () => {
	it('abbreviates counts', () => {
		expect(formatGames(987)).toBe('987');
		expect(formatGames(45300)).toBe('45k');
		expect(formatGames(1234567)).toBe('1.2M');
		expect(formatGames(2_500_000_000)).toBe('2.5B');
	});
});
