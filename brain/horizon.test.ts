import { describe, it, expect } from 'vitest';
import { Chess } from 'chess.js';
import { horizonMove } from './horizon';

// js-chess-engine picks among equal-scoring moves at random, so none of these
// can assert WHICH move comes back — only that whatever comes back is a move
// the position actually allows, spelled the way UCI wants it. Each case runs
// several times because a one-shot pass would not notice an illegal move that
// only appears on some branches.
const RUNS = 12;

function legalUcis(fen: string): Set<string> {
	return new Set(
		new Chess(fen).moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ''))
	);
}

describe('horizonMove', () => {
	it.each([
		['opening', 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 1],
		['open middlegame', 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1', 2],
		['in check with three ways out', 'r1bq2r1/p1p1k2p/1p1ppppn/2b1P1N1/8/P2P1P2/1Bn3PP/R2QKBNR w KQ - 0 14', 1],
		['endgame', '8/5k2/8/8/3K4/8/4P3/8 w - - 0 1', 2]
	])('plays a legal move: %s', (_name, fen, level) => {
		const legal = legalUcis(fen);
		for (let i = 0; i < RUNS; i++) {
			const uci = horizonMove(fen, level);
			expect(uci, 'a position with legal moves must produce one').not.toBeNull();
			expect(legal, `${uci} is not legal here`).toContain(uci!);
		}
	});

	it('spells a promotion out, because js-chess-engine does not', () => {
		// the only legal pawn move is a7a8, and it must promote
		const uci = horizonMove('8/P6k/8/8/8/8/6K1/8 w - - 0 1', 1);
		expect(uci).toBe('a7a8q');
	});

	it('returns null rather than inventing a move when there are none', () => {
		expect(horizonMove('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1', 1)).toBeNull(); // checkmate
		expect(horizonMove('7k/5Q2/8/8/8/8/8/6K1 b - - 0 1', 1)).toBeNull(); // stalemate
		// sanity: the same shape WITH a legal move must still produce one
		expect(horizonMove('7k/5Q1p/8/8/8/8/8/6K1 b - - 0 1', 1)).not.toBeNull();
	});

	it('survives a level it was never given', () => {
		// the bridge passes `jsceLevel ?? 1`; a persona edited to something odd
		// should degrade rather than throw across the boundary
		expect(() => horizonMove('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 0))
			.not.toThrow();
	});
});
