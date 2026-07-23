import { describe, expect, it } from 'vitest';
import { computeControl } from './control';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

// the side owning a square, ignoring margin/held — most tests only care who
const side = (map: ReturnType<typeof computeControl>, sq: string) => map.get(sq)?.side;

describe('computeControl', () => {
	it('gives each side its own half of the opening board', () => {
		const map = computeControl(START);
		// squares only one side can safely move to
		expect(side(map, 'e4')).toBe('w');
		expect(side(map, 'a3')).toBe('w');
		expect(side(map, 'e5')).toBe('b');
		expect(side(map, 'h6')).toBe('b');
		// nobody can reach the other camp on move one
		expect(map.get('e2')).toBeUndefined(); // occupied and not winnable
		expect(map.get('e7')).toBeUndefined();
	});

	it('a defended landing square still counts when the recapture settles even', () => {
		// after 1.e4: Black may play d5 — exd5 Qxd5 is an even trade, so d5 is
		// usable by Black and unreachable for White
		const fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
		expect(side(computeControl(fen), 'd5')).toBe('b');
	});

	it('tints an occupied square only when the piece there is winnable', () => {
		// undefended white bishop on f4, black knight can just take it
		const hanging = '4k3/8/8/7n/5B2/8/8/4K3 w - - 0 1';
		expect(side(computeControl(hanging), 'f4')).toBe('b');
		// queen-defended: Nxf4 Qxf4 is an even trade — no owner
		const defended = '4k3/8/8/7n/3Q1B2/8/8/4K3 w - - 0 1';
		expect(computeControl(defended).get('f4')).toBeUndefined();
	});

	it('computes nothing while in check or after the game ends', () => {
		// material deliberately present: an earlier version of this test used a
		// position with nothing to control, so it passed either way and missed
		// a change that DID start mapping in check
		const inCheck = '4k3/8/8/8/7b/8/4R3/4K3 w - - 0 1'; // Bh4+ checks e1
		expect(computeControl('4k3/8/8/8/8/8/4R3/4K3 w - - 0 1').size)
			.toBeGreaterThan(0); // the same material, unchecked, does map
		expect(computeControl(inCheck).size).toBe(0);
		const over = '4k3/8/8/8/8/8/8/4K3 w - - 0 1'; // insufficient material
		expect(computeControl(over).size).toBe(0);
	});

	it('a king can hold a square no other piece defends', () => {
		// black rook eyes d2; the white king on e1 defends it, so Rd2 would just
		// be taken for free — d2 is not black's square
		const fen = '3rk3/8/8/8/8/8/8/4K3 w - - 0 1';
		expect(side(computeControl(fen), 'd2')).not.toBe('b');
	});

	// ---- intensity gradation (margin) ----

	it('grades a winnable piece by the material the exchange wins', () => {
		// undefended white queen on d4, black knight on e6 can take it (Nxd4)
		const queen = computeControl('4k3/8/4n3/8/3Q4/8/8/4K3 w - - 0 1').get('d4');
		expect(queen).toEqual({ side: 'b', margin: 9, held: false });
		// undefended white pawn on d4 instead — same attacker, far smaller stake
		const pawn = computeControl('4k3/8/4n3/8/3P4/8/8/4K3 w - - 0 1').get('d4');
		expect(pawn).toEqual({ side: 'b', margin: 1, held: false });
	});

	it('an uncontested territory square carries margin 0', () => {
		// a1 corner in the opening: white owns it, black cannot contest it at all
		const map = computeControl(START);
		expect(map.get('a3')).toEqual({ side: 'w', margin: 0, held: false });
	});

	it('a square the opponent forfeits material to contest carries that margin', () => {
		// White knight f3 can hold e5 (pawn d4 backs it up, so Qxe5 dxe5 loses the
		// queen). Black's only way onto e5 is the queen, and dxe5 answers — so
		// Black forfeits a whole queen (9) to contest a square that is White's.
		const map = computeControl('4q2k/8/8/8/3P4/5N2/8/5K2 w - - 0 1');
		expect(map.get('e5')).toEqual({ side: 'w', margin: 9, held: false });
	});

	// ---- held occupied squares (opt-in) ----

	it('does not mark held pieces unless asked', () => {
		// black knight on h5 attacks white bishop f4, which the white queen d4
		// defends — an even, held standoff. Off by default: no tint on f4.
		const fen = '4k3/8/8/7n/3Q1B2/8/8/4K3 w - - 0 1';
		expect(computeControl(fen).get('f4')).toBeUndefined();
	});

	it('marks a contested-but-held piece for its own side when asked', () => {
		// same standoff: with { held } f4 becomes white's, flagged held, margin 0
		const fen = '4k3/8/8/7n/3Q1B2/8/8/4K3 w - - 0 1';
		expect(computeControl(fen, { held: true }).get('f4')).toEqual({
			side: 'w',
			margin: 0,
			held: true
		});
	});

	it('held never overrides a genuinely losable piece', () => {
		// hanging bishop stays the OPPONENT's winnable square even with held on
		const hanging = '4k3/8/8/7n/5B2/8/8/4K3 w - - 0 1';
		expect(computeControl(hanging, { held: true }).get('f4')).toEqual({
			side: 'b',
			margin: 3,
			held: false
		});
	});

	it('held leaves unattacked pieces alone (does not repaint the board)', () => {
		// the white king on e1 is attacked by nothing; held must not tint it
		const fen = '3rk3/8/8/8/8/8/8/4K3 w - - 0 1';
		expect(computeControl(fen, { held: true }).get('e1')).toBeUndefined();
	});
});
