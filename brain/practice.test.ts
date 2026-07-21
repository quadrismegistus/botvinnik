import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
	addItem,
	enPassantSetup,
	itemDataFromStoredMove,
	loadItems,
	masteryStats,
	nextItem,
	puzzleDifficulty,
	puzzleSetupMove,
	recordResult,
	type PracticeItem, addItems} from './practice';
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

describe('addItems (the bulk form)', () => {
	// Every field PracticeItem requires. Written out rather than partial: tsc
	// is what catches a short fixture, and `npx vitest run` TRANSPILES without
	// typechecking — a green vitest run says nothing about this, which is how
	// the first version of these tests reached CI.
	const seed = (fen: string) => ({
		fen,
		playedUci: 'e2e4',
		bestUci: 'd2d4',
		playedSan: 'e4',
		bestSan: 'd4',
		drop: 20,
		depth: 22,
		evalBestPawns: 0.3,
		mateBest: null,
		wcBest: 55,
		motifs: [] as string[]
	});

	it('adds many in one pass', () => {
		const next = addItems([], [seed('a'), seed('b')])!;
		expect(next.map((i) => i.fen)).toEqual(['a', 'b']);
	});

	it('skips a fen already collected', () => {
		const first = addItems([], [seed('a')])!;
		const next = addItems(first, [seed('a'), seed('b')])!;
		expect(next.map((i) => i.fen)).toEqual(['a', 'b']);
	});

	it('skips a duplicate WITHIN the batch', () => {
		// addItem could not hit this: one call, one item. A lichess import can
		// easily carry the same position twice.
		const next = addItems([], [seed('a'), seed('a')])!;
		expect(next).toHaveLength(1);
	});

	it('returns null when nothing was added, so the caller can skip persisting',
		() => {
			const first = addItems([], [seed('a')])!;
			expect(addItems(first, [seed('a')])).toBeNull();
			expect(addItems(first, [])).toBeNull();
		});

	it('agrees with addItem on the fields it sets', () => {
		const viaOne = addItem([], seed('a'))!;
		const viaMany = addItems([], [seed('a')])!;
		const strip = (i: (typeof viaOne)[number]) => ({ ...i, createdAt: '', dueAt: '' });
		expect(viaMany.map(strip)).toEqual(viaOne.map(strip));
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

describe('en-passant setup reconstruction', () => {
	it('rebuilds Black&apos;s double push from a rank-6 ep square', () => {
		// after 1.e4 ... c5 2.Nf3 ... and Black just played d7-d5, ep target d6
		expect(enPassantSetup('rnbqkbnr/pp2pppp/8/2ppP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3')).toBe(
			'd7d5'
		);
	});
	it('rebuilds White&apos;s double push from a rank-3 ep square', () => {
		expect(enPassantSetup('rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 2')).toBe(
			'e2e4'
		);
	});
	it('returns null when there is no ep square', () => {
		expect(enPassantSetup('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')).toBeNull();
	});
	it('puzzleSetupMove prefers the stored setup move, falls back to ep', () => {
		const stored = practiceItem({ setupUci: 'g1f3', fen: '8/8/8/8/8/8/8/8 w - - 0 1' });
		expect(puzzleSetupMove(stored)).toBe('g1f3');
		const epOnly = practiceItem({
			setupUci: undefined,
			fen: 'rnbqkbnr/pp2pppp/8/2ppP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3'
		});
		expect(puzzleSetupMove(epOnly)).toBe('d7d5');
	});
});

describe('nextItem randomization', () => {
	// three items all due long ago (equal weight); a controllable RNG lets us
	// prove selection depends on chance, not a fixed order
	const now = 10_000_000;
	const due = [
		practiceItem({ id: 'a', dueAt: new Date(0).toISOString() }),
		practiceItem({ id: 'b', dueAt: new Date(0).toISOString() }),
		practiceItem({ id: 'c', dueAt: new Date(0).toISOString() })
	];

	it('picks different items for different RNG draws (not a fixed order)', () => {
		const first = nextItem(due, undefined, now, undefined, () => 0.0)?.id;
		const last = nextItem(due, undefined, now, undefined, () => 0.99)?.id;
		expect(first).toBe('a');
		expect(last).toBe('c');
	});

	it('over many draws it reaches every due item', () => {
		const seen = new Set<string>();
		for (let k = 0; k < 30; k++) {
			seen.add(nextItem(due, undefined, now, undefined, () => k / 30)!.id);
		}
		expect(seen).toEqual(new Set(['a', 'b', 'c']));
	});

	it('still respects due-first: an item not yet due is never chosen while others are due', () => {
		const mixed = [
			practiceItem({ id: 'due', dueAt: new Date(0).toISOString() }),
			practiceItem({ id: 'later', dueAt: new Date(now + 86_400_000).toISOString() })
		];
		for (let k = 0; k < 20; k++) {
			expect(nextItem(mixed, undefined, now, undefined, () => k / 20)!.id).toBe('due');
		}
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

	it('re-tags items whose motifs predate the current tagger version', () => {
		// Qb3 was tagged 'pin' by the value-blind v1 detector, but the knight
		// behind the pawn is rook-defended — the recomputation must drop it
		const stored = practiceItem({
			id: 'rn5k/8/8/1p6/8/8/8/1Q5K w - - 0 1',
			fen: 'rn5k/8/8/1p6/8/8/8/1Q5K w - - 0 1',
			bestSan: 'Qb3',
			bestUci: 'b1b3',
			bestPv: ['b1b3'],
			motifs: ['pin'] // stale v1 tag, no tagV field
		});
		localStorage.setItem(KEY, JSON.stringify([stored]));

		const loaded = loadItems();
		expect(loaded[0].motifs).not.toContain('pin');
		expect(loaded[0].tagV).toBeGreaterThanOrEqual(2);

		// persisted, so the next load doesn't recompute again
		const raw = JSON.parse(localStorage.getItem(KEY)!);
		expect(raw[0].tagV).toBeGreaterThanOrEqual(2);
	});
});

describe('puzzleDifficulty', () => {
	it('rates a fresh big blunder or a tactical motif as easy', () => {
		expect(puzzleDifficulty(practiceItem({ drop: 30 }))).toBe('easy');
		expect(puzzleDifficulty(practiceItem({ drop: 15, motifs: ['free capture'] }))).toBe('easy');
	});
	it('rates a subtle fresh drop with no motif as hard', () => {
		expect(puzzleDifficulty(practiceItem({ drop: 6 }))).toBe('hard');
	});
	it('lets personal history override position features', () => {
		// nailed it repeatedly → easy despite a subtle drop
		expect(
			puzzleDifficulty(practiceItem({ drop: 6, attempts: 4, correct: 4, box: 3 }))
		).toBe('easy');
		// keeps failing → hard despite a big drop
		expect(
			puzzleDifficulty(practiceItem({ drop: 30, attempts: 3, correct: 0, lastResult: 'fail' }))
		).toBe('hard');
	});
});

describe('masteryStats', () => {
	it('buckets items into mastered / learning / fresh', () => {
		const s = masteryStats([
			practiceItem({ id: 'a', attempts: 0 }), // fresh
			practiceItem({ id: 'b', attempts: 2, box: 1 }), // learning
			practiceItem({ id: 'c', attempts: 4, box: 3 }) // mastered
		]);
		expect(s).toEqual({ fresh: 1, learning: 1, mastered: 1, total: 3 });
	});
});
