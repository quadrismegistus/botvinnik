// How often you played the engine's own first choice (#276).
//
// The number sits beside accuracy because the two disagree usefully: accuracy
// is dominated by the worst move in the game, so one blunder buries forty good
// ones, while this counts how often you actually saw it.
import { describe, expect, it } from 'vitest';

import { Chess } from 'chess.js';

import { engineCorrelation, type StoredMove } from './gameStore';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const AFTER_E4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

/** A graded move: what was played, and what the engine wanted.
 *
 * `topRecorded` by default, because that is what a live game and a chess.com
 * import both write — the writer searched every position and recorded the
 * engine's move on every ply. Pass it explicitly as undefined for a lichess
 * import, where an absent bestUci means only that no judgment fired. */
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
		topRecorded: true,
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

	it('refuses a game whose writer did not record the top move every ply', () => {
		// A lichess import: `best` is present only where a judgment fired, so
		// every bestUci marks a MISS and a match carries nothing at all.
		// Counting those printed "0 of 39" under every analysed game in a real
		// 500-game archive — 15,765 moves carried a bestUci and exactly 0 of
		// them matched. Without the promise, the absence means nothing.
		const lichess = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'd2d4', fenBefore: START, topRecorded: undefined }),
			move({ color: 'w', uci: 'g1f3', bestUci: 'b1c3', fenBefore: START, topRecorded: undefined })
		];
		expect(engineCorrelation(lichess, 'w')).toBeNull();
	});

	it('counts the same moves once the writer does promise it', () => {
		// the control: identical records, with the promise present
		const graded = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'd2d4', fenBefore: START }),
			move({ color: 'w', uci: 'g1f3', bestUci: 'g1f3', fenBefore: START })
		];
		expect(engineCorrelation(graded, 'w')).toEqual({ played: 1, total: 2 });
	});

	it('counts a match, which is the whole point and was unreachable before', () => {
		// With `best` written only on a mismatch, `mine === best` could not
		// happen by construction. This is the case that used to be impossible.
		const matched = [move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START })];
		expect(engineCorrelation(matched, 'w')).toEqual({ played: 1, total: 1 });
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

	it('excludes a move whose ENGINE move is the unreadable one', () => {
		// the other arm of the unreadable guard. Without it a record whose
		// bestUci does not fit its position is counted as a MISS, scoring the
		// player down for the engine's bad data.
		const moves = [
			move({ color: 'w', uci: 'e2e4', bestUci: 'e2e4', fenBefore: START }),
			move({ color: 'w', uci: 'd2d4', bestUci: 'h7h8', fenBefore: START })
		];
		expect(engineCorrelation(moves, 'w')).toEqual({ played: 1, total: 1 });
	});

	it('does not rewrite a king CAPTURING an enemy rook on the a-file', () => {
		// Kb1xa1 is the one shape where the colour test is the only thing
		// standing between a king capture and a rewritten "O-O-O": the square is
		// on the a-file and holds a rook, so the file and type tests both pass.
		const fen = '4k3/8/8/8/8/8/8/rK6 w - - 0 1';
		expect(new Chess(fen).move({ from: 'b1', to: 'a1' }).san).toBe('Kxa1');
		expect(
			engineCorrelation([move({ color: 'w', uci: 'b1a1', bestUci: 'b1a1', fenBefore: fen })], 'w')
		).toEqual({ played: 1, total: 1 });
	});

	it('does not rewrite a king capturing a QUEEN on the a-file', () => {
		// same square, same file, not a rook — so here the type test is the only
		// refusal, and dropping it rewrites Kxa1 into a castle that never was
		const fen = '4k3/8/8/8/8/8/8/qK6 w - - 0 1';
		expect(new Chess(fen).move({ from: 'b1', to: 'a1' }).san).toBe('Kxa1');
		expect(
			engineCorrelation([move({ color: 'w', uci: 'b1a1', bestUci: 'b1a1', fenBefore: fen })], 'w')
		).toEqual({ played: 1, total: 1 });
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
