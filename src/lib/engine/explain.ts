// Fact-based move explanations, cook.py-style: every claim is detected on an
// engine-validated line (the refutation PV or the best-move PV), never guessed,
// and templates only verbalize detected facts. See memory: move-explanation-research.

import { Chess, type Square, type Color } from 'chess.js';
import { getSanLine } from './chess';

export interface Explanation {
	playedIssue?: string; // what's wrong with the played move
	bestPoint?: string; // what the best move achieves (may reveal it)
	playedPoint?: string; // what a GOOD played move achieves
}

const VAL: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
const NAME: Record<string, string> = {
	p: 'pawn',
	n: 'knight',
	b: 'bishop',
	r: 'rook',
	q: 'queen',
	k: 'king'
};

function apply(chess: Chess, uci: string) {
	try {
		return chess.move({
			from: uci.slice(0, 2) as Square,
			to: uci.slice(2, 4) as Square,
			promotion: uci.length > 4 ? uci[4] : undefined
		});
	} catch {
		return null;
	}
}

function sanLine(fen: string, ucis: string[], max = 6): string {
	return getSanLine(fen, ucis.slice(0, max))
		.map((s) => s.san)
		.join(' ');
}

// net material change over a line for the side to move in `fen`, in points
export function materialOverLine(fen: string, ucis: string[]): number {
	const c = new Chess(fen);
	const mover = c.turn();
	let net = 0;
	for (const uci of ucis) {
		const m = apply(c, uci);
		if (!m) break;
		if (m.captured) net += (m.color === mover ? 1 : -1) * VAL[m.captured];
		if (m.promotion) net += (m.color === mover ? 1 : -1) * (VAL[m.promotion] - 1);
	}
	return net;
}

// Like materialOverLine, but the count stops at the last quiet ply — a window
// ending mid-exchange would credit a capture the opponent recaptures next move.
// Returns the plies actually counted so callers can quote exactly that line.
function quietMaterialOverLine(fen: string, ucis: string[]): { net: number; plies: number } {
	const c = new Chess(fen);
	const mover = c.turn();
	let net = 0;
	let plies = 0;
	let quiet = { net: 0, plies: 0 };
	for (const uci of ucis) {
		const m = apply(c, uci);
		if (!m) break;
		plies++;
		if (m.captured) net += (m.color === mover ? 1 : -1) * VAL[m.captured];
		if (m.promotion) net += (m.color === mover ? 1 : -1) * (VAL[m.promotion] - 1);
		if (!m.captured && !m.promotion) quiet = { net, plies };
	}
	return quiet;
}

// The refutation's first move captures a piece nobody defends -> the cleanest,
// most common amateur blunder. Only fires in the airtight case (zero defenders).
function hangingIssue(fenBefore: string, playedUci: string, refutationUci: string | undefined) {
	if (!refutationUci) return undefined;
	const c = new Chess(fenBefore);
	const played = apply(c, playedUci);
	if (!played) return undefined;
	const target = refutationUci.slice(2, 4) as Square;
	const victim = c.get(target);
	if (!victim || victim.color !== played.color || victim.type === 'p' || victim.type === 'k')
		return undefined;
	const defenders = c.attackers(target, played.color).length;
	if (defenders > 0) return undefined; // not airtight — let material accounting speak
	const ref = apply(c, refutationUci);
	if (!ref || !ref.captured) return undefined;
	return `This leaves the ${NAME[victim.type]} on ${target} undefended — ${ref.san} just takes it.`;
}

// Does `uci` fork? (cook.py rule: the moved piece attacks ≥2 enemy pieces that
// are each the king, higher-valued than the forker, or undefended.)
function forkPoint(fenBefore: string, uci: string) {
	const c = new Chess(fenBefore);
	const m = apply(c, uci);
	if (!m || m.piece === 'k') return undefined;
	const to = m.to as Square;
	const targets: string[] = [];
	for (const row of c.board()) {
		for (const cell of row) {
			if (!cell || cell.color === m.color || cell.type === 'p') continue;
			if (!c.attackers(cell.square as Square, m.color).includes(to)) continue;
			const undefended = c.attackers(cell.square as Square, cell.color).length === 0;
			if (cell.type === 'k' || VAL[cell.type] > VAL[m.piece] || undefended) {
				targets.push(`${NAME[cell.type]} on ${cell.square}`);
			}
		}
	}
	if (targets.length < 2) return undefined;
	return `${m.san} forks the ${targets.join(' and the ')}.`;
}

// Best move simply captures an undefended piece
function freeCapturePoint(fenBefore: string, uci: string) {
	const c = new Chess(fenBefore);
	const mover = c.turn();
	const target = uci.slice(2, 4) as Square;
	const victim = c.get(target);
	if (!victim || victim.type === 'p') return undefined;
	if (c.attackers(target, victim.color).length > 0) return undefined;
	const m = apply(c, uci);
	if (!m || !m.captured) return undefined;
	void mover;
	return `${m.san} simply wins the ${NAME[victim.type]} — it's undefended.`;
}

export function explainMove(input: {
	fenBefore: string;
	playedUci: string;
	refutationPv: string[]; // opponent's continuation after the played move
	bestUci: string;
	bestPv: string[]; // engine line starting with the best move
	playedMate: number | null; // mover's perspective after the played move
	bestMate: number | null;
	isBest: boolean;
}): Explanation {
	const { fenBefore, playedUci, refutationPv, bestUci, bestPv, playedMate, bestMate, isBest } =
		input;
	if (isBest) return {};

	const out: Explanation = {};
	const playedLine = [playedUci, ...refutationPv];

	// --- what's wrong with the played move (priority: mate > hang > material) ---
	if (playedMate !== null && playedMate < 0) {
		const n = Math.abs(playedMate);
		const refSans = getSanLine(fenBefore, playedLine.slice(0, 2)).map((s) => s.san);
		out.playedIssue =
			n === 1 && refSans[1]
				? `This allows immediate mate — ${refSans[1]}.`
				: `This allows a forced mate in ${n}${refSans[1] ? `, starting with ${refSans[1]}` : ''}.`;
	} else {
		out.playedIssue = hangingIssue(fenBefore, playedUci, refutationPv[0]);
		if (!out.playedIssue && refutationPv.length > 0) {
			const { net, plies } = quietMaterialOverLine(fenBefore, playedLine.slice(0, 9));
			if (net <= -2) {
				// quote only the continuation — the played move itself is already named
				const continuation = getSanLine(fenBefore, playedLine.slice(0, plies))
					.slice(1)
					.map((s) => s.san)
					.join(' ');
				if (continuation) {
					out.playedIssue = `This loses material — after ${continuation}, you're down ${-net} points.`;
				}
			}
		}
	}

	// --- what the best move achieves (priority: mate > fork > free capture > material) ---
	if (bestMate !== null && bestMate > 0 && !(playedMate !== null && playedMate > 0)) {
		const bestSan = getSanLine(fenBefore, [bestUci])[0]?.san ?? bestUci;
		out.bestPoint =
			bestMate === 1
				? `${bestSan} was immediate checkmate.`
				: `${bestSan} forces mate in ${bestMate}.`;
	} else {
		out.bestPoint = forkPoint(fenBefore, bestUci) ?? freeCapturePoint(fenBefore, bestUci);
		if (!out.bestPoint && bestPv.length > 1) {
			const { net, plies } = quietMaterialOverLine(fenBefore, bestPv.slice(0, 9));
			if (net >= 2) {
				out.bestPoint = `Instead, ${sanLine(fenBefore, bestPv, plies)} wins ${net} point${net === 1 ? '' : 's'} of material.`;
			}
		}
	}

	return out;
}

// Why a GOOD move is good — same detectors, pointed at the played move itself.
export function explainGoodMove(
	fenBefore: string,
	playedUci: string,
	playedPv: string[], // line starting with the played move
	playedMate: number | null
): string | undefined {
	if (playedMate !== null && playedMate > 0) {
		const san = getSanLine(fenBefore, [playedUci])[0]?.san ?? playedUci;
		return playedMate === 1 ? `${san} is checkmate.` : `${san} forces mate in ${playedMate}.`;
	}
	const point = forkPoint(fenBefore, playedUci) ?? freeCapturePoint(fenBefore, playedUci);
	if (point) return point;
	if (playedPv.length > 1) {
		const { net, plies } = quietMaterialOverLine(fenBefore, playedPv.slice(0, 9));
		if (net >= 2) {
			const continuation = getSanLine(fenBefore, playedPv.slice(0, plies))
				.slice(1)
				.map((s) => s.san)
				.join(' ');
			if (continuation) return `It wins ${net} points of material (${continuation}).`;
		}
	}
	return undefined;
}
