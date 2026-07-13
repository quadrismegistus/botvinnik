import { describe, expect, it } from 'vitest';
import { computeControl } from './control';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

describe('computeControl', () => {
	it('gives each side its own half of the opening board', () => {
		const map = computeControl(START);
		// squares only one side can safely move to
		expect(map.get('e4')).toBe('w');
		expect(map.get('a3')).toBe('w');
		expect(map.get('e5')).toBe('b');
		expect(map.get('h6')).toBe('b');
		// nobody can reach the other camp on move one
		expect(map.get('e2')).toBeUndefined(); // occupied and not winnable
		expect(map.get('e7')).toBeUndefined();
	});

	it('a defended landing square still counts when the recapture settles even', () => {
		// after 1.e4: Black may play d5 — exd5 Qxd5 is an even trade, so d5 is
		// usable by Black and unreachable for White
		const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
		expect(computeControl(fen).get('d5')).toBe('b');
	});

	it('tints an occupied square only when the piece there is winnable', () => {
		// undefended white bishop on f4, black knight can just take it
		const hanging = '4k3/8/8/7n/5B2/8/8/4K3 w - - 0 1';
		expect(computeControl(hanging).get('f4')).toBe('b');
		// queen-defended: Nxf4 Qxf4 is an even trade — no owner
		const defended = '4k3/8/8/7n/3Q1B2/8/8/4K3 w - - 0 1';
		expect(computeControl(defended).get('f4')).toBeUndefined();
	});

	it('computes nothing while in check or after the game ends', () => {
		const inCheck = '4k3/8/8/8/7b/8/8/4K3 w - - 0 1'; // Bh4+ checks e1
		expect(computeControl(inCheck).size).toBe(0);
		const over = '4k3/8/8/8/8/8/8/4K3 w - - 0 1'; // insufficient material
		expect(computeControl(over).size).toBe(0);
	});

	it('a king can hold a square no other piece defends', () => {
		// black rook eyes d2; the white king on e1 defends it, so Rd2 would just
		// be taken for free — d2 is not black's square
		const fen = '3rk3/8/8/8/8/8/8/4K3 w - - 0 1';
		const map = computeControl(fen);
		expect(map.get('d2')).not.toBe('b');
	});
});
