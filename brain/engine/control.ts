// Square control, statically: a side "can use" a square if it has a legal
// move landing there whose exchange doesn't lose material — capture gains
// count, and the occupier may be recaptured, resolved by the classic swap
// algorithm over the post-move attacker lists (so vacated lines and the
// mover's own absence are accounted for; x-rays behind other pieces are not).
//
// An EMPTY square exactly one side can safely use is controlled by that side.
// An OCCUPIED square is tinted when the opponent wins the exchange outright
// there (the piece is effectively lost). With the opt-in `held` option it is
// also tinted for its OWN side when the opponent attacks it but cannot win the
// exchange — a contested-but-safe piece. Held is off by default because
// tinting every safe piece would just repaint the whole board; the option
// restricts it to pieces actually under fire, which is the readable subset.
//
// Each tinted square carries a `margin`: the material (in pawns) the exchange
// there decides, so the consumer can grade intensity instead of painting a
// flat yes/no. A hanging queen reads hotter than a hanging pawn; calm
// territory the opponent cannot even contest reads margin 0.
//
// Pure chess.js — no engine time. The opponent's moves come from the same
// null-move turn-flip the threat probe uses (ep voided).
//
// NOT computed in check, deliberately. The two halves would stop being
// comparable: the side to move would get only its real legal moves — in check
// just the evasions — while the opponent kept full free-move mobility. Across
// 800 check positions that skews to ~3 squares against ~17, so a checked side
// reads as crushed even when it is winning (in 4k3/8/8/8/7q/8/8/4K2R w K - 0 1
// White plays Rxh4 and is a queen up, but would tint 5 against 16). Blank says
// "no fair comparison here", which is the truth. Making it symmetric needs
// pseudo-legal move generation, which chess.js does not expose. (Tried once in
// 40ed32d, reverted with that data in be3cc0c — do not re-attempt without a
// plan for the asymmetry.)

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

// A square one side owns, with the exchange margin that decides it (pawns) and
// whether it is an occupied piece its own side merely HOLDS (as opposed to an
// empty square owned, or an enemy piece falling where it stands).
export interface ControlCell {
	side: 'w' | 'b';
	margin: number;
	held: boolean;
}

export type ControlMap = Map<string, ControlCell>;

export interface ControlOpts {
	// mark occupied squares the owner holds under fire (default off — see header)
	held?: boolean;
}

export function computeControl(fen: string, opts: ControlOpts = {}): ControlMap {
	const map: ControlMap = new Map();
	let real: Chess;
	try {
		real = new Chess(fen);
	} catch {
		return map;
	}
	if (real.isGameOver() || real.inCheck()) return map;

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
				const owner: Color = piece.color;
				const opp: Color = owner === 'w' ? 'b' : 'w';
				const oppNet = nets[opp].get(sq);
				if (oppNet === undefined) continue; // opponent can't reach it — nothing to say
				if (oppNet > 0) {
					// the piece is winnable: the opponent wins `oppNet` pawns outright
					map.set(sq, { side: opp, margin: oppNet, held: false });
				} else if (opts.held) {
					// under fire but the exchange doesn't win for the opponent — the
					// owner holds it; margin is the deterrent depth (0 = even standoff)
					map.set(sq, { side: owner, margin: oppNet === 0 ? 0 : -oppNet, held: true });
				}
			} else {
				const w = nets.w.get(sq);
				const b = nets.b.get(sq);
				const wSafe = w !== undefined && w >= 0;
				const bSafe = b !== undefined && b >= 0;
				// margin = how much the losing side forfeits by contesting the square
				// (it can only reach it at a loss, or not at all → 0, calm territory)
				if (wSafe && !bSafe) {
					map.set(sq, { side: 'w', margin: b === undefined ? 0 : -b, held: false });
				} else if (bSafe && !wSafe) {
					map.set(sq, { side: 'b', margin: w === undefined ? 0 : -w, held: false });
				}
			}
		}
	}
	return map;
}
