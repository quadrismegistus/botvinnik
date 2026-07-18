// Square control, statically: a side "can use" a square if it has a legal
// move landing there whose exchange doesn't lose material — capture gains
// count, and the occupier may be recaptured, resolved by the classic swap
// algorithm over the post-move attacker lists (so vacated lines and the
// mover's own absence are accounted for; x-rays behind other pieces are not).
//
// An EMPTY square exactly one side can safely use is controlled by that side.
// An OCCUPIED square is tinted only when the opponent wins the exchange
// outright there (the piece is effectively lost) — tinting every held square
// would just repaint the whole board.
//
// Pure chess.js — no engine time. The opponent's moves come from the same
// null-move turn-flip the threat probe uses (ep voided). That flip can leave
// the other king attacked, so king captures are filtered out of move
// generation; with those gone the map is computed in check too, where the
// side to move is honestly limited to its evasion squares.

import { Chess, type Color, type Square } from 'chess.js';
import { PIECE_VAL } from './explain';

// kings sort after every real piece and may only capture undefended ones
const KING_V = 100;

function pieceVal(t: string): number {
	return t === 'k' ? KING_V : PIECE_VAL[t];
}

// The opponent's best gain from capturing a piece worth `target`, given their
// attacker values and the defender values (both ascending). Capturing is
// optional, so the result is never negative.
function see(target: number, atts: number[], defs: number[]): number {
	if (atts.length === 0) return 0;
	const [a, ...rest] = atts;
	if (a === KING_V && defs.length > 0) return 0; // a king can't take a defended piece
	return Math.max(0, target - see(a, defs, rest));
}

function attackerVals(c: Chess, sq: Square, by: Color): number[] {
	return c
		.attackers(sq, by)
		.map((s) => pieceVal(c.get(s)?.type ?? 'k'))
		.sort((x, y) => x - y);
}

// best achievable net for the side to move on `c`, per target square
function bestNets(c: Chess): Map<string, number> {
	const side = c.turn();
	const opp: Color = side === 'w' ? 'b' : 'w';
	const out = new Map<string, number>();
	for (const m of c.moves({ verbose: true })) {
		// The turn-flip can leave the OTHER king attacked, and chess.js will
		// then offer to capture it — a "gain" worth more than the board. Drop
		// those: they can never arise in the real position, where a king
		// capture is not a move anyone gets to make.
		if (m.captured === 'k') continue;
		const gain = m.captured ? PIECE_VAL[m.captured] : 0;
		try {
			c.move({ from: m.from, to: m.to, promotion: m.promotion });
		} catch {
			continue;
		}
		const occ = pieceVal(m.promotion ?? m.piece);
		// a legal king move never lands on an attacked square
		const net =
			occ === KING_V
				? gain
				: gain -
					see(occ, attackerVals(c, m.to as Square, opp), attackerVals(c, m.to as Square, side));
		c.undo();
		const prev = out.get(m.to);
		if (prev === undefined || net > prev) out.set(m.to, net);
	}
	return out;
}

export type ControlMap = Map<string, 'w' | 'b'>;

export function computeControl(fen: string): ControlMap {
	const map: ControlMap = new Map();
	let real: Chess;
	try {
		real = new Chess(fen);
	} catch {
		return map;
	}
	if (real.isGameOver()) return map;

	const parts = fen.split(' ');
	const flippedParts = [...parts];
	flippedParts[1] = parts[1] === 'w' ? 'b' : 'w';
	flippedParts[3] = '-';
	let flipped: Chess;
	try {
		flipped = new Chess(flippedParts.join(' '));
	} catch {
		return map;
	}

	const mover = real.turn();
	const nets: Record<Color, Map<string, number>> = {
		w: bestNets(mover === 'w' ? real : flipped),
		b: bestNets(mover === 'b' ? real : flipped)
	};

	const files = 'abcdefgh';
	for (let f = 0; f < 8; f++) {
		for (let r = 1; r <= 8; r++) {
			const sq = (files[f] + r) as Square;
			const piece = real.get(sq);
			if (piece) {
				const opp: Color = piece.color === 'w' ? 'b' : 'w';
				const oppNet = nets[opp].get(sq);
				if (oppNet !== undefined && oppNet > 0) map.set(sq, opp); // the piece is winnable
			} else {
				const w = nets.w.get(sq);
				const b = nets.b.get(sq);
				const wSafe = w !== undefined && w >= 0;
				const bSafe = b !== undefined && b >= 0;
				if (wSafe && !bSafe) map.set(sq, 'w');
				else if (bSafe && !wSafe) map.set(sq, 'b');
			}
		}
	}
	return map;
}
