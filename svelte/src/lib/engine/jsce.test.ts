import { describe, it, expect } from 'vitest';
import { Chess } from 'chess.js';
import { jsceMove } from './jsce';

// The web's Horizon path. Its move→UCI half is shared with the brain's bundled
// copy and tested thoroughly in brain/horizonUci.test cases; what is left here
// is this file's own contract — the dynamic import resolves, and a position
// the library refuses degrades to null instead of throwing into the bot loop.
//
// Non-deterministic (js-chess-engine breaks ties at random), so these assert
// legality, never a particular move.

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

describe('jsceMove', () => {
	it('resolves the lazy import and returns a legal move', async () => {
		const legal = new Chess(START)
			.moves({ verbose: true })
			.map((m) => m.from + m.to + (m.promotion ?? ''));
		for (let i = 0; i < 6; i++) {
			expect(legal).toContain(await jsceMove(START, 1));
		}
	});

	it('queens a promotion rather than underpromoting', async () => {
		expect(await jsceMove('8/P6k/8/8/8/8/6K1/8 w - - 0 1', 1)).toBe('a7a8q');
	});

	it('returns null on a finished game instead of throwing', async () => {
		const mate = 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3';
		expect(new Chess(mate).isCheckmate(), 'the fixture must really be mate').toBe(true);
		await expect(jsceMove(mate, 1)).resolves.toBeNull();
	});

	it('returns null on a malformed position instead of throwing', async () => {
		// the caller treats null as "fall back to Stockfish"; a rejection would
		// escape into the bot reply loop instead
		for (const fen of ['', 'not a fen', `${START} `]) {
			await expect(jsceMove(fen, 1), `on ${JSON.stringify(fen)}`).resolves.toBeNull();
		}
	});

	it('returns null for a level the library rejects', async () => {
		await expect(jsceMove(START, 0)).resolves.toBeNull();
		await expect(jsceMove(START, 1)).resolves.not.toBeNull(); // control
	});
});
