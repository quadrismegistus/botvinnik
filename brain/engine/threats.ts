import { Chess, type Color, type Square } from 'chess.js';
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

// ...unless the gain names no victim. The settled window ends on a quiet ply,
// but quiet is not settled: a gambit line is quiet and a pawn down ON PURPOSE,
// and a weak engine's horizon turns that into "threat: Nc6 costs 1.0" with no
// piece to point at. A victimless gain must be worth a real threat's while
// (promotion pushes clear this easily); small ones are choreography noise.
const VICTIMLESS_MIN_GAIN = 2;

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
		// the mated side is the side to move in the real position
		const king = kingSquare(fen, new Chess(fen).turn());
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
	// a threat must either name a victim or be worth ≥ VICTIMLESS_MIN_GAIN
	if (targets.length === 0 && net < VICTIMLESS_MIN_GAIN) return null;
	return { fen, uci: best.pv[0], san: getSan(nullFen, best.pv[0]) ?? best.pv[0], gain: net, targets };
}

function kingSquare(fen: string, color: Color): string | null {
	const c = new Chess(fen);
	for (const row of c.board()) {
		for (const cell of row) {
			if (cell && cell.type === 'k' && cell.color === color) return cell.square;
		}
	}
	return null;
}

/**
 * The same judgment run on the side to move's OWN top line — what does the
 * mover win by playing it? The green mirror of [judgeThreat]: same three
 * facts behind each target (attacked the instant the first move lands, falls
 * inside the settled window, not an even trade it initiated), same floors.
 * The pv is the position's live analysis line, so this costs no extra search.
 * Unlike the probe there is no turn flip and no in-check bail: an evasion
 * that wins the checking piece is a perfectly good tactical win.
 */
export function judgeTacticalWin(
	fen: string,
	best: { pv: string[]; mate: number | null } | null | undefined
): Threat | null {
	let base: Chess;
	try {
		base = new Chess(fen);
	} catch {
		return null;
	}
	if (base.isGameOver() || !best || best.pv.length === 0) return null;

	if (best.mate !== null) {
		if (best.mate <= 0) return null;
		const king = kingSquare(fen, base.turn() === 'w' ? 'b' : 'w'); // the OPPONENT king falls
		return {
			fen,
			uci: best.pv[0],
			san: getSan(fen, best.pv[0]) ?? best.pv[0],
			gain: Infinity,
			targets: king ? [king] : []
		};
	}

	const quiet = quietMaterialOverLine(fen, best.pv);
	const net = quiet.plies > 0 ? quiet.net : staticFirstCaptureGain(fen, best.pv[0]);
	if (net < MIN_GAIN) return null;
	const targets =
		quiet.plies > 0 ? victimSquares(fen, best.pv, quiet.plies) : [best.pv[0].slice(2, 4)];
	if (targets.length === 0 && net < VICTIMLESS_MIN_GAIN) return null;
	return { fen, uci: best.pv[0], san: getSan(fen, best.pv[0]) ?? best.pv[0], gain: net, targets };
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
	// the defender's immediately-preceding capture: {landing square, value taken}
	let defCapture: { sq: string; val: number } | null = null;
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
		// en passant: the pawn dies beside the landing square, not on it
		const capSq: string | null = m.captured
			? m.isEnPassant()
				? m.to[0] + m.from[1]
				: m.to
			: null;
		if (m.color === mover && capSq) {
			// captured ≠ lost: when this is the recapture of an exchange the
			// DEFENDER initiated last ply on this square, the piece traded
			// itself off — ring it only if it died for insufficient value
			// (a desperado grab by a trapped piece), never for a fair trade
			const fairTrade =
				defCapture !== null &&
				defCapture.sq === capSq &&
				defCapture.val >= PIECE_VAL[m.captured!];
			if (!fairTrade) {
				let sq = capSq;
				for (let j = defenderMoves.length - 1; j >= 0; j--) {
					if (defenderMoves[j].to === sq) sq = defenderMoves[j].from;
				}
				candidates.push({ sq, ply: i });
			}
		}
		if (m.color !== mover) {
			defenderMoves.push({ from: m.from, to: m.to });
			defCapture = capSq ? { sq: capSq, val: PIECE_VAL[m.captured!] } : null;
		}
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
