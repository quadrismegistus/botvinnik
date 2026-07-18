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

	// mate for the threatening side (side to move in the flipped position)
	if (best.mate !== null && best.mate > 0) {
		return { fen, uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: Infinity };
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

	return { fen, uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: net };
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
