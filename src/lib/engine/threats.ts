import { Chess } from 'chess.js';
import { getSan } from './chess';
import { materialOverLine, quietMaterialOverLine } from './explain';
import type { EngineResult } from './stockfish';

// A "threat" is what the side NOT to move would do if handed a free move — the
// classic null-move probe. We flip the side to move, ask the engine for its
// best reply, and keep it only when that reply actually WINS material (or
// mates). Equal trades and sacrifices net zero-or-worse material and are
// dropped, matching "a threat is not an equal-material sacrifice". Uses the
// engine because neither chessground (a renderer) nor chess.js (legality +
// move generation, no search) can see tactics; the material filter reuses the
// same settled-exchange counting the move explanations use.

export interface Threat {
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

export async function findThreat(
	fen: string,
	analyze: Analyze,
	opts: { depth?: number; movetimeMs?: number } = {}
): Promise<Threat | null> {
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
	let flipped: Chess;
	try {
		flipped = new Chess(nullFen);
	} catch {
		return null; // chess.js rejects an illegal flip (shouldn't happen from a legal, check-free position)
	}
	if (flipped.inCheck()) return null;

	const res = await analyze(nullFen, opts.depth ?? 14, () => {}, opts.movetimeMs ?? 500);
	const best = res.moves[0];
	if (!best || best.pv.length === 0) return null;

	// mate for the threatening side (side to move in the flipped position)
	if (best.mate !== null && best.mate > 0) {
		return { uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: Infinity };
	}

	// settle the exchange over the engine's line; net is from the mover's
	// (the threatening side's) perspective, so a positive net means they win
	const quiet = quietMaterialOverLine(nullFen, best.pv);
	const net = quiet.plies > 0 ? quiet.net : materialOverLine(nullFen, best.pv);
	if (net < MIN_GAIN) return null;

	return { uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: net };
}
