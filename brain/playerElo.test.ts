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
		expect(estimatePlayerElo([{ ...game('squarefish-1000', '1-0'), botPersona: undefined }])).toBeNull();
	});

	it('counts games archived under a pre-rename persona id', () => {
		// The whole argument for the id migration is that estimatePlayerElo does
		// `if (!p) continue` — a broken alias drops history silently rather than
		// failing. Every other id in this file is post-rename, so without this
		// the alias could be deleted and this suite would stay green.
		const legacy = estimatePlayerElo([game('square-1000', '1-0', 'b')]);
		const renamed = estimatePlayerElo([game('squarefish-1000', '1-0', 'b')]);
		expect(legacy).not.toBeNull();
		expect(legacy).toEqual(renamed);
	});

	it('a win over 1000 and a loss to 1500 lands in between', () => {
		const est = estimatePlayerElo([
			game('squarefish-1000', '0-1', 'w'), // bot is white, black won ⇒ player win
			game('squarefish-1500', '1-0', 'w') // bot is white and won ⇒ player loss
		])!;
		expect(est.games).toBe(2);
		expect(est.elo).toBeGreaterThan(1000);
		expect(est.elo).toBeLessThan(1500);
		expect(est.se).toBeGreaterThan(150); // two games: still very uncertain
	});

	it('handles the player-as-white orientation (botColor=b)', () => {
		const win = estimatePlayerElo([game('squarefish-1000', '1-0', 'b')])!; // white (player) won
		const loss = estimatePlayerElo([game('squarefish-1000', '0-1', 'b')])!;
		expect(win.elo).toBeGreaterThan(loss.elo);
	});

	it('stays finite on an all-win record (virtual-draw regularizer)', () => {
		const est = estimatePlayerElo([
			game('squarefish-1000', '0-1', 'w'),
			game('squarefish-1000', '0-1', 'w'),
			game('squarefish-1000', '0-1', 'w')
		])!;
		expect(Number.isFinite(est.elo)).toBe(true);
		expect(est.elo).toBeGreaterThan(1000); // above the opponent it keeps beating
		expect(est.elo).toBeLessThan(2900);
	});

	it('abandoned games are excluded', () => {
		expect(estimatePlayerElo([game('squarefish-1000', '*')])).toBeNull();
	});

	it('more games shrink the standard error', () => {
		const two = estimatePlayerElo([
			game('squarefish-1200', '0-1', 'w'),
			game('squarefish-1200', '1-0', 'w')
		])!;
		const eight = estimatePlayerElo(
			Array.from({ length: 8 }, (_, i) => game('squarefish-1200', i % 2 ? '0-1' : '1-0', 'w'))
		)!;
		expect(eight.se).toBeLessThan(two.se);
	});
});

describe('takeback exclusion', () => {
	it('assisted games (takebacks used) are off the ruler', async () => {
		const { estimatePlayerElo } = await import('./playerElo');
		const g = {
			id: 't-undo',
			endedAt: '2026-07-15T00:00:00Z',
			result: '0-1',
			pgn: '',
			botElo: 0,
			botPersona: 'maia-s-1500',
			botUndos: 1,
			botColor: 'w' as const,
			moveCount: 40,
			whiteAccuracy: null,
			blackAccuracy: null,
			labelCounts: { w: {}, b: {} },
			moves: []
		};
		expect(estimatePlayerElo([g])).toBeNull();
	});
});

describe('fallback exclusion', () => {
	it('games where the stand-in moved are off the ruler', async () => {
		const { estimatePlayerElo } = await import('./playerElo');
		const g = {
			id: 't-fb',
			endedAt: '2026-07-15T00:00:00Z',
			result: '0-1',
			pgn: '',
			botElo: 0,
			botPersona: 'retro-bernstein-2',
			botFallback: true,
			botColor: 'w' as const,
			moveCount: 30,
			whiteAccuracy: null,
			blackAccuracy: null,
			labelCounts: { w: {}, b: {} },
			moves: []
		};
		expect(estimatePlayerElo([g])).toBeNull();
	});
});
