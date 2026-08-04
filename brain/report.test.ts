import { describe, expect, it } from 'vitest';
import { skillReportPeer, skillReportUser, timeClassOfPgn, type ReportGame } from './report';

describe('timeClassOfPgn (mirrors extract.mjs classifyTimeClass)', () => {
	it('classifies by initial + 40×increment', () => {
		expect(timeClassOfPgn('[TimeControl "300+0"]\n\n1. e4 *')).toBe('blitz');
		expect(timeClassOfPgn('[TimeControl "600+5"]\n\n1. e4 *')).toBe('rapid');
		expect(timeClassOfPgn('[TimeControl "1800+0"]\n\n1. e4 *')).toBe('classical');
		expect(timeClassOfPgn('[TimeControl "60+0"]\n\n1. e4 *')).toBe('bullet');
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

describe('skillReportUser time axis', () => {
	it('panic/calm bucket by the clock BEFORE the move; think time from clk deltas', () => {
		// White's clocks: 300 → 240 (thought 60) → 20 (thought 220) → 15
		// (thought 5). Before-values: 300 calm, 240 calm, 20 PANIC. Black has
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
		expect(r.time.clockedMoves).toBe(3);
		expect(r.time.calm.n).toBe(2);
		expect(r.time.panic.n).toBe(1);
		expect(r.time.panic.pBlunder).toBe(0);
		// thinks: 60, 220, 5 — one under-2s? none. Mean (60+220+5)/3.
		expect(r.time.under2sShare).toBe(0);
		expect(r.time.meanThinkS).toBeCloseTo(285 / 3, 6);
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
