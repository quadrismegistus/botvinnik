import { Chess, type Square } from 'chess.js';
import { getSan } from './chess';
import { PIECE_VAL, quietMaterialOverLine } from './explain';
import type { EngineResult } from './types';

// A "threat" is what the side NOT to move would do if handed a free move — the
// classic null-move probe. We flip the side to move, ask the engine for its
// best reply, and keep it only when that reply actually WINS material (or
// mates). Equal trades and sacrifices net zero-or-worse material and are
// dropped, matching "a threat is not an equal-material sacrifice". Uses the
// engine because neither chessground (a renderer) nor chess.js (legality +
// move generation, no search) can see tactics; the material filter reuses the
// same settled-exchange counting the move explanations use.

export interface Threat {
	fen: string; // the position the threat belongs to — display must check it still matches
	uci: string;
	san: string;
	gain: number; // material the threatening side nets, in pawns (Infinity = mate)
	// current squares of the pieces the line wins (the mated king for a mate).
	// A pv is a fiction as a script but a proof as a bound: the defender's
	// moves are best resistance, so it guarantees the VALUE, never the
	// choreography. A piece is listed only on the two facts that survive that:
	// the threat move attacks it THIS INSTANT (a static board fact), and best
	// defense still loses it somewhere in the settled line. A piece that dies
	// unattacked (it walked into a trade the engine chose for other reasons)
	// is script, not threat; a forked queen that escapes is attacked, not lost.
	targets: string[];
}

// pass the side to move: flip the active-colour field, void en passant.
function nullMoveFen(fen: string): string | null {
	const parts = fen.split(' ');
	if (parts.length < 4) return null;
	parts[1] = parts[1] === 'w' ? 'b' : 'w';
	parts[3] = '-'; // an ep square only makes sense for the original mover
	if (parts[4] !== undefined) parts[4] = '0'; // halfmove clock, irrelevant
	return parts.join(' ');
}

// win at least a pawn to count — enough to exclude equal trades, small enough
// to catch a clean pawn grab
const MIN_GAIN = 1;

type Analyze = (
	fen: string,
	depth: number,
	onUpdate: (moves: unknown) => void,
	movetimeMs?: number
) => Promise<EngineResult>;

/**
 * Where to point the null-move probe for [fen] — or null when the position
 * can't carry a threat (game over, in check, illegal flip). Split out so a
 * caller that owns its own engine (the Flutter app, over the JS bridge) can
 * run the search itself and hand the top line to [judgeThreat].
 */
export function threatProbeFen(fen: string): string | null {
	let base: Chess;
	try {
		base = new Chess(fen);
	} catch {
		return null;
	}
	// you can't be "threatened" by a free move when you must answer a check,
	// and a finished game has no threats
	if (base.isGameOver() || base.inCheck()) return null;

	const nullFen = nullMoveFen(fen);
	if (!nullFen) return null;
	try {
		if (new Chess(nullFen).inCheck()) return null;
	} catch {
		return null; // chess.js rejects an illegal flip (shouldn't happen from a legal, check-free position)
	}
	return nullFen;
}

/**
 * The material judgment on a null-move probe's top line: a real threat only
 * when the free move mates or wins at least a pawn once the exchange
 * settles. Pure — callable across the JS bridge.
 */
export function judgeThreat(
	fen: string,
	best: { pv: string[]; mate: number | null } | null | undefined
): Threat | null {
	const nullFen = threatProbeFen(fen);
	if (!nullFen || !best || best.pv.length === 0) return null;

	if (best.mate !== null) {
		// mate for the threatening side (side to move in the flipped position);
		// a NEGATIVE mate means even the free move loses to forced mate — their
		// pv is best resistance, and any material it grabs along the way is a
		// delaying tactic, not a threat
		if (best.mate <= 0) return null;
		const king = kingSquare(fen); // the mated side is the side to move in the real position
		return {
			fen,
			uci: best.pv[0],
			san: getSan(nullFen, best.pv[0]) ?? best.pv[0],
			gain: Infinity,
			targets: king ? [king] : []
		};
	}

	// settle the exchange over the engine's line; net is from the mover's
	// (the threatening side's) perspective, so a positive net means they win.
	// A pv with NO quiet ply ends mid-exchange, and a raw material count over
	// it credits captures the opponent recaptures just past the horizon (a
	// 1-ply pv made "Nxf4" a threat against a queen-defended bishop) — fall
	// back to a static guess on the first capture instead: profitable only if
	// the victim is undefended or outvalues the capturer.
	const quiet = quietMaterialOverLine(nullFen, best.pv);
	const net = quiet.plies > 0 ? quiet.net : staticFirstCaptureGain(nullFen, best.pv[0]);
	if (net < MIN_GAIN) return null;

	const targets =
		quiet.plies > 0
			? victimSquares(nullFen, best.pv, quiet.plies)
			: [best.pv[0].slice(2, 4)]; // the fallback only fires on a bare first capture
	return { fen, uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: net, targets };
}

// the side to move's king square — the king that falls when the probe mates
function kingSquare(fen: string): string | null {
	const c = new Chess(fen);
	for (const row of c.board()) {
		for (const cell of row) {
			if (cell && cell.type === 'k' && cell.color === c.turn()) return cell.square;
		}
	}
	return null;
}

// Where, on the CURRENT board, do the pieces the line wins stand? Each capture
// by the threatening side inside the settled window names a candidate — the
// capture may land plies deep, after the victim has run (or a blocker stepped
// in), so walk the defender's earlier moves backwards to the square the piece
// stands on right now. Then the filter that keeps the claim honest: a victim
// counts only if the threat move already attacks that square (checked in the
// position after ply 1), or IS ply 1's own capture. A piece the line trades
// off three plies deep without ever being attacked by the threat move died of
// the engine's choreography, not of the threat.
function victimSquares(nullFen: string, ucis: string[], plies: number): string[] {
	const c = new Chess(nullFen);
	const mover = c.turn();
	const defenderMoves: { from: string; to: string }[] = [];
	const candidates: { sq: string; ply: number }[] = [];
	for (let i = 0; i < plies; i++) {
		let m;
		try {
			m = c.move({
				from: ucis[i].slice(0, 2) as Square,
				to: ucis[i].slice(2, 4) as Square,
				promotion: ucis[i].length > 4 ? ucis[i][4] : undefined
			});
		} catch {
			break;
		}
		if (m.color === mover && m.captured) {
			// en passant: the pawn dies beside the landing square, not on it
			let sq: string = m.isEnPassant() ? m.to[0] + m.from[1] : m.to;
			for (let j = defenderMoves.length - 1; j >= 0; j--) {
				if (defenderMoves[j].to === sq) sq = defenderMoves[j].from;
			}
			candidates.push({ sq, ply: i });
		}
		if (m.color !== mover) defenderMoves.push({ from: m.from, to: m.to });
	}
	if (candidates.length === 0) return [];

	// the board as it stands the instant the threat move lands
	const afterThreat = new Chess(nullFen);
	try {
		afterThreat.move({
			from: ucis[0].slice(0, 2) as Square,
			to: ucis[0].slice(2, 4) as Square,
			promotion: ucis[0].length > 4 ? ucis[0][4] : undefined
		});
	} catch {
		return [];
	}
	const out: string[] = [];
	for (const { sq, ply } of candidates) {
		if (ply === 0 || afterThreat.attackers(sq as Square, mover).length > 0) {
			if (!out.includes(sq)) out.push(sq);
		}
	}
	return out;
}

export async function findThreat(
	fen: string,
	analyze: Analyze,
	opts: { depth?: number; movetimeMs?: number } = {}
): Promise<Threat | null> {
	const nullFen = threatProbeFen(fen);
	if (!nullFen) return null;
	const res = await analyze(nullFen, opts.depth ?? 14, () => {}, opts.movetimeMs ?? 500);
	return judgeThreat(fen, res.moves[0]);
}

// what a lone capture nets when the line ends before the exchange settles:
// the full victim if nobody defends it, else victim minus capturer (assume
// the cheapest possible outcome — a recapture)
function staticFirstCaptureGain(fen: string, uci: string): number {
	const c = new Chess(fen);
	const victimSq = uci.slice(2, 4) as Square;
	const victim = c.get(victimSq);
	const capturer = c.get(uci.slice(0, 2) as Square);
	if (!victim || !capturer || victim.color === capturer.color) return 0;
	if (c.attackers(victimSq, victim.color).length === 0) return PIECE_VAL[victim.type];
	return PIECE_VAL[victim.type] - PIECE_VAL[capturer.type];
}
