import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
	addItem,
	itemDataFromStoredMove,
	loadItems,
	nextItem,
	recordResult,
	type PracticeItem
} from './practice';
import { winChance } from './engine/insights';
import type { StoredMove } from './gameStore';

function practiceItem(overrides: Partial<PracticeItem> = {}): PracticeItem {
	return {
		id: 'a',
		fen: '4k3/8/8/4r3/8/8/8/4K3 w - - 0 1',
		playedSan: 'Kd1',
		playedUci: 'e1d1',
		bestSan: 'Ke2',
		bestUci: 'e1e2',
		bestPv: ['e1e2'],
		evalBestPawns: 0,
		mateBest: null,
		wcBest: 50,
		drop: 10,
		depth: 20,
		createdAt: new Date(0).toISOString(),
		box: 0,
		dueAt: new Date(0).toISOString(), // due long ago
		attempts: 0,
		correct: 0,
		...overrides
	};
}

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

describe('itemDataFromStoredMove motifs', () => {
	it('tags the best line with its motifs', () => {
		// black rook on e5 is undefended; the best move captures it for free
		const data = itemDataFromStoredMove(
			move({
				fenBefore: '4k3/8/8/Q3r3/8/8/8/4K3 w - - 0 1',
				bestSan: 'Qxe5',
				bestUci: 'a5e5'
			})
		)!;
		expect(data.motifs).toContain('free capture');
	});
});

describe('nextItem motif filter', () => {
	const items = [
		practiceItem({ id: 'p', fen: 'p', motifs: ['pin'] }),
		practiceItem({ id: 'f', fen: 'f', motifs: ['fork'] }),
		practiceItem({ id: 'n', fen: 'n', motifs: [] })
	];

	it('returns only items carrying the requested motif', () => {
		expect(nextItem(items, undefined, Date.now(), 'pin')?.id).toBe('p');
		expect(nextItem(items, undefined, Date.now(), 'fork')?.id).toBe('f');
	});

	it('returns null when no item has the motif', () => {
		expect(nextItem(items, undefined, Date.now(), 'skewer')).toBeNull();
	});

	it('ignores motifs when none is passed', () => {
		expect(nextItem(items, undefined, Date.now())).not.toBeNull();
	});
});

describe('recordResult hinted credit', () => {
	it('holds the box on a hinted pass but still counts the attempt', () => {
		const items = [practiceItem({ id: 'x', box: 2, attempts: 3, correct: 2 })];
		const next = recordResult(items, 'x', true, true);
		expect(next[0].box).toBe(2); // unchanged — the hint took the credit
		expect(next[0].attempts).toBe(4);
		expect(next[0].correct).toBe(3);
		expect(next[0].lastResult).toBe('pass');
	});

	it('promotes on a cold (un-hinted) pass', () => {
		const items = [practiceItem({ id: 'x', box: 2 })];
		expect(recordResult(items, 'x', true, false)[0].box).toBe(3);
		expect(recordResult(items, 'x', true)[0].box).toBe(3); // default is un-hinted
	});

	it('resets to box 0 on a failure regardless of hints', () => {
		const items = [practiceItem({ id: 'x', box: 3 })];
		expect(recordResult(items, 'x', false, true)[0].box).toBe(0);
		expect(recordResult(items, 'x', false, false)[0].box).toBe(0);
	});
});

describe('loadItems motif backfill', () => {
	const KEY = 'botvinnik-practice-v1';

	class MemStorage {
		private store = new Map<string, string>();
		getItem(k: string) {
			return this.store.has(k) ? this.store.get(k)! : null;
		}
		setItem(k: string, v: string) {
			this.store.set(k, String(v));
		}
		removeItem(k: string) {
			this.store.delete(k);
		}
		clear() {
			this.store.clear();
		}
	}

	beforeEach(() => {
		(globalThis as { localStorage?: Storage }).localStorage = new MemStorage() as unknown as Storage;
	});
	afterEach(() => {
		delete (globalThis as { localStorage?: Storage }).localStorage;
	});

	it('computes and persists motifs for items missing them', () => {
		// stored item predating motif tagging — no `motifs` field
		const stored = practiceItem({
			id: '4k3/8/8/Q3r3/8/8/8/4K3 w - - 0 1',
			fen: '4k3/8/8/Q3r3/8/8/8/4K3 w - - 0 1',
			bestSan: 'Qxe5',
			bestUci: 'a5e5',
			bestPv: ['a5e5']
		});
		delete stored.motifs;
		localStorage.setItem(KEY, JSON.stringify([stored]));

		const loaded = loadItems();
		expect(loaded[0].motifs).toContain('free capture');

		// the backfill was written back, so a fresh read already has it
		const raw = JSON.parse(localStorage.getItem(KEY)!);
		expect(raw[0].motifs).toContain('free capture');
	});
});
