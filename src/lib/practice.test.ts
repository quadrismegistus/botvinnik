import { describe, expect, it } from 'vitest';
import { addItem, itemDataFromStoredMove } from './practice';
import { winChance } from './engine/insights';
import type { StoredMove } from './gameStore';

function move(overrides: Partial<StoredMove> = {}): StoredMove {
	return {
		ply: 7,
		san: 'Nf6',
		uci: 'g8f6',
		color: 'w',
		fenBefore: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
		fenAfter: 'rnbqkb1r/pppppppp/5n2/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 1 2',
		evalPawns: -0.5,
		mate: null,
		pctBest: 40,
		wcDrop: 12,
		label: 'mistake',
		bestSan: 'e5',
		bestUci: 'e7e5',
		...overrides
	};
}

describe('itemDataFromStoredMove', () => {
	it('returns null without a best move', () => {
		expect(itemDataFromStoredMove(move({ bestUci: undefined }))).toBeNull();
		expect(itemDataFromStoredMove(move({ bestSan: undefined }))).toBeNull();
		expect(itemDataFromStoredMove(move({ fenBefore: '' }))).toBeNull();
		expect(itemDataFromStoredMove(move({ wcDrop: 0 }))).toBeNull();
	});

	it('produces consistent fields for a mistake', () => {
		const m = move();
		const data = itemDataFromStoredMove(m)!;
		expect(data).not.toBeNull();
		expect(data.fen).toBe(m.fenBefore);
		expect(data.playedSan).toBe('Nf6');
		expect(data.playedUci).toBe('g8f6');
		expect(data.bestSan).toBe('e5');
		expect(data.bestUci).toBe('e7e5');
		expect(data.bestPv).toEqual(['e7e5']);
		expect(data.mateBest).toBeNull();
		expect(data.drop).toBe(12);
		expect(data.depth).toBe(22);

		// win chance of the best move = after-move win chance + the drop
		const wcAfter = winChance(m.evalPawns, m.mate);
		expect(data.wcBest).toBeCloseTo(wcAfter + m.wcDrop, 5);

		// the inverted eval round-trips back through the sigmoid to wcBest
		expect(winChance(data.evalBestPawns, null)).toBeCloseTo(data.wcBest, 0);
		expect(Math.abs(winChance(data.evalBestPawns, null) - data.wcBest)).toBeLessThan(1);
	});

	it('clamps wcBest into [0, 100]', () => {
		const data = itemDataFromStoredMove(move({ evalPawns: 12, wcDrop: 30 }))!;
		expect(data.wcBest).toBeLessThanOrEqual(100);
		expect(data.evalBestPawns).toBeLessThanOrEqual(15);
	});
});

describe('addItem', () => {
	it('dedupes by fen', () => {
		const data = itemDataFromStoredMove(move())!;
		const once = addItem([], data)!;
		expect(once).toHaveLength(1);
		expect(addItem(once, data)).toBeNull();
	});
});
