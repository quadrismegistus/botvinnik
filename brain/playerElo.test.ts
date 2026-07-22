import { describe, it, expect } from 'vitest';
import { estimatePlayerElo } from './playerElo';
import type { StoredGame } from './gameStore';

// A minimal RATED persona game. `rated` is here because since #168 it is the
// gate: a fixture without it fits nothing at all, which is the point — no game
// counts unless the player started it as a rated one.
function game(personaId: string, result: string, botColor: 'w' | 'b' = 'w'): StoredGame {
	return {
		id: `t-${Math.random()}`,
		endedAt: '2026-07-14T00:00:00Z',
		result,
		pgn: '',
		botElo: 0,
		botPersona: personaId,
		rated: true,
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

	it('drops a game both sides of which were bots', () => {
		// #144 stopped these earning a "won clean" crown but not being scored as
		// a human result: playerColor falls back to White when both sides carry a
		// persona, so the record looks like a human White game. Verified against
		// the shipped bundle that an unflagged one is counted, so this pair fails
		// if the fixture never reaches the exclusion.
		const both = { ...game('squarefish-1000', '1-0', 'b'), botBothSides: true };
		expect(estimatePlayerElo([both])).toBeNull();
		expect(estimatePlayerElo([game('squarefish-1000', '1-0', 'b')])).not.toBeNull();
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

	it('counts rated games against downloaded (custom-) engines', () => {
		// A custom engine's id is `custom-<slug>[~style]`, not in bots.ts; its
		// display elo is recorded on the game (botElo is the internal scale =
		// display + SCALE_OFFSET). Three even-ish results vs a 1500-labelled Velvet
		// fit near 1500 -- they now count, where before they were silently dropped.
		const velvet = (result: string): StoredGame => ({
			...game('custom-velvet', result, 'b'),
			botElo: 1500 + 240
		});
		const est = estimatePlayerElo([velvet('1-0'), velvet('0-1'), velvet('1/2-1/2')])!;
		expect(est.games).toBe(3);
		expect(est.elo).toBeGreaterThan(1300);
		expect(est.elo).toBeLessThan(1700);

		// a Rodent STYLE persona (custom-rodent~tal) counts the same way
		const styled = estimatePlayerElo([
			{ ...game('custom-rodent~tal', '1-0', 'b'), botElo: 1200 + 240 }
		]);
		expect(styled?.games).toBe(1);

		// the usual exclusions still apply: a substituted opponent doesn't count
		expect(estimatePlayerElo([{ ...velvet('1-0'), botFallback: true }])).toBeNull();
		// and a legacy slider game (no persona id) still doesn't
		expect(
			estimatePlayerElo([{ ...velvet('1-0'), botPersona: undefined }])
		).toBeNull();
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
			rated: true,
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

describe('rated mode is the gate (#168)', () => {
	it('a game not started as rated never counts, however clean it was', () => {
		// The pair. Same game, same result, same opponent — the ONLY difference
		// is the mode the player chose at the start, and `botHintsUsed: false`
		// on both sides so this cannot be the hint rule firing instead.
		const casual = { ...game('squarefish-1000', '1-0', 'b'), rated: undefined, botHintsUsed: false };
		const rated = { ...game('squarefish-1000', '1-0', 'b'), botHintsUsed: false };
		expect(estimatePlayerElo([casual])).toBeNull();
		expect(estimatePlayerElo([rated])).not.toBeNull();
	});

	it('an archive from before rated mode existed rates nothing', () => {
		// Every game saved before #168 lacks the field, and the discontinuity is
		// the sanctioned half of the decision: a rating that quietly counted a
		// history of assisted games is the thing being fixed.
		const legacy = [
			{ ...game('squarefish-1000', '1-0', 'b'), rated: undefined },
			{ ...game('squarefish-1200', '0-1', 'w'), rated: undefined },
			{ ...game('squarefish-1400', '1/2-1/2'), rated: undefined }
		];
		expect(estimatePlayerElo(legacy)).toBeNull();
	});

	it('rated is not inferred from the help flags being clean', () => {
		// The rejected design: "no hints and no takebacks" read off the record.
		// This game passes every one of those tests and still does not rate,
		// because the player never said it was on the record.
		const clean = {
			...game('squarefish-1000', '1-0', 'b'),
			rated: undefined,
			botHintsUsed: false,
			botUndos: 0,
			botFallback: false,
			botBothSides: false
		};
		expect(estimatePlayerElo([clean])).toBeNull();
	});
});

describe('hint exclusion', () => {
	it('help on the board takes a rated game off the ruler', () => {
		// The pair, and the bug it closes: botHintsUsed has been declared since
		// the archive existed and written since #144, and until #168 nothing
		// read it — arrows, threat rings and square control excluded no game at
		// all. An unpaired fixture would have passed against that code too.
		const helped = { ...game('squarefish-1000', '1-0', 'b'), botHintsUsed: true };
		const blind = { ...game('squarefish-1000', '1-0', 'b'), botHintsUsed: false };
		expect(estimatePlayerElo([helped])).toBeNull();
		expect(estimatePlayerElo([blind])).not.toBeNull();
	});

	it('one helped game drops out of a fit the rest of the archive still makes', () => {
		// The count is what proves the exclusion here: a single refusal inside a
		// surviving fit is invisible in the elo alone.
		const clean = [
			game('squarefish-1000', '1-0', 'b'),
			game('squarefish-1200', '0-1', 'w'),
			game('squarefish-1400', '1-0', 'b')
		];
		expect(estimatePlayerElo(clean)!.games).toBe(3);
		expect(estimatePlayerElo([{ ...clean[0], botHintsUsed: true }, clean[1], clean[2]])!.games).toBe(2);
	});

	it('an absent botHintsUsed does not refuse a rated game', () => {
		// "Hints unknown" is what absence means on a game archived before the
		// field existed — but such a game is not rated either, so this can only
		// arise if the save path ever stops writing the field on a rated game.
		// Refusing on absence would then take every rated game off the ruler
		// silently, which is the failure mode this whole issue is about.
		const unknown = { ...game('squarefish-1000', '1-0', 'b'), botHintsUsed: undefined };
		expect(estimatePlayerElo([unknown])).not.toBeNull();
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
			rated: true,
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
