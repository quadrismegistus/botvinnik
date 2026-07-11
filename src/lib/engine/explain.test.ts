import { describe, expect, it } from 'vitest';
import { explainGoodMove, explainMove, materialOverLine } from './explain';

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

	it('credits a genuinely free capture', () => {
		// lone rook takes an undefended queen
		const fen = 'k7/3q4/8/8/8/8/3R4/K7 w - - 0 1';
		expect(explainGoodMove(fen, 'd2d7', ['d2d7', 'a8b8'], null)).toBe(
			"Rxd7 simply wins the queen — it's undefended."
		);
	});

	it('describes a forced mate', () => {
		// back-rank: 1.f3 e5 2.g4 and black to play Qh4#
		const fen = 'rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2';
		expect(explainGoodMove(fen, 'd8h4', ['d8h4'], 1)).toBe('Qh4# is checkmate.');
	});
});
