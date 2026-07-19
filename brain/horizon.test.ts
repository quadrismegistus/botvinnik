import { describe, it, expect } from 'vitest';
import { Chess } from 'chess.js';
import { horizonMove } from './horizon';
import { horizonUci } from './horizonUci';

// js-chess-engine picks among equal-scoring moves at random, so none of these
// can assert WHICH move comes back — only that whatever comes back is a move
// the position actually allows, spelled the way UCI wants it.
//
// Every FEN below is CHECKED against chess.js rather than described in a
// comment. Three hand-written FENs in this file have already turned out to be
// something other than what their comment claimed (a fool's mate labelled "in
// check", a stalemate labelled "not mate", a stalemate labelled "checkmate"),
// so the position's nature is now asserted, not asserted-by-comment.
const RUNS = 12;

function legalUcis(fen: string): Set<string> {
	return new Set(
		new Chess(fen).moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ''))
	);
}

/** Fails loudly if a FEN stops being the kind of position the test needs. */
function assertPosition(
	fen: string,
	want: { check?: boolean; mate?: boolean; stalemate?: boolean; minMoves?: number }
) {
	const c = new Chess(fen);
	if (want.check !== undefined) expect(c.inCheck(), `${fen} inCheck`).toBe(want.check);
	if (want.mate !== undefined) expect(c.isCheckmate(), `${fen} isCheckmate`).toBe(want.mate);
	if (want.stalemate !== undefined)
		expect(c.isStalemate(), `${fen} isStalemate`).toBe(want.stalemate);
	if (want.minMoves !== undefined)
		expect(c.moves().length, `${fen} legal moves`).toBeGreaterThanOrEqual(want.minMoves);
}

describe('horizonMove', () => {
	it.each([
		['opening', 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 1],
		['open middlegame', 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1', 2],
		['in check with three ways out', 'r1bq2r1/p1p1k2p/1p1ppppn/2b1P1N1/8/P2P1P2/1Bn3PP/R2QKBNR w KQ - 0 14', 1],
		['castling available', 'r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1', 2],
		['en passant available', 'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3', 1],
		['endgame', '8/5k2/8/8/3K4/8/4P3/8 w - - 0 1', 2]
	])('plays a legal move: %s', (_name, fen, level) => {
		assertPosition(fen, { minMoves: 1 });
		const legal = legalUcis(fen);
		for (let i = 0; i < RUNS; i++) {
			const uci = horizonMove(fen, level);
			expect(uci, 'a position with legal moves must produce one').not.toBeNull();
			expect(legal, `${uci} is not legal here`).toContain(uci!);
		}
	});

	it('spells a promotion out, and queens rather than underpromoting', () => {
		const fen = '8/P6k/8/8/8/8/6K1/8 w - - 0 1';
		// chess.js orders promotions n, b, r, q — the bug this guards against is
		// reading the piece off the FIRST match, which is the knight
		expect(new Chess(fen).moves({ verbose: true }).find((m) => m.promotion)!.promotion).toBe('n');
		expect(horizonMove(fen, 1)).toBe('a7a8q');
	});

	it('returns null on a finished game — checkmate AND stalemate', () => {
		const mate = 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3';
		const stalemate = '7k/5Q2/6K1/8/8/8/8/8 b - - 0 1';
		assertPosition(mate, { check: true, mate: true });
		assertPosition(stalemate, { check: false, mate: false, stalemate: true });
		expect(horizonMove(mate, 1)).toBeNull();
		expect(horizonMove(stalemate, 1)).toBeNull();
		// sanity: the same shape WITH a legal move must still produce one
		assertPosition('7k/5Q1p/8/8/8/8/8/6K1 b - - 0 1', { stalemate: false, minMoves: 1 });
		expect(horizonMove('7k/5Q1p/8/8/8/8/8/6K1 b - - 0 1', 1)).not.toBeNull();
	});

	it('returns null rather than throwing on a level it was never given', () => {
		// the bridge passes `jsceLevel ?? 1`; a persona edited to something odd
		// must degrade, and a throw here would cross to Dart as a StateError on
		// the bot's turn. Assert the VALUE, not just the absence of a throw —
		// otherwise this passes even if every level returns null.
		const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
		for (const level of [0, -1, 99, NaN]) {
			expect(horizonMove(start, level)).toBeNull();
		}
		expect(horizonMove(start, 1)).not.toBeNull(); // the control
	});

	it('never throws on a malformed position, however malformed', () => {
		// a throw crosses the bridge as a StateError and wedges the bot's turn,
		// so this is the contract that matters most, not the return value
		for (const fen of [
			'',
			' ',
			'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1 ', // trailing space
			'not a fen at all',
			'8/8/8/8/8/8/8/8 w - - 0 1', // no kings
			'P7/8/8/8/8/8/8/K6k w - - 0 1', // pawn on the back rank
			'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR' // truncated
		]) {
			expect(() => horizonMove(fen, 1), `threw on ${JSON.stringify(fen)}`).not.toThrow();
		}
	});
});

describe('horizonUci', () => {
	it('spells castling as the king move, not the rook swap', () => {
		const fen = 'r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1';
		assertPosition(fen, { minMoves: 1 });
		expect(horizonUci(fen, 'E1', 'G1')).toBe('e1g1');
		expect(horizonUci(fen, 'E1', 'C1')).toBe('e1c1');
	});

	it('spells en passant as a plain pawn move', () => {
		expect(horizonUci('rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3', 'E5', 'F6'))
			.toBe('e5f6');
	});

	it('accepts the uppercase squares js-chess-engine actually emits', () => {
		expect(horizonUci('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'G1', 'F3'))
			.toBe('g1f3');
	});

	it('returns null for a move the position does not allow', () => {
		const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
		expect(horizonUci(start, 'E2', 'E5')).toBeNull();
		expect(horizonUci(start, 'D4', 'D5')).toBeNull(); // empty origin square
	});

	it('does not throw on a malformed fen', () => {
		expect(() => horizonUci('', 'E2', 'E4')).not.toThrow();
		expect(horizonUci('', 'E2', 'E4')).toBeNull();
	});
});
