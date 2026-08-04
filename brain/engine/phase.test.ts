import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { endgameStartPly, isEndgamePosition } from './phase';

describe('isEndgamePosition (lila divider rule: majors+minors ≤ 6, both sides)', () => {
	it('the start position is not an endgame', () => {
		expect(
			isEndgamePosition('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')
		).toBe(false);
	});

	it('seven majors-and-minors is a middlegame; six is an endgame', () => {
		// white Q R R B N (5) + black q r (2) = 7 → not yet
		expect(isEndgamePosition('qr5k/8/8/8/8/8/8/QRRBN2K w - - 0 1')).toBe(false);
		// one black rook off: 6 → endgame, pawns not counted
		expect(isEndgamePosition('q6k/pppppppp/8/8/8/8/PPPPPPPP/QRRBN2K w - - 0 1')).toBe(true);
	});

	it('a queen endgame is an endgame — the rule counts pieces, not force', () => {
		expect(isEndgamePosition('q6k/8/8/8/8/8/8/Q6K w - - 0 1')).toBe(true);
	});
});

describe('endgameStartPly', () => {
	it('returns the first ply PLAYED in an endgame position', () => {
		// 7 majors+minors; Rxb8+ takes the black rook → 6 → the NEXT move is
		// the first played in an endgame. Assert the fixture, not its
		// description.
		const fen = 'qr5k/8/8/8/8/8/8/QRRBN1K1 w - - 0 1';
		const board = new Chess(fen);
		expect(board.move('Rxb8').san).toBe('Rxb8+');
		expect(isEndgamePosition(board.fen())).toBe(true);

		expect(endgameStartPly(['Rxb8+', 'Qxb8', 'Nf3'], fen)).toBe(2);
	});

	it('a game that never reaches the endgame is null', () => {
		expect(endgameStartPly(['e4', 'e5', 'Nf3', 'Nc6'])).toBeNull();
	});

	it('a position already in the endgame starts at ply 1', () => {
		expect(endgameStartPly(['Qb2', 'Qg7'], 'q6k/8/8/8/8/8/8/Q6K w - - 0 1')).toBe(1);
	});

	it('unparseable movetext claims nothing rather than guessing', () => {
		expect(endgameStartPly(['e4', 'Zz9'], undefined)).toBeNull();
	});
});
