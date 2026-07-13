import { describe, expect, it } from 'vitest';
import {
	discoveredPoint,
	explainGoodMove,
	explainMove,
	materialOverLine,
	motifTags,
	pinOrSkewerPoint,
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
		// diagonal ray, so the pawn's push would genuinely expose the knight
		const fen = '7k/8/4n3/3p4/8/8/8/5B1K w - - 0 1';
		expect(pinOrSkewerPoint(fen, 'f1c4')).toBe(
			'Bc4 pins the pawn on d5 against the knight on e6.'
		);
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
});
