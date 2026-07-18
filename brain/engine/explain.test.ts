import { describe, expect, it } from 'vitest';
import {
	bestMovePoint,
	discoveredPoint,
	explainGoodMove,
	explainMove,
	materialOverLine,
	motifTags,
	pinOrSkewerPoint,
	promotionPoint,
	sacrificeStory,
	summarizeLine,
	trappedPoint
} from './explain';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

describe('materialOverLine', () => {
	it('is zero over a quiet line', () => {
		expect(materialOverLine(START, ['e2e4', 'e7e5', 'g1f3', 'b8c6'])).toBe(0);
	});

	it('nets a completed exchange from the mover perspective', () => {
		// 1.e4 d5 2.exd5 Qxd5: white wins a pawn, loses a pawn... net for white = 0
		expect(materialOverLine(START, ['e2e4', 'd7d5', 'e4d5', 'd8d5'])).toBe(0);
		// stop after 2.exd5 only: white is up the captured pawn
		expect(materialOverLine(START, ['e2e4', 'd7d5', 'e4d5'])).toBe(1);
	});
});

describe('summarizeLine', () => {
	it('is silent over a quiet line', () => {
		expect(summarizeLine(START, ['e2e4', 'e7e5', 'g1f3'])).toBeUndefined();
	});

	it('narrates an equal trade', () => {
		// white Rd1 takes black Rd8, the e8 rook recaptures, then a quiet move
		const fen = '3rr3/8/8/7k/8/8/8/K2R4 w - - 0 1';
		expect(summarizeLine(fen, ['d1d8', 'e8d8', 'a1b1'])).toBe('rooks are traded on d8');
	});

	it('narrates losing a piece mid-line', () => {
		// black shuffles, white rook grabs the queen, black shuffles again
		const fen = 'q6k/8/8/8/8/8/1K6/R7 b - - 0 1';
		expect(summarizeLine(fen, ['h8h7', 'a1a8', 'h7h6'])).toBe('your queen is taken (Rxa8)');
	});

	it('narrates an unequal exchange', () => {
		// white RxN, black pawn recaptures the rook, then quiet: R for N
		const fen = '7k/2p5/3n4/8/8/8/8/K2R4 w - - 0 1';
		expect(summarizeLine(fen, ['d1d6', 'c7d6', 'a1b1'])).toBe(
			'you give up a rook for a knight on d6'
		);
	});

	it('chains events in order', () => {
		// rook trade on d8, then white picks up the a7 pawn with the other rook
		const fen = '3rr2k/p7/8/8/8/R7/8/K2R4 w - - 0 1';
		expect(summarizeLine(fen, ['d1d8', 'e8d8', 'a3a7', 'h8g8'])).toBe(
			'rooks are traded on d8, then you pick up a pawn (Rxa7)'
		);
	});

	it('never narrates an exchange the horizon cuts open', () => {
		// line ends right after white wins Q for R — the recapture may lie beyond
		const fen = '3r4/8/8/3q3k/8/8/8/K2R4 w - - 0 1';
		expect(summarizeLine(fen, ['d1d5', 'd8d5'])).toBeUndefined();
	});
});

describe('pinOrSkewerPoint', () => {
	it('detects the classic Bg5 pin against the queen', () => {
		// 1.d4 Nf6 2.c4 e6 3.Nc3 d5 and now 4.Bg5
		const fen = 'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4';
		expect(pinOrSkewerPoint(fen, 'c1g5')).toBe(
			'Bg5 pins the knight on f6 against the queen on d8.'
		);
	});

	it('does not call a blocked ray a pin', () => {
		// Bb5 hits the c6 knight, but d7 still holds a PAWN — nothing valuable shielded
		const fen = 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3';
		expect(pinOrSkewerPoint(fen, 'f1b5')).toBeUndefined();
	});

	it('does not call a bare check a pin or skewer', () => {
		// Bb2 hits the king with nothing behind it
		const fen = '7k/8/8/8/8/8/8/B3K3 w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'a1b2')).toBeUndefined();
	});

	it('does not pin against an equal-valued piece', () => {
		// knight shields only another knight
		const fen = '8/6n1/5n2/8/8/8/k7/B6K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'a1b2')).toBeUndefined();
	});

	it('detects a check-skewer winning the piece behind the king', () => {
		const fen = '8/8/8/1qk5/8/8/8/4K2R w K - 0 1';
		expect(pinOrSkewerPoint(fen, 'h1h5')).toBe(
			'Rh5+ skewers the king on c5 against the queen on b5.'
		);
	});

	it('does not skewer when only a pawn hides behind the king', () => {
		const fen = '8/8/8/1pk5/8/8/8/4K2R w K - 0 1';
		expect(pinOrSkewerPoint(fen, 'h1h5')).toBeUndefined();
	});

	it('does not call it a pin when taking the piece behind would lose material', () => {
		// Qb3 "pins" the b5 pawn against the b8 knight — but the knight is
		// rook-defended, so Qxb8 loses queen for knight; nothing is restrained
		const fen = 'rn5k/8/8/1p6/8/8/8/1Q5K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'b1b3')).toBeUndefined();
	});

	it('pins a pawn against an UNDEFENDED knight — the capture behind pays', () => {
		// diagonal ray, so the pawn's push would genuinely expose the knight.
		// (The pinner sits on b3, out of the pawn's reach — the old fixture put
		// it on c4 where dxc4 just wins the bishop, which is no pin at all.)
		const fen = '7k/8/4n3/3p4/8/8/2B5/7K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'c2b3')).toBe(
			'Bb3 pins the pawn on d5 against the knight on e6.'
		);
	});

	it('does not call it a pin when the pinned piece just takes the pinner', () => {
		// lichess 0XocP-style: Rxd8 "pins" the e8 rook against the king, but the
		// pinner is undefended — Rxd8 in reply simply removes it
		const fen = '3rr1k1/8/8/8/8/8/8/3R3K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'd1d8')).toBeUndefined();
	});

	it('never calls a pawn on a file-ray pinned — its pushes stay on the ray', () => {
		// same undefended knight behind, but on the b-FILE: pushing b5-b4 keeps
		// blocking, so nothing is ever exposed
		const fen = '1n5k/8/8/1p6/8/8/8/1Q5K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'b1b3')).toBeUndefined();
	});

	it('still calls a file-pinned pawn pinned against its KING (captures are illegal)', () => {
		const fen = '1k6/8/8/1p6/8/8/8/1Q5K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'b1b3')).toBe('Qb3 pins the pawn on b5 against the king.');
	});

	it('does not check-skewer when the piece behind the king is defended and dearer to take', () => {
		// Rh5+ forces the king aside, but Rxb5 (knight, rook-defended) loses the exchange
		const fen = '8/8/8/rnk5/8/8/8/4K2R w K - 0 1';
		expect(pinOrSkewerPoint(fen, 'h1h5')).toBeUndefined();
	});
});

describe('discoveredPoint', () => {
	it('detects a discovered check', () => {
		const fen = '3k4/8/8/8/3N4/8/8/3R3K w - - 0 1';
		expect(discoveredPoint(fen, 'd4e6')).toBe('Ne6+ discovers check from the rook on d1.');
	});

	it('stays silent when the mover still blocks the ray', () => {
		// the rook slides up its own file — the line to the king never opens
		const fen = '3k4/8/8/8/3R4/8/8/3R3K w - - 0 1';
		expect(discoveredPoint(fen, 'd4d6')).toBeUndefined();
	});

	it('detects a discovered attack on the queen', () => {
		const fen = '3q3k/8/8/8/3B4/8/8/3R3K w - - 0 1';
		expect(discoveredPoint(fen, 'd4b6')).toBe(
			"Bb6 uncovers the rook on d1's attack on the queen on d8."
		);
	});
});

describe('trappedPoint', () => {
	it('detects the classic trapped bishop', () => {
		// b6 attacks Ba7; b8 is covered by the rook, Bxb6 runs into axb6.
		// (Ne8 blocks the back rank so the rook is not already checking, and is
		// itself correctly NOT a trap candidate — its attacker is not cheaper.)
		const fen = 'R3n1k1/b7/8/PP6/8/8/8/6K1 w - - 0 1';
		expect(trappedPoint(fen, 'b5b6')).toBe(
			'b6 traps the bishop on a7 — it has no safe square.'
		);
	});

	it('stays silent when an escape square is defended', () => {
		// black Rc8 defends b8: Bb8 survives, so nothing is trapped
		const fen = 'R1r3k1/b7/8/PP6/8/8/8/6K1 w - - 0 1';
		expect(trappedPoint(fen, 'b5b6')).toBeUndefined();
	});

	it('stays silent when a genuinely safe square exists', () => {
		// no rook on a8: b8 is free
		const fen = '6k1/b7/8/PP6/8/8/8/6K1 w - - 0 1';
		expect(trappedPoint(fen, 'b5b6')).toBeUndefined();
	});

	it('an escape attacked only by the king but defended is SAFE, not trapped', () => {
		// b4 hits the a5 knight; b7/c6/c4 are covered, but b3 is guarded only by
		// the white king and the a4 pawn defends it — Nb3 survives (Kxb3 is
		// illegal against a defended piece)
		const fen = '1R6/6k1/8/n2P4/p7/1P1P4/1K6/8 w - - 0 1';
		expect(trappedPoint(fen, 'b3b4')).toBeUndefined();
	});

	it('an escape attacked only by the king and UNDEFENDED is unsafe — trapped', () => {
		// same position without the a4 pawn: the king simply takes on b3
		const fen = '1R6/6k1/8/n2P4/8/1P1P4/1K6/8 w - - 0 1';
		expect(trappedPoint(fen, 'b3b4')).toBe('b4 traps the knight on a5 — it has no safe square.');
	});
});

describe('motifTags', () => {
	it('tags a pin', () => {
		const fen = 'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4';
		expect(motifTags(fen, 'c1g5', ['c1g5'], null)).toEqual(['pin']);
	});

	it('tags a free capture and mate together', () => {
		const fen = 'k7/3q4/8/8/8/8/3R4/K7 w - - 0 1';
		expect(motifTags(fen, 'd2d7', ['d2d7', 'a8b8'], 5)).toEqual(['mate', 'free capture']);
	});

	it('returns no tags for a quiet developing move', () => {
		const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
		expect(motifTags(START, 'e2e4', ['e2e4', 'e7e5', 'g1f3'], null)).toEqual([]);
	});

	it('does not call it a fork when the forker itself can be taken by a pawn', () => {
		// Nd5 "forks" the c7 queen and f6 rook, but exd5 just removes the knight
		const fen = '7k/2q5/4pr2/8/5N2/8/8/7K w - - 0 1';
		expect(motifTags(fen, 'f4d5', ['f4d5'], null)).toEqual([]);
	});

	it('still tags a fork when the forker is defended and nothing cheaper attacks it', () => {
		// Nd5 (guarded by the e4 pawn, hunted only by the equal-value b4 knight)
		// forks the queen and the rook
		const fen = '7k/2q5/5r2/8/1n2PN2/8/8/7K w - - 0 1';
		expect(motifTags(fen, 'f4d5', ['f4d5'], null)).toContain('fork');
	});
});

describe('explainMove', () => {
	it('names an allowed mate with the mating move', () => {
		// after 1.f3 e5, playing 2.g4 allows Qh4#
		const fenBefore = 'rnbqkbnr/pppp1ppp/8/4p3/8/5P2/PPPPP1PP/RNBQKBNR w KQkq - 0 2';
		const out = explainMove({
			fenBefore,
			playedUci: 'g2g4',
			refutationPv: ['d8h4'],
			bestUci: 'b1c3',
			bestPv: ['b1c3'],
			playedMate: -1,
			bestMate: null,
			isBest: false
		});
		expect(out.playedIssue).toBe('This allows immediate mate — Qh4#.');
	});

	it('spots a piece left hanging with zero defenders', () => {
		// white queen wanders to h5 where only Nf6 attacks it and nothing defends it
		const fenBefore = 'rnbqkb1r/pppp1ppp/5n2/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 3';
		const out = explainMove({
			fenBefore,
			playedUci: 'd1h5',
			refutationPv: ['f6h5'],
			bestUci: 'g1f3',
			bestPv: ['g1f3'],
			playedMate: null,
			bestMate: null,
			isBest: false
		});
		expect(out.playedIssue).toBe('This leaves the queen on h5 undefended — Nxh5 just takes it.');
	});

	it('returns no claims for the best move', () => {
		const out = explainMove({
			fenBefore: START,
			playedUci: 'e2e4',
			refutationPv: ['e7e5'],
			bestUci: 'e2e4',
			bestPv: ['e2e4'],
			playedMate: null,
			bestMate: null,
			isBest: true
		});
		expect(out).toEqual({});
	});
});

describe('explainGoodMove', () => {
	it('does not claim material won when the PV window ends mid-exchange', () => {
		// regression: 1.d4 once claimed "+3" because the 9-ply count window ended
		// on Bxf6 with the recapture exf6 just past the cut
		const pv = [
			'd2d4', 'd7d5', 'b1c3', 'g8f6', 'c1g5', 'b8c6', 'e2e3', 'h7h6',
			'g5f6', // ply 9: Bxf6 (+3 inside the window)
			'e7f6' // ply 10: exf6 (the recapture the old code never saw)
		];
		expect(explainGoodMove(START, 'd2d4', pv, null)).toBeUndefined();
	});

	it('credits a genuinely free capture, with its evidence line', () => {
		// lone rook takes an undefended queen
		const fen = 'k7/3q4/8/8/8/8/3R4/K7 w - - 0 1';
		const point = explainGoodMove(fen, 'd2d7', ['d2d7', 'a8b8'], null);
		expect(point?.text).toBe("Rxd7 simply wins the queen — it's undefended.");
		expect(point?.evidence).toEqual({ fen, ucis: ['d2d7'] });
	});

	it('describes a forced mate', () => {
		// back-rank: 1.f3 e5 2.g4 and black to play Qh4#
		const fen = 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2';
		expect(explainGoodMove(fen, 'd8h4', ['d8h4'], 1)?.text).toBe('Qh4# is checkmate.');
	});

	it('says checkmate even when engine mate info is missing', () => {
		const fen = 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2';
		expect(explainGoodMove(fen, 'd8h4', ['d8h4'], null)?.text).toBe('Qh4# is checkmate.');
	});
});

// Puzzle-audit regressions (explain-audit.mts vs lichess themes): the
// geometric detectors used to narrate side facts about mating moves —
// "Qxh7# traps the knight on d5" is true and absurd. A move that mates ends
// the game; only the mate claim stands.
describe('mating moves stay silent in the motif detectors', () => {
	// lichess bEOuz: Qxh7# — the knight on d5 really is trapped, but who cares
	const QXH7 = 'r2q1rk1/pppn1ppp/3b4/3n2N1/2BP1pb1/3Q4/PPP3PP/R1B2RK1 w - - 0 12';
	// lichess TUczR: Qxf7# — geometrically pins the c7 pawn against the b7 bishop
	const F7 = 'r2qkb1r/pbp2ppp/1p2pn2/3pN2Q/8/1P2P3/PBPP1PPP/RN2K2R w KQkq - 2 9';
	// lichess NywjU: Rd1# — "forks" the c1 bishop and the g1 king
	const BACKRANK = '4r1k1/p2r3p/2p3p1/4p3/1P3p1Q/P6R/5PPP/2B3K1 b - - 0 33';

	it('trappedPoint stays quiet on a mating move', () => {
		expect(trappedPoint(QXH7, 'd3h7')).toBeUndefined();
	});

	it('pinOrSkewerPoint stays quiet on a mating move', () => {
		expect(pinOrSkewerPoint(F7, 'h5f7')).toBeUndefined();
	});

	it('motifTags returns only mate facts, detected from the board itself', () => {
		expect(motifTags(BACKRANK, 'd7d1', ['d7d1'], null)).toEqual(['mate', 'back-rank mate']);
		expect(motifTags(QXH7, 'd3h7', ['d3h7'], null)).toEqual(['mate']);
	});

	it('motifTags drops restraint side facts on the first move of a longer mate', () => {
		// lichess p6sNk: Rd1+ starts mate in 2 — and incidentally "traps" the b2
		// rook, which must not become the drill tag
		const fen = '3k4/p2r2p1/Pp3p2/4b2p/8/4Q3/1R3PPP/6K1 b - - 0 33';
		expect(motifTags(fen, 'd7d1', ['d7d1', 'e3e1', 'd1e1'], 2)).toEqual([
			'mate',
			'back-rank mate'
		]);
	});

	it('motifTags keeps the move-own-action tag inside a mate line', () => {
		// lichess Gfes3: Ra1+ genuinely forks the a7 bishop and the king while
		// starting mate in 3 — a fine fork drill, cook.py co-tags it too
		const fen = '3R1bk1/B4p1p/2B3p1/8/4b3/4R1P1/r4P1P/6K1 b - - 0 23';
		const tags = motifTags(fen, 'a2a1', ['a2a1', 'd8d1', 'a1d1', 'e3e1', 'd1e1'], 3);
		expect(tags).toContain('mate');
		expect(tags).toContain('fork');
		expect(tags).not.toContain('trapped piece');
	});

	it('bestMovePoint reports the mate instead of a side motif', () => {
		expect(bestMovePoint(QXH7, 'd3h7', ['d3h7'])).toBe('Qxh7# is checkmate.');
	});

	it('check that is NOT mate still gets its motif', () => {
		// Nc7+ forking king and queen — the classic royal fork
		const fen = 'q3k3/8/8/1N6/8/8/8/4K3 w - - 0 1';
		expect(motifTags(fen, 'b5c7', ['b5c7'], null)).toContain('fork');
	});
});

describe('mate patterns, promotion, sacrifice', () => {
	it('names a back-rank mate', () => {
		// lichess NywjU: Rd1# against a king boxed in by f2/g2/h2
		const fen = '4r1k1/p2r3p/2p3p1/4p3/1P3p1Q/P6R/5PPP/2B3K1 b - - 0 33';
		expect(bestMovePoint(fen, 'd7d1', ['d7d1'])).toBe(
			'Rd1# is checkmate — a back-rank mate.'
		);
	});

	it('names a smothered mate', () => {
		// Philidor's finish: Nf7# against a king boxed in by its own rook and pawns
		const fen = '6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1';
		expect(bestMovePoint(fen, 'g5f7', ['g5f7'])).toBe('Nf7# is checkmate — a smothered mate.');
		expect(motifTags(fen, 'g5f7', ['g5f7'], null)).toEqual(['mate', 'smothered mate']);
	});

	it('does not call it back-rank when the escape squares are merely covered, not blocked', () => {
		// ladder mate: Re8# with g7/h7 EMPTY (covered by the b7 rook) — a mate,
		// but not the trapped-behind-your-own-pawns pattern
		const fen = '7k/1R6/8/8/8/8/8/K3R3 w - - 0 1';
		expect(bestMovePoint(fen, 'e1e8', ['e1e8'])).toBe('Re8# is checkmate.');
	});

	it('narrates a line that promotes', () => {
		// lichess vsPvD: Rxb8 Rxb8 c2 Rd8 c1=Q — previously narrated as bare
		// material, but the point is the new queen
		const fen = 'RQ6/5pk1/4b2p/5p2/5P2/2p2BKP/1r4P1/8 b - - 0 40';
		expect(bestMovePoint(fen, 'b2b8', ['b2b8', 'a8b8', 'c3c2', 'b8d8', 'c2c1q'])).toBe(
			'Rxb8 Rxb8 c2 Rd8 c1=Q makes a new queen.'
		);
	});

	it('no promotion claim when the new piece is immediately captured', () => {
		// e8=Q Rxe8 is just a trade, not a new queen
		const fen = '3r4/4P3/8/8/8/8/8/k3K3 w - - 0 1';
		expect(promotionPoint(fen, ['e7e8q', 'd8e8'])).toBeUndefined();
	});

	it('tells the queen-sacrifice mate story', () => {
		// Qxd8! Rxd8 Rxd8# — give the queen, mate on the back rank (queen and
		// rook batteried on the d-file)
		const fen = '3r1rk1/5ppp/8/8/8/8/3Q4/3R2K1 w - - 0 1';
		const pv = ['d2d8', 'f8d8', 'd1d8'];
		const out = explainMove({
			fenBefore: fen,
			playedUci: 'g1h1',
			refutationPv: [],
			bestUci: 'd2d8',
			bestPv: pv,
			playedMate: null,
			bestMate: 2,
			isBest: false
		});
		expect(out.bestPoint).toBe(
			'Qxd8 sacrifices the queen and forces mate in 2 — a back-rank mate.'
		);
		expect(motifTags(fen, 'd2d8', pv, 2)).toEqual(['mate', 'back-rank mate', 'sacrifice']);
	});

	it('tells a material sacrifice story without engine mate info', () => {
		expect(sacrificeStory('3r1rk1/5ppp/8/8/8/8/3Q4/3R2K1 w - - 0 1', ['d2d8', 'f8d8', 'd1d8']))
			.toMatchObject({ piece: 'queen', mates: true });
	});

	it('uncovers a discovered attack on an EQUAL but undefended piece', () => {
		// Ne3 clears the d-file: rook d1 hits the undefended rook d8
		const fen = '3r3k/8/8/3N4/8/8/8/3R2K1 w - - 0 1';
		expect(discoveredPoint(fen, 'd5e3')).toBe(
			"Ne3 uncovers the rook on d1's attack on the rook on d8."
		);
	});
});

describe('the one-pawn material tier', () => {
	it('names a clean pawn loss (the modal amateur mistake)', () => {
		// d3?? just feeds the d-pawn to exd3, with quiet play after
		const fen = 'k7/8/8/8/4p3/8/3P4/K7 w - - 0 1';
		const out = explainMove({
			fenBefore: fen,
			playedUci: 'd2d3',
			refutationPv: ['e4d3', 'a1b1', 'a8b8'],
			bestUci: 'a1b1',
			bestPv: ['a1b1'],
			playedMate: null,
			bestMate: null,
			isBest: false
		});
		expect(out.playedIssue).toMatch(/^This loses a pawn — after .*, you're a pawn down\.$/);
	});

	it('says the best move wins a pawn', () => {
		// exd5 grabs the pawn; quiet play follows, nothing recaptures
		const fen = 'k7/8/8/3p4/4P3/8/8/K7 w - - 0 1';
		expect(bestMovePoint(fen, 'e4d5', ['e4d5', 'a8b7', 'a1b1'])).toMatch(
			/^Instead, exd5.* wins a pawn\.$/
		);
	});
});

// Adversarial-review regressions: positions where earlier versions of the
// detectors produced prose that LIED about the position.
describe('claims that used to lie', () => {
	it('a promotion trade is not a queen sacrifice', () => {
		// c8=Q Rxc8 Rxc8+ invests a pawn and wins a rook — the old net treated
		// Rxc8 as a −9 queen sacrifice because promotions went uncounted
		const fen = '3r3k/2P5/8/8/8/8/8/2R4K w - - 0 1';
		const pv = ['c7c8q', 'd8c8', 'c1c8', 'h8h7'];
		expect(sacrificeStory(fen, pv)).toBeUndefined();
		expect(bestMovePoint(fen, 'c7c8q', pv)).toContain('wins 4 points of material');
	});

	it('queen-for-rook-and-knight (net −1) is not "a pawn"', () => {
		// Qxd5?? Rxd5 Rxd5 sums to −1 with no pawn anywhere in the line
		const fen = '3r3k/8/8/3n3Q/8/8/8/3R3K w - - 0 1';
		const out = explainMove({
			fenBefore: fen,
			playedUci: 'h5d5',
			refutationPv: ['d8d5', 'd1d5', 'h8g8'],
			bestUci: 'd1d2',
			bestPv: ['d1d2'],
			playedMate: null,
			bestMate: null,
			isBest: false
		});
		expect(out.playedIssue).toContain('a point down');
		expect(out.playedIssue).not.toContain('pawn');
	});

	it('no "new queen" claim when the promoted piece dies later in the window', () => {
		// e8=Q Ka7 Qd8 Rxd8 — the queen moves away and is then captured; the
		// old tracker stopped following once it moved
		const fen = 'k1r5/4P3/8/8/8/8/8/6K1 w - - 0 1';
		expect(promotionPoint(fen, ['e7e8q', 'a8a7', 'e8d8', 'c8d8'])).toBeUndefined();
	});

	it('no pin claim when the only "defender" of the pinner is itself pinned', () => {
		// Rd3 blocks the queen check; Qxd3+ just wins the rook because Be2 is
		// absolutely pinned by Bh5 and cannot legally recapture
		const fen = '3k4/8/8/3q3b/8/7R/4B3/3K4 w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'h3d3')).toBeUndefined();
	});
});
