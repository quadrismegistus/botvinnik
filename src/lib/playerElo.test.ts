import { describe, it, expect } from 'vitest';
import { estimatePlayerElo } from './playerElo';
import type { StoredGame } from './gameStore';

// minimal persona game: result + botColor + botPersona are all the fit reads
function game(personaId: string, result: string, botColor: 'w' | 'b' = 'w'): StoredGame {
	return {
		id: `t-${Math.random()}`,
		endedAt: '2026-07-14T00:00:00Z',
		result,
		pgn: '',
		botElo: 0,
		botPersona: personaId,
		botColor,
		moveCount: 30,
		whiteAccuracy: null,
		blackAccuracy: null,
		labelCounts: { w: {}, b: {} },
		moves: []
	};
}

describe('estimatePlayerElo', () => {
	it('returns null with no persona games', () => {
		expect(estimatePlayerElo([])).toBeNull();
		// legacy slider game: no persona id ⇒ excluded (broken-ruler opponents)
		expect(estimatePlayerElo([{ ...game('square-1000', '1-0'), botPersona: undefined }])).toBeNull();
	});

	it('a win over 1000 and a loss to 1500 lands in between', () => {
		const est = estimatePlayerElo([
			game('square-1000', '0-1', 'w'), // bot is white, black won ⇒ player win
			game('square-1500', '1-0', 'w') // bot is white and won ⇒ player loss
		])!;
		expect(est.games).toBe(2);
		expect(est.elo).toBeGreaterThan(1000);
		expect(est.elo).toBeLessThan(1500);
		expect(est.se).toBeGreaterThan(150); // two games: still very uncertain
	});

	it('handles the player-as-white orientation (botColor=b)', () => {
		const win = estimatePlayerElo([game('square-1000', '1-0', 'b')])!; // white (player) won
		const loss = estimatePlayerElo([game('square-1000', '0-1', 'b')])!;
		expect(win.elo).toBeGreaterThan(loss.elo);
	});

	it('stays finite on an all-win record (virtual-draw regularizer)', () => {
		const est = estimatePlayerElo([
			game('square-1000', '0-1', 'w'),
			game('square-1000', '0-1', 'w'),
			game('square-1000', '0-1', 'w')
		])!;
		expect(Number.isFinite(est.elo)).toBe(true);
		expect(est.elo).toBeGreaterThan(1000); // above the opponent it keeps beating
		expect(est.elo).toBeLessThan(2900);
	});

	it('abandoned games are excluded', () => {
		expect(estimatePlayerElo([game('square-1000', '*')])).toBeNull();
	});

	it('more games shrink the standard error', () => {
		const two = estimatePlayerElo([
			game('square-1200', '0-1', 'w'),
			game('square-1200', '1-0', 'w')
		])!;
		const eight = estimatePlayerElo(
			Array.from({ length: 8 }, (_, i) => game('square-1200', i % 2 ? '0-1' : '1-0', 'w'))
		)!;
		expect(eight.se).toBeLessThan(two.se);
	});
});
