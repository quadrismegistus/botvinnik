import { describe, expect, it } from 'vitest';
import type { EngineMove } from './stockfish';
import { backfillGrade, gradeMove, winChance, whitePovWinChance } from './insights';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

function line(uci: string, score: number, multipv: number, mate: number | null = null): EngineMove {
	return { pv: [uci], score, mate, depth: 20, multipv };
}

// pre-move analysis of the start position: e4 best, then d4/Nf3/c4/e3
const LINES = [
	line('e2e4', 0.3, 1),
	line('d2d4', 0.25, 2),
	line('g1f3', 0.2, 3),
	line('c2c4', 0.15, 4),
	line('e2e3', 0.1, 5)
];

describe('winChance', () => {
	it('is 50% at equality and clamps at mates', () => {
		expect(winChance(0, null)).toBe(50);
		expect(winChance(null, 3)).toBe(100);
		expect(winChance(null, -1)).toBe(0);
	});

	it('is monotonic in the eval', () => {
		expect(winChance(1, null)).toBeGreaterThan(winChance(0, null));
		expect(winChance(-1, null)).toBeLessThan(winChance(0, null));
		// lichess constant: +1 pawn ≈ 59%
		expect(winChance(1, null)).toBeCloseTo(59.1, 0);
	});
});

describe('whitePovWinChance', () => {
	it("keeps White's evals as-is and flips Black's", () => {
		// +1 pawn for the mover ≈ 59%
		expect(whitePovWinChance('w', 1, null)).toBeCloseTo(59.1, 0);
		// same eval from Black's move is White losing ≈ 41%
		expect(whitePovWinChance('b', 1, null)).toBeCloseTo(40.9, 0);
	});

	it('flips mates by the mover', () => {
		expect(whitePovWinChance('w', null, 2)).toBe(100);
		expect(whitePovWinChance('b', null, 2)).toBe(0);
	});
});

describe('gradeMove', () => {
	it('marks the top engine line as best', () => {
		const g = gradeMove(1, START, 'e4', 'e2e4', 'w', LINES)!;
		expect(g.isBest).toBe(true);
		expect(g.rank).toBe(1);
		expect(g.pctBest).toBe(100);
		expect(g.bestSan).toBe('e4');
	});

	it('flags moves outside the MultiPV list', () => {
		const g = gradeMove(1, START, 'a4', 'a2a4', 'w', LINES)!;
		expect(g.offList).toBe(true);
		expect(g.evalPawns).toBeNull();
	});
});

describe('backfillGrade labels', () => {
	it('labels the best move as best', () => {
		const g = gradeMove(1, START, 'e4', 'e2e4', 'w', LINES)!;
		// child position (after e4), opponent's perspective: -0.3 = same eval negated
		const done = backfillGrade(g, [line('e7e5', -0.3, 1)]);
		expect(done.label).toBe('best');
		expect(done.evalPawns).toBeCloseTo(0.3);
	});

	it('labels a large win-chance drop as blunder', () => {
		const g = gradeMove(1, START, 'a4', 'a2a4', 'w', LINES)!;
		// child search says the opponent is now +5 — a ~40% win-chance drop
		const done = backfillGrade(g, [line('e7e5', 5, 1)]);
		expect(done.label).toBe('blunder');
		expect(done.evalPawns).toBeCloseTo(-5);
		expect(done.rank).toBe(6); // worse than all five pre-move lines
	});

	it('labels a small drop as inaccuracy', () => {
		const g = gradeMove(1, START, 'a4', 'a2a4', 'w', LINES)!;
		// ~ -0.55 pawns => ~8% drop from +0.3
		const done = backfillGrade(g, [line('e7e5', 0.55, 1)]);
		expect(done.label).toBe('inaccuracy');
	});

	it('labels a missed material-winning capture as miss', () => {
		// Rd2 can take the hanging queen on d8 (best); instead it plays Rd7,
		// leaving the position roughly equal — a missed capture, still ok
		const fen = 'k2q4/8/8/8/8/8/3R4/K7 w - - 0 1';
		const lines = [line('d2d8', 8, 1), line('d2d7', 0, 2)];
		const g = gradeMove(1, fen, 'Rd7', 'd2d7', 'w', lines)!;
		// after Rd7 the position is ~equal (Black's perspective ~0)
		const done = backfillGrade(g, [line('d8a5', 0, 1)]);
		expect(done.label).toBe('miss');
	});

	it('does not call it a miss when the missed best move is not a capture', () => {
		// same drop, but the best move (a4) captures nothing → plain blunder/mistake
		const g = gradeMove(1, START, 'a3', 'a2a3', 'w', LINES)!;
		const done = backfillGrade(g, [line('e7e5', 5, 1)]);
		expect(done.label).not.toBe('miss');
	});
});
