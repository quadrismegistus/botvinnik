import { Chess } from 'chess.js';
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
	type PracticeItem, addItems, migratePracticeItems} from './practice';
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
	it('carries the best line\'s mate distance through, rather than null', () => {
		// The grade has always known this and storage used to drop it (#283), so
		// the tagger saw every position as one where nothing forced mate.
		const withMate = itemDataFromStoredMove(move({ bestMate: 2 }));
		expect(withMate?.mateBest).toBe(2);
		expect(itemDataFromStoredMove(move())?.mateBest).toBeNull();
	});

	it('tags a quiet move that forces mate as mate, not as a positional fact', () => {
		// Rd5 is quiet, gives no check, and forces mate in two. Collected with
		// mate: null it was filed under "open file" — which the tier-1 hint then
		// says out loud on a mating puzzle. The control below is the same
		// position with the mate distance withheld, which is what used to reach
		// the tagger and is why the tag was wrong rather than merely missing.
		const mating = {
			fenBefore: '5B2/2P5/8/1P4R1/5k2/4p3/p3P1K1/B2R2N1 w - - 3 75',
			fenAfter: '5B2/2P5/8/1P1R4/5k2/4p3/p3P1K1/B2R2N1 b - - 4 75',
			san: 'Rd5',
			uci: 'g5d5',
			bestSan: 'Rgd5',
			bestUci: 'g5d5',
		};
		// played !== best, or there is no puzzle at all — the drill asks the
		// player to find Rgd5 after some other move. Kf1 is legal here; a
		// described-but-unasserted fixture is how a FEN comment starts lying.
		expect(new Chess(mating.fenBefore).move({ from: 'g2', to: 'f1' }).san).toBe('Kf1');
		const item = itemDataFromStoredMove(
			move({ ...mating, san: 'Kf1', uci: 'g2f1', bestMate: 2 })
		);
		expect(item?.motifs).toContain('mate');
		expect(item?.motifs).not.toContain('open file');

		const blind = itemDataFromStoredMove(move({ ...mating, san: 'Kf1', uci: 'g2f1' }));
		expect(blind?.motifs).toEqual(['open file']);
	});

	it('returns null without a best move', () => {
		expect(itemDataFromStoredMove(move({ bestUci: undefined }))).toBeNull();
		expect(itemDataFromStoredMove(move({ bestSan: undefined }))).toBeNull();
		expect(itemDataFromStoredMove(move({ fenBefore: '' }))).toBeNull();
		expect(itemDataFromStoredMove(move({ wcDrop: 0 }))).toBeNull();
	});

	it("carries the grade's own line through, so mates and sacrifices tag (#287)", () => {
		// Qe8+!! Rxe8 Rxe8# — a queen sacrifice deflecting into a back-rank
		// mate. With the one-move line a stored move used to carry, patternTag
		// cannot walk to the mating position and sacrificeStory never fires, so
		// this item was filed under bare "mate" and the sacrifice drill did not
		// exist as a filter option at all.
		const fen = 'r5k1/5ppp/8/q7/8/8/P3QPPP/4R1K1 w - - 0 1';
		const pv = ['e2e8', 'a8e8', 'e1e8'];
		// Assert the line, not the description of it.
		const board = new Chess(fen);
		expect(board.move({ from: 'e2', to: 'e8' }).san).toBe('Qe8+');
		expect(board.move({ from: 'a8', to: 'e8' }).san).toBe('Rxe8');
		expect(board.move({ from: 'e1', to: 'e8' }).san).toBe('Rxe8#');
		expect(board.isCheckmate()).toBe(true);

		const item = itemDataFromStoredMove(
			move({
				fenBefore: fen,
				san: 'a3',
				uci: 'a2a3',
				bestSan: 'Qe8+',
				bestUci: 'e2e8',
				bestMate: 2,
				bestPv: pv,
			})
		);
		expect(item?.bestPv).toEqual(pv);
		expect(item?.motifs).toContain('mate');
		expect(item?.motifs).toContain('back-rank mate');
		expect(item?.motifs).toContain('sacrifice');
	});

	it('discards a stored line that does not start with the best move', () => {
		// The same defence lichessImport applies to its variations: a pv that
		// disagrees with bestUci would make the tags describe a line the drill
		// never shows. Fall back to the one-move line rather than trust it.
		const item = itemDataFromStoredMove(
			move({ bestPv: ['d2d4', 'g8f6'] }) // bestUci is e7e5
		);
		expect(item?.bestPv).toEqual(['e7e5']);
	});

	it('refuses a puzzle whose answer is the move you played', () => {
		// Vacuous by construction, and worse than useless: checkAttempt
		// short-circuits to a PASS when the played move equals the stored
		// bestUci, so the drill would ask you to correct a mistake and then
		// accept that mistake as the correction.
		//
		// Reachable because a grade's bestEval and its evalPawns can come from
		// two different searches, so the engine's own top move can be scored as
		// having lost a few points. Found in a real 677-item queue: one item,
		// `played Qe2 / best Qe2`, drop 6.6%.
		expect(itemDataFromStoredMove(move({ bestUci: 'g8f6', bestSan: 'Nf6' }))).toBeNull();
		// and the ordinary case still collects
		expect(itemDataFromStoredMove(move())).not.toBeNull();
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

	it('returns null only when nothing changed at all, so the caller can skip persisting',
		() => {
			// The old contract was "null when nothing was ADDED" — but a bumped
			// repeat counter is a change worth saving (#286), so a duplicate no
			// longer qualifies. What still does: an empty batch, and a re-seed
			// of the same game (same seenKey), which is the grader's crash-redo
			// and must stay a no-op.
			const first = addItems([], [seed('a')], ['g1'])!;
			expect(addItems(first, [])).toBeNull();
			expect(addItems(first, [seed('a')], ['g1'])).toBeNull();
		});

	it('agrees with addItem on the fields it sets', () => {
		const viaOne = addItem([], seed('a'))!;
		const viaMany = addItems([], [seed('a')])!;
		const strip = (i: (typeof viaOne)[number]) => ({ ...i, createdAt: '', dueAt: '' });
		expect(viaMany.map(strip)).toEqual(viaOne.map(strip));
	});
});

describe('addItem', () => {
	it('holds one item per position, counting repeats (#286)', () => {
		const data = itemDataFromStoredMove(move())!;
		const once = addItem([], data)!;
		expect(once).toHaveLength(1);
		// A repeat is not discarded any more — it is the signal #286 exists to
		// keep: the item stays one item, and remembers it has beaten you twice.
		const twice = addItem(once, data)!;
		expect(twice).toHaveLength(1);
		expect(twice[0].seenCount).toBe(2);
		expect(twice[0].lastSeenAt).toBeTruthy();
	});
});

describe('the repeat key is the position, not the bookkeeping (#286)', () => {
	const fenAt = (halfmove: number, fullmove: number) =>
		`rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - ${halfmove} ${fullmove}`;

	it('merges the same position reached on different move numbers', () => {
		// The feature's poster child: the same opening trap walked into on move
		// 12 in one game and move 14 in another. The full-fen key split these
		// apart, which is precisely the repeat worth counting.
		const first = addItem([], itemDataFromStoredMove(move({ fenBefore: fenAt(0, 1) }))!)!;
		const next = addItem(first, itemDataFromStoredMove(move({ fenBefore: fenAt(3, 12) }))!)!;
		expect(next).toHaveLength(1);
		expect(next[0].seenCount).toBe(2);
		// the drill still sets up from the full fen it first saw
		expect(next[0].fen).toBe(fenAt(0, 1));
	});

	it('ignores an en-passant square no capture can use', () => {
		// After 1.e4 chess.js records e3 as the target even though Black has no
		// pawn to take with; dartchess writes "-" for the same position. Two
		// writers, one position — the key must not split on the convention.
		const withEp = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
		const bare = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
		expect(
			new Chess(withEp).moves({ verbose: true }).some((m) => m.flags.includes('e'))
		).toBe(false);
		const first = addItem([], itemDataFromStoredMove(move({ fenBefore: withEp, color: 'b' }))!)!;
		const next = addItem(first, itemDataFromStoredMove(move({ fenBefore: bare, color: 'b' }))!)!;
		expect(next).toHaveLength(1);
		expect(next[0].seenCount).toBe(2);
	});

	it('keeps an en-passant square a capture can actually use', () => {
		// Here exd6 is legal, and en passant changes the answer — the position
		// WITH the right is a different puzzle from the one without it.
		const capturable = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3';
		const expired = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3';
		expect(
			new Chess(capturable).moves({ verbose: true }).some((m) => m.flags.includes('e'))
		).toBe(true);
		const first = addItem([], itemDataFromStoredMove(move({ fenBefore: capturable }))!)!;
		const next = addItem(first, itemDataFromStoredMove(move({ fenBefore: expired }))!)!;
		expect(next).toHaveLength(2);
	});
});

describe('bulk repeats carry their game, so a redo cannot inflate the count (#286)', () => {
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

	it('the same game re-seeded is a no-op — the grader seeds BEFORE it saves', () => {
		// background_grader.dart's crash ordering depends on this: seed, crash,
		// re-grade, re-seed must land exactly where one clean pass would.
		const first = addItems([], [seed('a')], ['g1'])!;
		expect(first[0].seenCount ?? 1).toBe(1);
		expect(addItems(first, [seed('a')], ['g1'])).toBeNull();
	});

	it('the same mistake in ANOTHER game counts', () => {
		const first = addItems([], [seed('a')], ['g1'])!;
		const next = addItems(first, [seed('a')], ['g2'])!;
		expect(next[0].seenCount).toBe(2);
		// and re-seeding THAT game is now a no-op too
		expect(addItems(next, [seed('a')], ['g2'])).toBeNull();
	});

	it('a live repeat (no key) always counts', () => {
		const first = addItems([], [seed('a')], ['g1'])!;
		const next = addItem(first, seed('a'))!;
		expect(next[0].seenCount).toBe(2);
	});
});

describe('migratePracticeItems (#286)', () => {
	const fenAt = (fullmove: number) =>
		`rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 ${fullmove}`;

	it('re-keys full-fen ids and merges the twins the old key split', () => {
		const twinA = {
			...addItem([], itemDataFromStoredMove(move({ fenBefore: fenAt(1) }))!)![0],
			id: fenAt(1), // as the old key stored it
			box: 3,
			dueAt: '2026-08-01T00:00:00.000Z',
			attempts: 4,
			correct: 3,
			depth: 22
		};
		const twinB = {
			...addItem([], itemDataFromStoredMove(move({ fenBefore: fenAt(9) }))!)![0],
			id: fenAt(9),
			box: 1,
			dueAt: '2026-07-01T00:00:00.000Z',
			attempts: 2,
			correct: 0,
			depth: 18
		};
		const merged = migratePracticeItems([twinA, twinB])!;
		expect(merged).toHaveLength(1);
		const item = merged[0];
		expect(item.id).toBe('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -');
		// each old item was a separate occurrence of the mistake
		expect(item.seenCount).toBe(2);
		// the schedule keeps the least-learned state; history is summed
		expect(item.box).toBe(1);
		expect(item.dueAt).toBe('2026-07-01T00:00:00.000Z');
		expect(item.attempts).toBe(6);
		expect(item.correct).toBe(3);
		// the deeper grade's chess fields win
		expect(item.fen).toBe(fenAt(1));
	});

	it('returns null once the collection is already in the new shape', () => {
		const oldShape = {
			...addItem([], itemDataFromStoredMove(move({ fenBefore: fenAt(1) }))!)![0],
			id: fenAt(1) // as the full-fen key stored it
		};
		const migrated = migratePracticeItems([oldShape]);
		expect(migrated).not.toBeNull();
		expect(migratePracticeItems(migrated!)).toBeNull();
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
