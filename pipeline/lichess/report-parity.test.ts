// THE COMMENSURABILITY PIN (#268): one synthetic game, two walks — the peer
// pipeline's Aggregator over white-POV dump evals, and the app's
// skillReportUser over the same game in the archive's MOVER-POV encoding.
// If any axis number differs, the report compares two different quantities
// and every verdict on that screen is fiction. This is the test that holds
// the perspective flip honest.
import { describe, expect, it } from 'vitest';
import { winChance } from '../../brain/engine/insights';
import { endgameStartPly } from '../../brain/engine/phase';
import { skillReportUser, type ReportGame } from '../../brain/report';
import { Aggregator } from './aggregate.mjs';

// White-POV evals after each ply — the thresholds ladder: swings that put
// each side above 70 and below 30 at least once, with one 20+ point drop.
const PLIES: { color: 'w' | 'b'; sans: string; evalW: number }[] = [
	// swings chosen to clear the 70/30 gates with margin — a first draft sat
	// at win chances of 30.8 and 31.6, T4 stayed empty on BOTH sides, and
	// only the vacuity guards below caught the parity passing over nothing
	{ color: 'w', sans: 'e4', evalW: 0.3 },
	{ color: 'b', sans: 'e5', evalW: 3.0 }, // black blunders: white winning
	{ color: 'w', sans: 'Nf3', evalW: 2.8 }, // white (≥70) leaks a little → T3
	{ color: 'b', sans: 'Nc6', evalW: 3.2 }, // black (≤30) small drop → T4
	{ color: 'w', sans: 'Bb5', evalW: -2.8 }, // white (≥70) collapses 50 pts → T3 blunder
	{ color: 'b', sans: 'a6', evalW: -3.0 }, // black (now ≥70) plays on → T3
	{ color: 'w', sans: 'Ba4', evalW: -3.2 }, // white (≤30) small drop → T4
	{ color: 'b', sans: 'Nf6', evalW: -2.9 } // black (≥70) leaks a little → T3
];

describe('pipeline ↔ report parity', () => {
	it('T3/T4 from the Aggregator equal winning/losing from skillReportUser', () => {
		// ---- pipeline side: both players in one band, white-POV evals
		const agg = new Aggregator(
			{ winChance, endgameStartPly },
			{ root: { children: new Map() }, lines: 0 }, // empty book: deviate at ply 1, irrelevant here
			{ t5SampleCap: 0 }
		);
		agg.addGame({
			timeClass: 'blitz',
			whiteElo: 1500,
			blackElo: 1500,
			initial: 300,
			increment: 0,
			moves: PLIES.map((p, i) => ({
				ply: i + 1,
				color: p.color,
				san: p.sans,
				clk: null,
				eval: { pawns: p.evalW, mate: null }
			}))
		});
		const cell = agg.cellFor(1500, 'blitz');

		// ---- report side: the SAME game twice, once per human side, so the
		// union covers both colors' moves exactly as the shared cell does.
		// Stored moves are MOVER-POV: negate white-POV evals for black plies.
		const pgn = '[TimeControl "300+0"]\n\n1. e4 e5 *';
		const gameAs = (human: 'w' | 'b'): ReportGame => ({
			botColor: human === 'w' ? 'b' : 'w',
			pgn,
			moves: PLIES.map((p) => ({
				color: p.color,
				evalPawns: p.color === 'w' ? p.evalW : -p.evalW,
				mate: null,
				san: p.sans
			}))
		});
		const user = skillReportUser([gameAs('w'), gameAs('b')], 'blitz');

		expect(user.games.considered).toBe(2);
		expect(user.winning.n).toBe(cell.t3.n);
		expect(user.winning.mean).toBeCloseTo(cell.t3.mean()!, 10);
		expect(user.winning.blunderRate).toBeCloseTo(cell.t3Blunders / cell.t3.n, 10);
		expect(user.losing.n).toBe(cell.t4.n);
		expect(user.losing.mean).toBeCloseTo(cell.t4.mean()!, 10);

		// the ladder itself must have exercised both tables, or the parity is
		// vacuously green over empty cells
		expect(cell.t3.n).toBeGreaterThan(1);
		expect(cell.t4.n).toBeGreaterThan(1);
		expect(cell.t3Blunders).toBeGreaterThan(0);
	});
});
