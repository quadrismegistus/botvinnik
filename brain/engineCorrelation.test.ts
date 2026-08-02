// How often you played the engine's own first choice (#276).
//
// The number sits beside accuracy because the two disagree usefully: accuracy
// is dominated by the worst move in the game, so one blunder buries forty good
// ones, while this counts how often you actually saw it.
import { describe, expect, it } from 'vitest';

import { engineCorrelation, type StoredMove } from './gameStore';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const AFTER_E4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

/** A graded move: what was played, and what the engine wanted. */
function move(
	over: Partial<StoredMove> & { color: 'w' | 'b'; uci: string; fenBefore: string }
): StoredMove {
	return {
		ply: 1,
		san: '',
		fenAfter: '',
		evalPawns: 0,
		mate: null,
		pctBest: 100,
		wcDrop: 0,
		depth: 12,
		...over
	} as StoredMove;
}

describe('engineCorrelation', () => {
	it('counts the moves that matched the engine top line', () => {
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START }),
			move({ color: 'b', uci: 'e7e5', bestUci: 'e7e5', fenBefore: AFTER_E4 }),
			move({ color: 'w', uci: 'd2d4', bestUci: 'g1f3', fenBefore: START })
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 1, total: 2 });
		expect(engineCorrelation(moves, 'b')).toEqual({ played: 1, total: 1 });
	});

	it('is null when nothing could be counted, rather than zero', () => {
		// an import that was never analysed: the question was never asked
		const moves = [move({ color: 'w', uci: 'e2e4', fenBefore: START })];
		expect(engineCorrelation(moves, 'w')).toBeNull();
	});

	it('ignores a move the engine never judged', () => {
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START }),
			move({ color: 'w', uci: 'd2d4', fenBefore: START }) // no bestUci
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 1, total: 1 });
	});

	it('refuses an IMPORTED game, where bestUci means the opposite thing', () => {
		// chesscomCore writes `best` only when the played move was NOT the top
		// choice, and lichess's is "present on flagged moves" — so on an import
		// a bestUci marks a MISS and a match carries nothing at all. Reading it
		// as the engine's answer printed "0 of 39" under every imported game in
		// the 500-game archive: 15,765 moves carry one and 0 of them match.
		// pctBest is null on every one of those moves, and non-null on every
		// move this app graded itself.
		const imported = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'd2d4', fenBefore: START, pctBest: null }),
			move({ color: 'w', uci: 'g1f3', bestUci: 'b1c3', fenBefore: START, pctBest: null })
		];
		expect(engineCorrelation(imported, 'w')).toBeNull();
	});

	it('counts the same moves once the app has graded them itself', () => {
		// the control: identical records, with the grading signal present
		const graded = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'd2d4', fenBefore: START, pctBest: 88 }),
			move({ color: 'w', uci: 'g1f3', bestUci: 'g1f3', fenBefore: START, pctBest: 100 })
		];
		expect(engineCorrelation(graded, 'w')).toEqual({ played: 1, total: 2 });
	});

	it('skips a record chess.js cannot set up, without losing the game', () => {
		// this used to throw out of the whole function — and the caller is a
		// widget build method, so that is a red screen rather than a missing row
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START }),
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: 'not a fen at all' })
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 1, total: 1 });
	});

	it('does not count a forced move that happens to be a promotion', () => {
		// chess.moves() expands one promotion into four, so a length test reads
		// four choices where the board offers one
		const forcedPromo = '1r6/7P/7k/8/8/8/1r6/K7 w - - 0 1';
		expect(
			engineCorrelation(
				[move({ color: 'w', uci: 'h7h8q', bestUci: 'h7h8q', fenBefore: forcedPromo })],
				'w'
			)
		).toBeNull();
	});

	it('does not read a king move onto some other friendly rook as castling', () => {
		// a rook on f1 is not a castling rook; rewriting e1f1 to e1c1 scored a
		// match for a move nobody made
		const fen = '4k3/8/8/8/8/8/8/R3KR2 w Q - 0 1';
		expect(
			engineCorrelation([move({ color: 'w', uci: 'e1f1', bestUci: 'e1c1', fenBefore: fen })], 'w')
		).toBeNull();
	});

	it('does not count a position with only one legal move', () => {
		// the whole point of the exclusion: a game of forced recaptures would
		// otherwise read 100% and mean nothing
		// Kxg2 is the ONLY legal move — and it has to be the move in the fixture,
		// or the record is refused as unreadable and the forced-position rule is
		// never reached at all
		const forced = '7k/8/8/8/8/8/6q1/7K w - - 0 1';
		expect(engineCorrelation([move({ color: 'w', uci: 'h1g2', bestUci: 'h1g2', fenBefore: forced })], 'w'))
			.toBeNull();
	});

	it('still counts a position with two legal moves', () => {
		// the control: one square either side of the boundary
		const two = '7k/8/8/8/8/8/8/q6K w - - 0 1'; // Kh2 or Kg2
		expect(engineCorrelation([move({ color: 'w', uci: 'h1h2', bestUci: 'h1h2', fenBefore: two })], 'w'))
			.toEqual({ played: 1, total: 1 });
	});

	it('matches castling however the archive spelled it', () => {
		// dartchess normalises to king-takes-rook (e1h1); the lichess and
		// chess.com importers write king-two-squares (e1g1). Comparing the raw
		// strings scored every castling move as a miss.
		const fen = 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1';
		const both = engineCorrelation(
			[move({ color: 'w', uci: 'e1g1', bestUci: 'e1h1', fenBefore: fen })],
			'w'
		);
		expect(both).toEqual({ played: 1, total: 1 });
	});

	it('matches QUEENSIDE castling in the takes-rook spelling too', () => {
		// e1a1 must become O-O-O, not O-O: normalising every castle to the king
		// side scores the same and only this direction catches it
		const fen = 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1';
		expect(
			engineCorrelation([move({ color: 'w', uci: 'e1c1', bestUci: 'e1a1', fenBefore: fen })], 'w')
		).toEqual({ played: 1, total: 1 });
	});

	it('does not credit a different castling side as a match', () => {
		const fen = 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1';
		expect(
			engineCorrelation([move({ color: 'w', uci: 'e1c1', bestUci: 'e1h1', fenBefore: fen })], 'w')
		).toEqual({ played: 0, total: 1 });
	});

	it('skips a move that does not fit its own position', () => {
		// a corrupt or mis-stitched record: refuse it rather than score it
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START }),
			move({ color: 'w', uci: 'h7h8', bestUci: 'e2e4', fenBefore: START })
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 1, total: 1 });
	});

	it('reads promotions, which carry a fifth character', () => {
		const fen = '8/P6k/8/8/8/8/8/7K w - - 0 1';
		expect(
			engineCorrelation([move({ color: 'w', uci: 'a7a8q', bestUci: 'a7a8q', fenBefore: fen })], 'w')
		).toEqual({ played: 1, total: 1 });
		expect(
			engineCorrelation([move({ color: 'w', uci: 'a7a8n', bestUci: 'a7a8q', fenBefore: fen })], 'w')
		).toEqual({ played: 0, total: 1 });
	});

	it('counts each side only against its own moves', () => {
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'd2d4', fenBefore: START }),
			move({ color: 'b', uci: 'e7e5', bestUci: 'e7e5', fenBefore: AFTER_E4 })
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 0, total: 1 });
		expect(engineCorrelation(moves, 'b')).toEqual({ played: 1, total: 1 });
	});
});
