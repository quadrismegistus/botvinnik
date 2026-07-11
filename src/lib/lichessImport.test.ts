import { describe, expect, it } from 'vitest';
import { lichessGameToStored } from './lichessImport';

// Fool's mate, as the lichess NDJSON export would ship it: per-half-move evals
// from White's POV, with the blunder flagged (best + variation + judgment).
const FOOLS_MATE = {
	id: 'abcd1234',
	variant: 'standard',
	speed: 'blitz',
	status: 'mate',
	winner: 'black' as const,
	lastMoveAt: 1770000000000,
	players: {
		white: { user: { name: 'Ryan' }, rating: 1500 },
		black: { user: { name: 'Villain' }, rating: 1510 }
	},
	moves: 'f3 e5 g4 Qh4#',
	pgn: '1. f3 e5 2. g4 Qh4# 0-1',
	analysis: [
		{ eval: -50 }, // after 1.f3
		{ eval: -70 }, // after 1...e5
		{ mate: -1, best: 'b1c3', variation: 'Nc3', judgment: { name: 'Blunder', comment: '' } }, // after 2.g4
		{ mate: 0 } // after 2...Qh4#
	]
};

describe('lichessGameToStored', () => {
	it('maps evals to mover-perspective grades and labels', () => {
		const mapped = lichessGameToStored(FOOLS_MATE, 'ryan')!;
		expect(mapped.humanColor).toBe('w');
		const { stored } = mapped;
		expect(stored.id).toBe('lichess-abcd1234');
		expect(stored.result).toBe('0-1');
		expect(stored.white).toBe('Ryan');
		expect(stored.botColor).toBe('b'); // review orientation: human plays White

		const [f3, e5, g4, qh4] = stored.moves;
		expect(f3.san).toBe('f3');
		expect(f3.evalPawns).toBeCloseTo(-0.5); // mover (White) perspective
		expect(e5.evalPawns).toBeCloseTo(0.7); // Black's perspective of -70
		expect(g4.label).toBe('blunder'); // ~45% win-chance drop into mate
		expect(g4.bestSan).toBe('Nc3');
		expect(g4.mate).toBe(-1);
		expect(qh4.label).toBe('excellent'); // no drop — delivered the mate
		expect(qh4.wcDrop).toBe(0);
	});

	it('collects the importing user own mistakes as practice candidates', () => {
		const mapped = lichessGameToStored(FOOLS_MATE, 'ryan')!;
		expect(mapped.practice).toHaveLength(1);
		const p = mapped.practice[0];
		expect(p.playedSan).toBe('g4');
		expect(p.bestSan).toBe('Nc3');
		expect(p.bestPv).toEqual(['b1c3']);
		expect(p.drop).toBeGreaterThan(20);
		// but not the opponent's mistakes
		const asVillain = lichessGameToStored(FOOLS_MATE, 'villain')!;
		expect(asVillain.practice).toHaveLength(0); // black made no flagged move
		expect(asVillain.humanColor).toBe('b');
	});

	it('rejects non-standard or unanalysed games', () => {
		expect(lichessGameToStored({ ...FOOLS_MATE, variant: 'atomic' }, 'ryan')).toBeNull();
		expect(lichessGameToStored({ ...FOOLS_MATE, analysis: [] }, 'ryan')).toBeNull();
	});
});
