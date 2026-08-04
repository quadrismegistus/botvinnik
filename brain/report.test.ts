import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { endgameStartPly, isEndgamePosition } from './engine/phase';
import { skillReportPeer, skillReportUser, timeClassOfPgn, type ReportGame } from './report';

describe('timeClassOfPgn (mirrors extract.mjs classifyTimeClass)', () => {
	it('classifies by initial + 40×increment', () => {
		expect(timeClassOfPgn('[TimeControl "300+0"]\n\n1. e4 *')).toBe('blitz');
		expect(timeClassOfPgn('[TimeControl "600+5"]\n\n1. e4 *')).toBe('rapid');
		expect(timeClassOfPgn('[TimeControl "1800+0"]\n\n1. e4 *')).toBe('classical');
		expect(timeClassOfPgn('[TimeControl "60+0"]\n\n1. e4 *')).toBe('bullet');
	});

	it('reads chess.com\'s bare-seconds form — a zero-increment 10|0 is "600"', () => {
		// Review of #293: the +increment-required regex silently dropped EVERY
		// chess.com game into noClass — the archive's biggest population — while
		// their clocks parsed fine. pgn_import.dart has always read this form.
		expect(timeClassOfPgn('[TimeControl "600"]\n\n1. e4 *')).toBe('rapid');
		expect(timeClassOfPgn('[TimeControl "180"]\n\n1. e4 *')).toBe('blitz');
		// chess.com daily ("1/86400") is genuinely unclassifiable here
		expect(timeClassOfPgn('[TimeControl "1/86400"]\n\n1. e4 *')).toBeNull();
	});

	it('no header, correspondence, or no pgn → null', () => {
		expect(timeClassOfPgn('[Event "x"]\n\n1. e4 *')).toBeNull();
		expect(timeClassOfPgn('[TimeControl "-"]\n\n1. e4 *')).toBeNull();
		expect(timeClassOfPgn(undefined)).toBeNull();
	});
});

describe('skillReportUser population accounting', () => {
	const move = (color: 'w' | 'b'): ReportGame['moves'][number] => ({
		color,
		evalPawns: 0,
		mate: null
	});

	it('excludes and COUNTS: humanless, other class, unclassifiable', () => {
		const games: ReportGame[] = [
			{ botColor: null, moves: [move('w')] },
			{ botBothSides: true, botColor: 'b', moves: [move('w')] },
			{ botColor: 'b', pgn: '[TimeControl "600+5"]\n\n1. e4 *', moves: [move('w')] },
			{ botColor: 'b', moves: [move('w')] }, // no pgn at all
			{ botColor: 'b', pgn: '[TimeControl "300+0"]\n\n1. e4 *', moves: [move('w')] }
		];
		const r = skillReportUser(games, 'blitz');
		expect(r.games).toEqual({
			considered: 1,
			humanless: 2,
			otherClass: 1,
			noClass: 1
		});
	});
});

describe('skillReportUser endgame gate', () => {
	it('is STICKY through a promotion, agreeing with endgameStartPly', () => {
		// A promotion raises the majors+minors count back above six
		// mid-endgame. T5 in the pipeline is sticky from endgameStartPly; a
		// per-ply test here dropped the post-promotion plies — same predicate,
		// different application, silently incomparable numbers (#293 review:
		// user n=2 vs pipeline n=4 on this very game). The gate now latches.
		const fen = '2k5/P7/8/8/8/8/7r/K1BBRnn1 w - - 0 1';
		const sans = ['a8=Q', 'Kd7', 'Rxf1', 'Rh1'];
		// derive each fenBefore by replay — never hand-write a position
		const board = new Chess(fen);
		const fensBefore = sans.map((san) => {
			const before = board.fen();
			board.move(san);
			return before;
		});
		expect(endgameStartPly(sans, fen)).toBe(1);
		expect(isEndgamePosition(fensBefore[1])).toBe(false); // the promotion raised it

		const evalsW = [3.0, 8.0, 1.0, 6.0];
		const g: ReportGame = {
			botColor: 'b', // human plays White: plies 1 and 3
			pgn: '[TimeControl "300+0"]\n\n1. a8=Q *',
			moves: sans.map((san, i) => ({
				color: i % 2 === 0 ? 'w' : 'b',
				evalPawns: i % 2 === 0 ? evalsW[i] : -evalsW[i],
				mate: null,
				fenBefore: fensBefore[i],
				san
			}))
		};
		const r = skillReportUser([g], 'blitz');
		expect(r.endgame.n).toBe(2);
	});
});

describe('skillReportUser perspective at the mate boundary', () => {
	it('flips at the WIN% level like the pipeline — mate 0 reads as 100 for the mover', () => {
		// winChance is not antisymmetric at mate === 0 (both signs yield 0), so
		// negating the mate NUMBER diverged from the pipeline's 100−wc flip
		// exactly there (#293 review). No importer writes mate 0 today; the
		// walk must still agree with the pipeline if one ever does.
		const g: ReportGame = {
			botColor: 'w', // human plays Black
			pgn: '[TimeControl "300+0"]\n\n1. e4 *',
			moves: [
				{ color: 'w', evalPawns: null, mate: 0, san: 'e4' },
				{ color: 'b', evalPawns: 0, mate: null, san: 'e5' }
			]
		};
		const r = skillReportUser([g], 'blitz');
		// pipeline reading: black's before = 100 − wc(mate 0) = 100 ≥ 70 → T3
		expect(r.winning.n).toBe(1);
		expect(r.losing.n).toBe(0);
	});
});

describe('skillReportUser time axis', () => {
	it('panic/calm bucket by the clock BEFORE the move; think time from clk deltas', () => {
		// White's clocks: 240 → 20 (thought 220) → 15 (thought 5). White's
		// FIRST move contributes nothing (the walk is seeded null — lichess
		// grants no increment there, and a berserked header lies about the
		// initial). Before-values thereafter: 240 calm, 20 PANIC. Black has
		// no clocks — a gap poisons only black's walk.
		const pgn = [
			'[TimeControl "300+0"]',
			'',
			'1. e4 {[%eval 0.0][%clk 0:04:00]} e5 {[%eval 0.0]} ' +
				'2. Nf3 {[%eval 0.0][%clk 0:00:20]} Nc6 {[%eval 0.0]} ' +
				'3. Bb5 {[%eval 0.0][%clk 0:00:15]} *'
		].join('\n');
		const g: ReportGame = {
			botColor: 'b',
			pgn,
			moves: (['w', 'b', 'w', 'b', 'w'] as const).map((color) => ({
				color,
				evalPawns: 0,
				mate: null
			}))
		};
		const r = skillReportUser([g], 'blitz');
		expect(r.time.clockedMoves).toBe(2);
		expect(r.time.calm.n).toBe(1);
		expect(r.time.panic.n).toBe(1);
		expect(r.time.panic.pBlunder).toBe(0);
		// thinks: 220, 5 — none under 2s
		expect(r.time.under2sShare).toBe(0);
		expect(r.time.meanThinkS).toBeCloseTo(225 / 2, 6);
	});
});

describe('skillReportUser gate constants mirror the pipeline exactly', () => {
	// Mutation survivors (#293): the parity ladder sits at 73–77% and 23–27%,
	// so the 70/30 gates could drift 10 points with every suite green. These
	// pin each gate from both sides.
	const g = (blackEvalMoverPov: number): ReportGame => ({
		botColor: 'b', // human plays White
		pgn: '[TimeControl "300+0"]\n\n1. e4 *',
		moves: [
			{ color: 'w', evalPawns: 0.2, mate: null },
			{ color: 'b', evalPawns: blackEvalMoverPov, mate: null },
			{ color: 'w', evalPawns: 0.0, mate: null }
		]
	});
	// +2.0 pawns is 67.6% for the mover, +3.0 is 75.1%: only the second clears 70
	it('67.6% before is not "winning"; 75.1% is', () => {
		expect(skillReportUser([g(-2.0)], 'blitz').winning.n).toBe(0);
		expect(skillReportUser([g(-3.0)], 'blitz').winning.n).toBe(1);
	});
	it('32.4% before is not "losing"; 24.9% is', () => {
		expect(skillReportUser([g(2.0)], 'blitz').losing.n).toBe(0);
		expect(skillReportUser([g(3.0)], 'blitz').losing.n).toBe(1);
	});
});

describe('skillReportUser eval-gap and clock edges', () => {
	it('an ungraded ply resets the eval walk — no drop is measured across a gap', () => {
		// Mutation survivor (#293): with the reset dropped, the stale eval
		// carries across the gap and the once-applied flip fabricates a
		// 50-point blunder-while-winning out of two IDENTICAL evals.
		const g: ReportGame = {
			botColor: 'b', // human plays White
			pgn: '[TimeControl "300+0"]\n\n1. e4 *',
			moves: [
				{ color: 'w', evalPawns: -3.0, mate: null },
				{ color: 'b', evalPawns: null, mate: null }, // no eval at all: a gap
				{ color: 'w', evalPawns: -3.0, mate: null }
			]
		};
		const r = skillReportUser([g], 'blitz');
		expect(r.winning.n).toBe(0);
		expect(r.losing.n).toBe(0);
	});

	it('think time includes the increment the move banked', () => {
		// Mutation survivor (#293): every clocked fixture was 300+0. In 3+2 a
		// genuine 2.5s move would read as 0.5s and land under 2s — the clock
		// card's headline number, silently inflated. Measured on White's
		// SECOND move; the first contributes nothing by rule.
		const g: ReportGame = {
			botColor: 'b',
			pgn:
				'[TimeControl "180+2"]\n\n' +
				'1. e4 {[%clk 0:02:59]} e5 {[%clk 0:02:59]} ' +
				'2. Nf3 {[%clk 0:02:56]} *',
			moves: [
				{ color: 'w', evalPawns: 0, mate: null },
				{ color: 'b', evalPawns: 0, mate: null },
				{ color: 'w', evalPawns: 0, mate: null }
			]
		};
		const r = skillReportUser([g], 'blitz');
		expect(r.time.clockedMoves).toBe(1);
		expect(r.time.meanThinkS).toBeCloseTo(5, 6); // 179 → 176 with 2s banked
		expect(r.time.under2sShare).toBe(0);
	});

	it('exactly 30s left is neither panic nor calm — the pipeline puts it in 30-60s', () => {
		// Mutation survivor (#293): the peer's panic sum is [0,30) by bucket
		// construction; a <= gate here would count moves the peer number
		// excludes, and the seam is a COMMON stamp at second granularity.
		// White's clocks: 270 (first move, uncounted) → 30 → 25, so the
		// counted before-values are 270 (calm) and exactly 30 (neither).
		const game: ReportGame = {
			botColor: 'b',
			pgn:
				'[TimeControl "300+0"]\n\n' +
				'1. e4 {[%eval 0.0][%clk 0:04:30]} e5 {[%eval 0.0]} ' +
				'2. Nf3 {[%eval 0.0][%clk 0:00:30]} Nc6 {[%eval 0.0]} ' +
				'3. Bb5 {[%eval 0.0][%clk 0:00:25]} *',
			moves: (['w', 'b', 'w', 'b', 'w'] as const).map((color) => ({
				color,
				evalPawns: 0,
				mate: null
			}))
		};
		const r = skillReportUser([game], 'blitz');
		expect(r.time.panic.n).toBe(0); // ply 5's before-clock is exactly 30s
		expect(r.time.calm.n).toBe(1); // ply 3's before-clock is 270s
	});
});

describe('skillReportPeer', () => {
	const tables = {
		bands: {
			'1500': {
				blitz: {
					t3: { n: 10, mean: 4.7, blunderRate: 0.06, deciles: [1, 2, 3, 4, 5, 6, 7, 8, 9] },
					t4: { n: 10, mean: 2.3, blunderRate: 0.02, deciles: null },
					t5: { n: 5, mean: 3.1, blunderRate: 0.04, deciles: null, games: 2 },
					t1: { under2s: { n: 100, fraction: 0.29 } },
					t2: {
						blunderByClockBucket: {
							'0-5s': { n: 10, blunders: 2 },
							'5-10s': { n: 10, blunders: 1 },
							'10-30s': { n: 10, blunders: 0 },
							'30-60s': { n: 10, blunders: 0 },
							'60-120s': { n: 10, blunders: 1 },
							'120-300s': { n: 10, blunders: 0 },
							'300s+': { n: 10, blunders: 0 }
						}
					},
					t6: { plyOfFirstDeviation: { deciles: [2, 3, 3, 4, 5, 5, 6, 7, 9] } }
				}
			}
		}
	};

	it('reshapes the cell with the SAME panic/calm sums the user side uses', () => {
		const p = skillReportPeer(tables, 1500, 'blitz')!;
		expect(p.winning.mean).toBe(4.7);
		expect(p.time.panic).toEqual({ n: 30, pBlunder: 3 / 30 });
		expect(p.time.calm).toEqual({ n: 30, pBlunder: 1 / 30 });
		expect(p.time.under2sShare).toBe(0.29);
		expect(p.bookPlyDeciles?.[4]).toBe(5);
	});

	it('a missing cell is null — no baseline is ever invented', () => {
		expect(skillReportPeer(tables, 800, 'blitz')).toBeNull();
		expect(skillReportPeer(tables, 1500, 'rapid')).toBeNull();
		expect(skillReportPeer(undefined, 1500, 'blitz')).toBeNull();
	});
});
