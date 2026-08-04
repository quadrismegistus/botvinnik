// Never describe a PGN in a comment, assert it — every fixture referenced
// here is asserted against its actual on-disk contents, and every
// hand-computed number below was independently verified with
// `node -e` against the real loaded brain.js before being pinned (see the
// build session notes; the arithmetic is reproduced in comments so a future
// reader can re-derive it without re-running anything).
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { splitGameBlocks, streamGames } from './stream.mjs';
import { cleanSan, extractGame, parseMovetext } from './extract.mjs';
import { buildBook, plyOfFirstDeviation } from './book.mjs';
import {
	Aggregator,
	bandFor,
	clockBucketLabel,
	moverWinChance,
	whiteWinChance
} from './aggregate.mjs';
import { loadBrain } from './loadBrain.mjs';
import { parseArgs, run, sourceNameFrom } from './run.mjs';

const FIXTURES = fileURLToPath(new URL('./fixtures/', import.meta.url));
const readFixture = (name: string) => readFileSync(join(FIXTURES, name), 'utf8');

function toAsyncIter<T>(values: T[]): AsyncIterable<T> {
	return {
		async *[Symbol.asyncIterator]() {
			for (const v of values) yield v;
		}
	};
}

// ---------------------------------------------------------------------------
// stream.mjs
// ---------------------------------------------------------------------------

describe('splitGameBlocks', () => {
	it('splits headers+movetext+blank into one game block', async () => {
		const lines = [
			'[Event "Rated Blitz game"]',
			'[White "A"]',
			'',
			'1. e4 e5 1-0',
			'',
			'[Event "Rated Blitz game"]',
			'[White "B"]',
			'',
			'1. d4 d5 1/2-1/2'
		];
		const out: string[] = [];
		for await (const block of splitGameBlocks(toAsyncIter(lines))) out.push(block);
		expect(out.length).toBe(2);
		expect(out[0]).toBe('[Event "Rated Blitz game"]\n[White "A"]\n1. e4 e5 1-0');
		expect(out[1]).toBe('[Event "Rated Blitz game"]\n[White "B"]\n1. d4 d5 1/2-1/2');
	});

	it('yields the final game even with no trailing blank line at EOF', async () => {
		const lines = ['[Event "X"]', '', '1. e4 1-0'];
		const out: string[] = [];
		for await (const block of splitGameBlocks(toAsyncIter(lines))) out.push(block);
		expect(out).toEqual(['[Event "X"]\n1. e4 1-0']);
	});

	it('ignores stray blank lines before the first game', async () => {
		const lines = ['', '', '[Event "X"]', '', '1. e4 1-0'];
		const out: string[] = [];
		for await (const block of splitGameBlocks(toAsyncIter(lines))) out.push(block);
		expect(out).toEqual(['[Event "X"]\n1. e4 1-0']);
	});
});

describe('streamGames (spawns the real zstd binary)', () => {
	const zst = join(FIXTURES, 'e2e.pgn.zst');

	it('splits the compressed e2e fixture into exactly 5 games, in order', async () => {
		const blocks: string[] = [];
		for await (const block of streamGames(zst)) blocks.push(block);
		expect(blocks.length).toBe(5);
		expect(blocks[0]).toContain('fixtureClkEval');
		expect(blocks[1]).toContain('fixtureUnrated');
		expect(blocks[2]).toContain('fixtureVariant');
		expect(blocks[3]).toContain('fixtureBullet');
		expect(blocks[4]).toContain('fixtureThresholds');
	});

	it('reads a multi-frame file with skippable frames — the shape a real dump has', async () => {
		// A real monthly dump interleaves skippable frames between zstd frames
		// (2013-01: 6 frames + 3 skips, per `zstd -l`). node:zlib's built-in
		// zstd emits ZERO bytes and dies on the first skippable frame, which
		// is why streamGames shells out to the reference binary — this fixture
		// keeps that decision from silently regressing.
		const blocks: string[] = [];
		for await (const block of streamGames(join(FIXTURES, 'e2e-multiframe.pgn.zst'))) {
			blocks.push(block);
		}
		expect(blocks.length).toBe(2);
		expect(blocks[0]).toContain('[Event ');
		expect(blocks[1]).toContain('[Event ');
	});

	it('stops the child process cleanly on early break (--max-games path)', async () => {
		let count = 0;
		for await (const _block of streamGames(zst)) {
			count++;
			if (count === 2) break;
		}
		expect(count).toBe(2);
	});

	it('rejects when the input file does not exist', async () => {
		await expect(async () => {
			for await (const _block of streamGames(join(FIXTURES, 'does-not-exist.pgn.zst'))) {
				// no-op
			}
		}).rejects.toThrow();
	});
});

// ---------------------------------------------------------------------------
// extract.mjs
// ---------------------------------------------------------------------------

describe('cleanSan', () => {
	it('strips engine-annotation glyphs but keeps real check/mate symbols', () => {
		expect(cleanSan('Nf6??')).toBe('Nf6');
		expect(cleanSan('c4?!')).toBe('c4');
		expect(cleanSan('Qh5#')).toBe('Qh5#');
		expect(cleanSan('Nxf6+?!')).toBe('Nxf6+');
		expect(cleanSan('e4')).toBe('e4');
	});
});

describe('parseMovetext', () => {
	it('attaches a comment carrying both %eval and %clk to the preceding move', () => {
		const moves = parseMovetext('1. e4 { [%eval 0.2] [%clk 0:05:00] } 1... e5');
		expect(moves).toHaveLength(2);
		expect(moves[0]).toMatchObject({
			ply: 1,
			color: 'w',
			san: 'e4',
			clk: 300,
			eval: { pawns: 0.2, mate: null }
		});
		expect(moves[1]).toMatchObject({ ply: 2, color: 'b', san: 'e5', clk: null, eval: null });
	});

	it('parses a mate-form eval (#N) distinctly from a pawns eval', () => {
		const moves = parseMovetext('1. Qh5 Nf6?? { [%eval #4] }');
		expect(moves[1]).toMatchObject({ san: 'Nf6', eval: { pawns: null, mate: 4 } });
	});
});

describe('extractGame: fixtures/clk-eval.pgn', () => {
	const rec = extractGame(readFixture('clk-eval.pgn'));

	it('extracts a rated blitz game with 7 plies', () => {
		expect(rec.skip).toBeNull();
		if (rec.skip) throw new Error('unreachable');
		expect(rec.timeClass).toBe('blitz');
		expect(rec.whiteElo).toBe(1500);
		expect(rec.blackElo).toBe(1500);
		expect(rec.termination).toBe('Normal');
		expect(rec.moves).toHaveLength(7);
	});

	it('extracts clk on every move (incl. the mating move) and eval where present', () => {
		if (rec.skip) throw new Error('unreachable');
		const [e4, e5, Bc4, Nc6, Qh5, Nf6, Qxf7] = rec.moves;
		expect(e4).toMatchObject({ san: 'e4', clk: 300, eval: { pawns: 0.2, mate: null } });
		expect(e5).toMatchObject({ san: 'e5', clk: 298, eval: { pawns: 0.1, mate: null } });
		expect(Bc4).toMatchObject({ san: 'Bc4', clk: 295 });
		expect(Nc6).toMatchObject({ san: 'Nc6', clk: 290 });
		expect(Qh5).toMatchObject({ san: 'Qh5', clk: 290 });
		// the fixture's whole point: a mate-form eval, and the SAN glyph "??"
		// stripped from the move that earns it
		expect(Nf6).toMatchObject({ san: 'Nf6', clk: 270, eval: { pawns: null, mate: 4 } });
		// real lichess dumps often omit the eval comment on the mating move
		// itself — the fixture mirrors that; clk is still present
		expect(Qxf7).toMatchObject({ san: 'Qxf7#', clk: 268, eval: null });
	});
});

describe('extractGame: skip reasons', () => {
	it('skips a casual (unrated) game', () => {
		expect(extractGame(readFixture('unrated.pgn'))).toEqual({ skip: 'unrated' });
	});

	it('skips a variant game (Chess960)', () => {
		expect(extractGame(readFixture('variant.pgn'))).toEqual({ skip: 'variant' });
	});

	it('skips a bullet game by TimeControl, even though Event says "Bullet"', () => {
		expect(extractGame(readFixture('bullet.pgn'))).toEqual({ skip: 'bullet' });
	});
});

describe('extractGame: lichess speed classification (TimeControl -> time-class)', () => {
	function raw({
		timeControl = '300+0',
		event = 'Rated Blitz game'
	}: { timeControl?: string; event?: string } = {}) {
		return [
			`[Event "${event}"]`,
			'[Site "https://lichess.org/x"]',
			'[White "A"]',
			'[Black "B"]',
			'[Result "1-0"]',
			'[WhiteElo "1500"]',
			'[BlackElo "1500"]',
			`[TimeControl "${timeControl}"]`,
			'[Termination "Normal"]',
			'',
			'1. e4 1-0'
		].join('\n');
	}

	// estimate = initial + 40*increment (lichess's Speed.scala); boundaries are
	// <30 ultrabullet, <180 bullet, <480 blitz, <1500 rapid, else classical.
	it.each([
		['0+0', 'bullet'], // estimate 0 -> ultrabullet, collapsed into the 'bullet' skip reason
		['29+0', 'bullet'], // 29 -> ultrabullet
		['30+0', 'bullet'], // 30 -> bullet (boundary, inclusive on the bullet side)
		['179+0', 'bullet'], // just under the blitz boundary
		['180+0', 'blitz'], // boundary: blitz starts here
		['479+0', 'blitz'],
		['480+0', 'rapid'], // boundary: rapid starts here
		['1499+0', 'rapid'],
		['1500+0', 'classical'], // boundary: classical starts here
		['0+15', 'rapid'] // 0 + 40*15 = 600 -> rapid, NOT bullet: increment
		// alone can carry a tiny base time control well out of bullet territory,
		// which is exactly why the classifier reads TimeControl's increment
		// too, not just its initial seconds
	])('TimeControl %s classifies as %s (or is skipped as bullet)', (tc, expected) => {
		const rec = extractGame(raw({ timeControl: tc }));
		if (expected === 'bullet') {
			expect(rec).toEqual({ skip: 'bullet' });
		} else {
			expect(rec.skip).toBeNull();
			if (!rec.skip) expect(rec.timeClass).toBe(expected);
		}
	});

	it('TimeControl "-" (no clock / correspondence) is skipped, not classified', () => {
		expect(extractGame(raw({ timeControl: '-' }))).toEqual({ skip: 'no-time-control' });
	});
});

// ---------------------------------------------------------------------------
// book.mjs
// ---------------------------------------------------------------------------

describe('book.mjs (isolated mini book)', () => {
	const miniDir = fileURLToPath(new URL('./fixtures/openings-mini/', import.meta.url));
	const book = buildBook(miniDir);

	it('builds one trie node path per tsv row', () => {
		expect(book.lines).toBe(2);
	});

	it('returns null (stayed in book) for an exact known line', () => {
		expect(plyOfFirstDeviation(book, ['d4', 'd5'])).toBeNull();
	});

	it('finds the ply where a game leaves the book', () => {
		// 'd4' is known, 'c5' in reply to it is not (only d5/Nf6 are)
		expect(plyOfFirstDeviation(book, ['d4', 'c5'])).toBe(2);
		// unknown from move 1
		expect(plyOfFirstDeviation(book, ['e4', 'e5'])).toBe(1);
	});

	it('respects the ply cap', () => {
		// in book for 2 plies, would deviate at ply 3, but cap=2 stops looking
		expect(plyOfFirstDeviation(book, ['d4', 'Nf6', 'xxxx'], 2)).toBeNull();
	});
});

describe('book.mjs (real vendored chess-openings data)', () => {
	const book = buildBook();

	it('vendors a non-trivial number of reference lines', () => {
		expect(book.lines).toBeGreaterThan(3000);
	});

	it('has the expected opening moves at the root', () => {
		expect(book.root.children.has('e4')).toBe(true);
		expect(book.root.children.has('d4')).toBe(true);
	});

	// Hand-verified once against the committed data (data/openings/*.tsv is
	// vendored, fixed content — see pipeline/lichess/data/openings/):
	// "e4 e5 Bc4 Nc6" is known theory, "Qh5" next is not -> deviates at ply 5.
	it('finds the real deviation ply for the clk-eval fixture SAN sequence', () => {
		const rec = extractGame(readFixture('clk-eval.pgn'));
		if (rec.skip) throw new Error('unreachable');
		const sans = rec.moves.map((m) => m.san);
		expect(plyOfFirstDeviation(book, sans)).toBe(5);
	});

	// "a3" is known (Anderssen's Opening) but "a3 Nc6" is not -> ply 2.
	it('finds the real deviation ply for the thresholds fixture SAN sequence', () => {
		const rec = extractGame(readFixture('thresholds.pgn'));
		if (rec.skip) throw new Error('unreachable');
		const sans = rec.moves.map((m) => m.san);
		expect(plyOfFirstDeviation(book, sans)).toBe(2);
	});
});

// ---------------------------------------------------------------------------
// aggregate.mjs — the commensurability invariant lives here: every win-chance
// number below comes from the real loaded flutter/assets/brain.js.
// ---------------------------------------------------------------------------

describe('aggregate.mjs', () => {
	let brain: ReturnType<typeof loadBrain>;
	let book: ReturnType<typeof buildBook>;

	beforeAll(() => {
		brain = loadBrain();
		book = buildBook();
	});

	describe('bandFor', () => {
		it('buckets to the nearest 100 below', () => {
			expect(bandFor(1550)).toBe(1500);
			expect(bandFor(1500)).toBe(1500);
			expect(bandFor(1599)).toBe(1500);
		});
		it('clamps to the open-ended tails', () => {
			expect(bandFor(750)).toBe(800);
			expect(bandFor(1)).toBe(800);
			expect(bandFor(2650)).toBe(2600);
			expect(bandFor(9999)).toBe(2600);
		});
		it('returns null for a non-finite rating', () => {
			expect(bandFor(NaN)).toBeNull();
		});
	});

	describe('clockBucketLabel', () => {
		it('buckets remaining-clock seconds, boundaries inclusive on the low side', () => {
			expect(clockBucketLabel(0)).toBe('0-5s');
			expect(clockBucketLabel(4.9)).toBe('0-5s');
			expect(clockBucketLabel(5)).toBe('5-10s');
			expect(clockBucketLabel(29.9)).toBe('10-30s');
			expect(clockBucketLabel(30)).toBe('30-60s');
			expect(clockBucketLabel(299)).toBe('120-300s');
			expect(clockBucketLabel(300)).toBe('300s+');
			expect(clockBucketLabel(9999)).toBe('300s+');
		});
	});

	describe('mover-perspective win% — pinned against hand-computed fixed points', () => {
		// cp = 0 is the sigmoid's fixed point: winChance(0, null) === 50 exactly,
		// no calculator needed. mate sign resolves to 100/0 exactly by
		// definition (brain.winChance: `mate > 0 ? 100 : 0`). These two facts
		// alone pin the SIGN CONVENTION this pipeline depends on — that
		// %eval is White-POV and gets flipped to the mover's own POV by color
		// — without re-deriving the sigmoid curve itself (which the
		// commensurability invariant says must never be reimplemented here).
		it('cp=0 is 50% for White and 50% for the mover regardless of color', () => {
			const entry = { pawns: 0, mate: null };
			expect(whiteWinChance(brain, entry)).toBe(50);
			expect(moverWinChance(brain, entry, 'w')).toBe(50);
			expect(moverWinChance(brain, entry, 'b')).toBe(50);
		});

		it('a White-POV mate flips sign correctly for Black to move', () => {
			const whiteMates = { pawns: null, mate: 3 };
			expect(whiteWinChance(brain, whiteMates)).toBe(100);
			expect(moverWinChance(brain, whiteMates, 'w')).toBe(100); // White mating: great for White
			expect(moverWinChance(brain, whiteMates, 'b')).toBe(0); // ...terrible for Black

			const blackMates = { pawns: null, mate: -3 };
			expect(whiteWinChance(brain, blackMates)).toBe(0);
			expect(moverWinChance(brain, blackMates, 'w')).toBe(0);
			expect(moverWinChance(brain, blackMates, 'b')).toBe(100);
		});

		it('a favorable White-POV eval is WORSE for Black, numerically flipped', () => {
			// wc(+3.0 pawns) computed once from the real bundle: 75.11255...
			const entry = { pawns: 3.0, mate: null };
			const wcWhite = whiteWinChance(brain, entry)!;
			expect(wcWhite).toBeCloseTo(75.1126, 3);
			expect(moverWinChance(brain, entry, 'w')).toBeCloseTo(75.1126, 3);
			expect(moverWinChance(brain, entry, 'b')).toBeCloseTo(100 - 75.1126, 3);
		});

		it('null in, null out', () => {
			expect(whiteWinChance(brain, null)).toBeNull();
			expect(moverWinChance(brain, null, 'w')).toBeNull();
		});
	});

	describe('T3/T4 threshold gating — fixtures/thresholds.pgn', () => {
		// The fixture's eval sequence (White POV pawns) was designed by hand so
		// that exactly two moves face a mover-before win% >= 70 (T3) and
		// exactly one faces <= 30 (T4), with three more moves parked just
		// outside each boundary (69.2%, 30.8%, 32.4%) to prove the gate's
		// edges are exclusive in the right direction. Ground truth for each
		// ply (White-POV pawns -> White-POV win% via the real brain.winChance,
		// then flipped to the mover's POV by color):
		//
		//   before        wc(before)  mover  moverBefore  qualifies
		//   ply1 START     51.38(w)    w      51.38        no
		//   ply2 0.1        50.92(w)   b      49.08        no
		//   ply3 0.1        50.92(w)   w      50.92        no
		//   ply4 3.0        75.11(w)   b      24.89        T4 (<=30)
		//   ply5 4.0        81.35(w)   w      81.35        T3 (>=70)
		//   ply6 2.0        67.62(w)   b      32.38        no (just above 30)
		//   ply7 2.2        69.21(w)   w      69.21        no (just below 70)
		//   ply8 2.2        69.21(w)   b      30.79        no (just above 30)
		//   ply9 -0.3       47.24(w)   w      47.24        no
		//   ply10 -8.0       4.99(w)   b      95.01        T3 (>=70)
		//
		// -> t3.n === 2 (ply5, ply10), t4.n === 1 (ply4). None of the three
		// qualifying moves' wcDrop reaches the 20-point blunder line, so both
		// blunderRates are 0 — that is hand-verifiable from the table above
		// (e.g. ply5: 81.35 -> wc(2.0)=67.62, drop 13.73 < 20) without a
		// calculator for the sigmoid itself.
		let agg: Aggregator;

		beforeAll(() => {
			agg = new Aggregator(brain, book);
			const rec = extractGame(readFixture('thresholds.pgn'));
			if (rec.skip) throw new Error('fixture unexpectedly skipped: ' + rec.skip);
			agg.addGame(rec);
		});

		it('both players land in the 1500 band, blitz class', () => {
			expect([...agg.cells.keys()]).toEqual(['1500|blitz']);
		});

		it('T3 has exactly 2 samples, T4 exactly 1, neither reaching the blunder line', () => {
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t3.n).toBe(2);
			expect(cell.t4.n).toBe(1);
			expect(cell.t3Blunders).toBe(0);
			expect(cell.t4Blunders).toBe(0);
		});

		it('T3/T4 wcDrop values match the hand-derived table above', () => {
			const cell = agg.cellFor(1500, 'blitz');
			const t3sorted = [...cell.t3.values].sort((a, b) => a - b);
			// ply10 drop 95.01-90.11=4.90, ply5 drop 81.35-67.62=13.73
			expect(t3sorted[0]).toBeCloseTo(4.9, 1);
			expect(t3sorted[1]).toBeCloseTo(13.73, 1);
			// ply4 drop 24.89-18.65=6.24
			expect(cell.t4.values[0]).toBeCloseTo(6.24, 1);
		});
	});

	describe('T6 book-ply attribution', () => {
		it('records one sample per side per game, using the real book', () => {
			const agg = new Aggregator(brain, book);
			const rec = extractGame(readFixture('thresholds.pgn')); // deviates at ply 2
			if (rec.skip) throw new Error('unreachable');
			agg.addGame(rec);
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t6Deviation.n).toBe(2); // white's band + black's band, same cell here
			expect(cell.t6Deviation.values).toEqual([2, 2]);
		});
	});

	describe('T5 endgame: sampled replay through brain.endgameStartPly', () => {
		// A legal 84-ply trade-down GENERATED with chess.js (greedy captures,
		// repetition-guarded) rather than written by hand — three hand-built
		// fixtures went illegal in one day. The lila divider (majors+minors
		// ≤ 6) is first satisfied before ply 77, so plies 77..84 are the
		// endgame; the first test pins that against the brain itself.
		const SANS = [
			'a3','a6','a4','b6','a5','c6','axb6','d6','b7','e6','bxa8=N','f6',
			'b3','g6','b4','h6','b5','a5','b6','c5','b7','d5','bxc8=N','Qxc8',
			'c3','e5','c4','f5','cxd5','g5','d6','h5','d7+','Nxd7','d3','Qxa8',
			'd4','a4','d5','c4','d6','e4','e3','f4','exf4','g4','f5','h4','f6',
			'a3','f7+','Kxf7','f3','c3','f4','e3','f5','g3','f6','h3','gxh3',
			'Qxh1','h4','Qxg1','h5','Qxf1+','Kxf1','a2','h6','axb1=N','Rxb1',
			'c2','h7','cxd1=N','hxg8=N','Rxg8','h3','e2+','Kxe2','g2','Kxd1',
			'g1=N','h4','Bg7',
		];
		const gameText = ({ evals = true } = {}) => {
			const movetext = SANS.map((san, i) => {
				const num = i % 2 === 0 ? `${i / 2 + 1}. ` : '';
				return `${num}${san}${evals ? ' {[%eval 0.0]}' : ''}`;
			}).join(' ');
			return [
				'[Event "Rated Blitz game"]',
				'[Site "https://lichess.org/t5fix"]',
				'[White "w"]',
				'[Black "b"]',
				'[Result "*"]',
				'[WhiteElo "1500"]',
				'[BlackElo "1500"]',
				'[TimeControl "300+0"]',
				'[Termination "Unterminated"]',
				'',
				movetext + ' *',
			].join('\n');
		};
		const parsed = (text: string) => {
			const rec = extractGame(text);
			if ('skip' in rec && rec.skip) throw new Error('fixture skipped: ' + rec.skip);
			return rec;
		};

		it('the brain finds the pinned boundary for this line', () => {
			expect(brain.endgameStartPly(SANS)).toBe(77);
		});

		it('records exactly the endgame plies, both movers, flat evals → zero drops', () => {
			const agg = new Aggregator(brain, book);
			agg.addGame(parsed(gameText()));
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t5.n).toBe(8); // plies 77..84
			expect(cell.t5Games).toBe(2);
			expect(cell.t5Blunders).toBe(0);
			expect(cell.t5.values.every((v: number) => v === 0)).toBe(true);
		});

		it('the cap gates per SIDE, stops new games, and lands in meta', () => {
			// Both players band to the same cell here, so a cap of 1 admits
			// White's side and refuses Black's — 4 endgame plies, not 8 — and
			// the second game is not replayed at all.
			const agg = new Aggregator(brain, book, { t5SampleCap: 1 });
			agg.addGame(parsed(gameText()));
			agg.addGame(parsed(gameText()));
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t5Games).toBe(1);
			expect(cell.t5.n).toBe(4);
			const env = agg.toEnvelope({ source: 'x', brainVersion: 2, games: {} });
			expect(env.meta.caps.t5).toBe(1);
		});

		it('a game without evals is never replayed — the budget is for data', () => {
			let replays = 0;
			// the bundle's exports are getter-only, so shadow via defineProperty
			const counting = Object.create(brain);
			Object.defineProperty(counting, 'endgameStartPly', {
				value: (...args: unknown[]) => {
					replays++;
					return brain.endgameStartPly(...args);
				},
			});
			const agg = new Aggregator(counting, book);
			agg.addGame(parsed(gameText({ evals: false })));
			expect(replays).toBe(0);
			expect(agg.cellFor(1500, 'blitz').t5Games).toBe(0);
		});
	});

	describe('T1 think-time: the running clock is seeded from TimeControl’s initial time', () => {
		it('counts every move of a gap-free game, including each side’s first', () => {
			// prevClk[color] starts at the game's own TimeControl initial
			// seconds and haveClk[color] starts true — the "before" state for
			// the very first move of each color is genuinely known (it's what
			// TimeControl says they started with), so it is NOT excluded. All
			// 7 plies of clk-eval.pgn carry a %clk with no gaps.
			const agg = new Aggregator(brain, book);
			const rec = extractGame(readFixture('clk-eval.pgn'));
			if (rec.skip) throw new Error('unreachable');
			agg.addGame(rec);
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t1TotalN).toBe(7);
		});

		it('skips a move with no clk, and the next move of that color too (stale prevClk)', () => {
			// 1.e4 {clk} 1...e5 {clk} 2.Nf3 (no clk — the gap) 2...Nc6 {clk}
			// 3.Bc4 {clk} 3...Bc5 {clk}. White's Nf3 has no clk (excluded, and
			// it also invalidates White's running clock). White's very next
			// move, Bc4, DOES carry a clk, but the gap means we don't actually
			// know White's remaining time right before it — excluded too. Bc4
			// resumes tracking for White from itself onward. Black never has a
			// gap, so all 3 of Black's moves count. Expected: e4, e5, Nc6, Bc5
			// = 4 samples (Nf3 and Bc4 excluded).
			const raw = [
				'[Event "Rated Blitz game"]',
				'[Site "https://lichess.org/x"]',
				'[White "A"]',
				'[Black "B"]',
				'[Result "1-0"]',
				'[WhiteElo "1500"]',
				'[BlackElo "1500"]',
				'[TimeControl "300+0"]',
				'[Termination "Normal"]',
				'',
				'1. e4 { [%clk 0:05:00] } 1... e5 { [%clk 0:04:58] } 2. Nf3 2... Nc6 { [%clk 0:04:50] } 3. Bc4 { [%clk 0:04:45] } 3... Bc5 { [%clk 0:04:40] } 1-0'
			].join('\n');
			const agg = new Aggregator(brain, book);
			const rec = extractGame(raw);
			if (rec.skip) throw new Error('unreachable');
			agg.addGame(rec);
			const cell = agg.cellFor(1500, 'blitz');
			expect(cell.t1TotalN).toBe(4);
		});
	});

	describe('T2 clock-pressure: P(blunder | remaining clock bucket)', () => {
		it('records a blunder in the correct remaining-clock bucket', () => {
			// TimeControl "20+15" starts White with only 20s on the clock, but
			// the 15s increment pushes the estimate (20 + 40*15 = 620) into
			// 'rapid', not bullet — proving the classifier reads the increment,
			// not just initial seconds (see the TimeControl it.each above).
			// Ply 1's remaining-clock-before bucket is therefore
			// clockBucketLabel(20) = '10-30s'. The move's own eval (-3.0, White
			// POV) against START_EVAL's 0.15 is a real blunder: moverBefore =
			// wc(0.15) = 51.38, moverAfter = wc(-3.0) = 100 - wc(3.0) = 24.89,
			// wcDrop = 26.49 >= 20.
			const raw = [
				'[Event "Rated Blitz game"]',
				'[Site "https://lichess.org/x"]',
				'[White "A"]',
				'[Black "B"]',
				'[Result "0-1"]',
				'[WhiteElo "1500"]',
				'[BlackElo "1500"]',
				'[TimeControl "20+15"]',
				'[Termination "Normal"]',
				'',
				'1. a3 { [%eval -3.0] [%clk 0:00:15] } 0-1'
			].join('\n');
			const rec = extractGame(raw);
			if (rec.skip) throw new Error('unreachable');
			expect(rec.timeClass).toBe('rapid');

			const agg = new Aggregator(brain, book);
			agg.addGame(rec);
			const cell = agg.cellFor(1500, 'rapid');
			const bucket = cell.t2ClockBucket.get('10-30s');
			expect(bucket).toEqual({ n: 1, blunders: 1 });
		});
	});
});

// ---------------------------------------------------------------------------
// run.mjs — CLI helpers + full end-to-end pipeline over the crafted e2e dump
// ---------------------------------------------------------------------------

describe('run.mjs helpers', () => {
	it('parseArgs reads --out and --max-games, defaults otherwise', () => {
		const args = parseArgs(['dump.pgn.zst', '--out', 'x.json', '--max-games', '50']);
		expect(args).toMatchObject({ input: 'dump.pgn.zst', out: 'x.json', maxGames: 50 });
	});

	it('parseArgs throws with no input path', () => {
		expect(() => parseArgs(['--out', 'x.json'])).toThrow();
	});

	it('sourceNameFrom strips the .pgn.zst suffix', () => {
		expect(sourceNameFrom('/a/b/lichess_db_standard_rated_2013-01.pgn.zst')).toBe(
			'lichess_db_standard_rated_2013-01'
		);
	});
});

describe('end-to-end: fixtures/e2e.pgn.zst through the full pipeline', () => {
	let tmpDir: string;

	beforeAll(() => {
		tmpDir = mkdtempSync(join(tmpdir(), 'lichess-pipeline-e2e-'));
	});
	afterAll(() => {
		rmSync(tmpDir, { recursive: true, force: true });
	});

	it('streams, extracts, aggregates and writes the versioned envelope', async () => {
		const brain = loadBrain();
		const book = buildBook();
		const outPath = join(tmpDir, 'peer-tables.json');
		const zst = join(FIXTURES, 'e2e.pgn.zst');

		const { envelope, streamed, parsed, skipped } = await run(['--out', outPath, zst], {
			brain,
			book
		});

		// e2e.pgn.zst is clk-eval + unrated + variant + bullet + thresholds
		expect(streamed).toBe(5);
		expect(parsed).toBe(2); // clk-eval + thresholds
		expect(skipped).toEqual({ unrated: 1, variant: 1, bullet: 1 });

		expect(envelope.v).toBe(1);
		expect(envelope.source).toBe('e2e');
		expect(envelope.brainVersion).toBe(brain.BRAIN_VERSION);
		expect(envelope.meta.games).toEqual({ streamed: 5, parsed: 2, skipped });
		expect(envelope.meta.struck).toEqual(['t7']);
		expect(envelope.meta.caps.t5).toBe(2000);

		// both parsed games' players band to 1500/blitz
		expect(Object.keys(envelope.bands)).toEqual(['1500']);
		const cell = envelope.bands['1500'].blitz;
		// thresholds.pgn alone contributes t3.n=2 (see the dedicated T3/T4
		// describe block below for the hand-derivation); clk-eval.pgn adds one
		// more: its final move (Qxf7#) has no eval comment but ends in "#", so
		// the checkmate fallback scores it 100% for the mover — moverBefore is
		// itself 100 (White was already given mate-in-4 the move before), which
		// clears the T3 gate at wcDrop=0. Combined: 2 + 1 = 3. clk-eval.pgn
		// contributes nothing to T4.
		expect(cell.t3.n).toBe(3);
		expect(cell.t4.n).toBe(1);
		// ten-ply miniatures never reach the endgame: a real, empty table
		expect(cell.t5.n).toBe(0);
		expect(cell.t5.games).toBe(0);
		// both games' book-ply samples: clk-eval (5,5) + thresholds (2,2)
		expect(cell.t6.plyOfFirstDeviation.n).toBe(4);

		expect(existsSync(outPath)).toBe(true);
		const written = JSON.parse(readFileSync(outPath, 'utf8'));
		expect(written).toEqual(envelope);
	});
});

// ---------------------------------------------------------------------------
// loadBrain.mjs
// ---------------------------------------------------------------------------

describe('loadBrain', () => {
	it('loads the real bundle with a working winChance and a version number', () => {
		const brain = loadBrain();
		expect(typeof brain.winChance).toBe('function');
		expect(typeof brain.BRAIN_VERSION).toBe('number');
	});

	it('throws rather than silently returning a half-built brain', () => {
		expect(() => loadBrain('/definitely/not/a/real/path/brain.js')).toThrow();
	});
});
