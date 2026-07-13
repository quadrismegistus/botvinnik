// Fact-based move explanations, cook.py-style: every claim is detected on an
// engine-validated line (the refutation PV or the best-move PV), never guessed,
// and templates only verbalize detected facts. See memory: move-explanation-research.

import { Chess, type Square, type Color } from 'chess.js';
import { getFenAfter, getNumberedSanLine, getSanLine } from './chess';

export interface Explanation {
	playedIssue?: string; // what's wrong with the played move
	bestPoint?: string; // what the best move achieves (may reveal it)
	playedPoint?: string; // what a GOOD played move achieves
	lineStory?: string; // material narrative of the line ahead (trades, captures)
	// the engine line backing playedIssue/lineStory (played move + refutation),
	// so renderers can make the claim hoverable/replayable
	evidence?: { fen: string; ucis: string[] };
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

// Narrate the material story of a line from the mover's perspective:
// "rooks are traded on d5, then your queen is taken (Qxd8)". Conservative by
// design — anything the line's horizon might cut through is dropped rather
// than narrated wrong. Returns a lowercase clause (no period) or undefined.
export function summarizeLine(fen: string, ucis: string[]): string | undefined {
	const c = new Chess(fen);
	const mover = c.turn();
	interface CapEvent {
		ply: number;
		square: string;
		victim: string;
		byMover: boolean;
		san: string;
	}
	const events: CapEvent[] = [];
	let ply = 0;
	let lastSan = '';
	for (const uci of ucis) {
		const m = apply(c, uci);
		if (!m) break;
		ply++;
		lastSan = m.san;
		if (m.captured) {
			events.push({ ply, square: m.to, victim: m.captured, byMover: m.color === mover, san: m.san });
		}
	}
	if (ply === 0) return undefined;
	const mate = lastSan.endsWith('#');
	const mateByMover = mate && ply % 2 === 1;

	// consecutive-ply captures on one square form an exchange
	let groups: CapEvent[][] = [];
	for (const e of events) {
		const g = groups[groups.length - 1];
		if (g && e.ply === g[g.length - 1].ply + 1 && e.square === g[g.length - 1].square) g.push(e);
		else groups.push([e]);
	}
	// an exchange still open when the line ends may continue past the horizon —
	// only a completed equal trade is safe to narrate there
	groups = groups.filter(
		(g) => g[g.length - 1].ply !== ply || (g.length === 2 && g[0].victim === g[1].victim)
	);

	const phrases: string[] = [];
	for (const g of groups) {
		if (g.length === 1) {
			const e = g[0];
			phrases.push(
				e.byMover
					? `you pick up a ${NAME[e.victim]} (${e.san})`
					: `your ${NAME[e.victim]} is taken (${e.san})`
			);
		} else if (g.length === 2 && g[0].victim === g[1].victim) {
			phrases.push(`${NAME[g[0].victim]}s are traded on ${g[0].square}`);
		} else if (g.length === 2) {
			const won = g[0].byMover ? g[0].victim : g[1].victim; // what the mover captured
			const lost = g[0].byMover ? g[1].victim : g[0].victim; // what the mover gave up
			if (VAL[won] > VAL[lost]) {
				phrases.push(`you win a ${NAME[won]} for a ${NAME[lost]} on ${g[0].square}`);
			} else if (VAL[won] < VAL[lost]) {
				phrases.push(`you give up a ${NAME[lost]} for a ${NAME[won]} on ${g[0].square}`);
			} else {
				phrases.push(`a ${NAME[won]} and a ${NAME[lost]} are traded on ${g[0].square}`);
			}
		} else {
			const net = g.reduce((a, e) => a + (e.byMover ? VAL[e.victim] : -VAL[e.victim]), 0);
			if (net > 0.5) phrases.push(`you come out ahead in the exchange on ${g[0].square}`);
			else if (net < -0.5) phrases.push(`you come out behind in the exchange on ${g[0].square}`);
			else phrases.push(`pieces are traded on ${g[0].square}`);
		}
	}

	if (phrases.length === 0 && !mate) return undefined;
	let story = phrases.slice(0, 3).join(', then ');
	if (mate) {
		const mateClause = mateByMover ? 'mate follows' : 'you get mated';
		story = story ? `${story}, and ${mateClause}` : mateClause;
	}
	return story;
}

// Like materialOverLine, but the count stops at the last quiet ply — a window
// ending mid-exchange would credit a capture the opponent recaptures next move.
// Returns the plies actually counted so callers can quote exactly that line.
export function quietMaterialOverLine(fen: string, ucis: string[]): { net: number; plies: number } {
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

// ---- ray machinery for the slider motifs (pin / skewer / discovered) ----

type Dir = [number, number];
const BISHOP_DIRS: Dir[] = [
	[1, 1],
	[1, -1],
	[-1, 1],
	[-1, -1]
];
const ROOK_DIRS: Dir[] = [
	[1, 0],
	[-1, 0],
	[0, 1],
	[0, -1]
];

function sliderDirs(type: string): Dir[] | null {
	if (type === 'b') return BISHOP_DIRS;
	if (type === 'r') return ROOK_DIRS;
	if (type === 'q') return [...BISHOP_DIRS, ...ROOK_DIRS];
	return null;
}

function toSquare(file: number, rank: number): Square | null {
	if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
	return (String.fromCharCode(97 + file) + (rank + 1)) as Square;
}

function* raySquares(from: Square, dir: Dir): Generator<Square> {
	let file = from.charCodeAt(0) - 97;
	let rank = Number(from[1]) - 1;
	for (;;) {
		file += dir[0];
		rank += dir[1];
		const s = toSquare(file, rank);
		if (!s) return;
		yield s;
	}
}

// After playing `uci` with a slider: does it pin or skewer along some ray?
// Pin: first enemy piece on the ray shields the king or a MORE valuable piece.
// Skewer: the king (or queen) is hit first and must expose the piece behind.
// Geometry only — both claims are verifiable facts about the position.
export function pinOrSkewerPoint(fenBefore: string, uci: string): string | undefined {
	const c = new Chess(fenBefore);
	const m = apply(c, uci);
	if (!m) return undefined;
	const dirs = sliderDirs(m.piece);
	if (!dirs) return undefined;

	for (const dir of dirs) {
		let first: { sq: Square; type: string } | null = null;
		for (const s of raySquares(m.to as Square, dir)) {
			const p = c.get(s);
			if (!p) continue;
			if (p.color === m.color) break; // own piece blocks the ray
			if (!first) {
				first = { sq: s, type: p.type };
				continue;
			}
			// second enemy piece on the same ray. Unless the king is behind
			// (an absolute pin always binds), the claim is only real if
			// capturing the piece behind would PAY once the front piece is out
			// of the way: a trade up, or an undefended target. A queen
			// "pinning" a pawn to a rook-defended knight restrains nothing —
			// taking the knight just loses the queen.
			const wins = VAL[p.type] > VAL[m.piece] || c.attackers(s, p.color).length === 0;
			if (first.type === 'k') {
				// check with a piece behind the king: a skewer
				if (VAL[p.type] >= 3 && wins) {
					return `${m.san} skewers the king on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
				}
			} else if (p.type === 'k') {
				return `${m.san} pins the ${NAME[first.type]} on ${first.sq} against the king.`;
			} else if (VAL[p.type] > VAL[first.type]) {
				if (wins) {
					return `${m.san} pins the ${NAME[first.type]} on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
				}
			} else if (first.type === 'q' && VAL[m.piece] < 9 && VAL[p.type] >= 3 && wins) {
				// a queen skewered by a CHEAPER slider must give up the piece behind
				return `${m.san} skewers the queen on ${first.sq} against the ${NAME[p.type]} on ${s}.`;
			}
			break; // ray resolved either way
		}
	}
	return undefined;
}

// Moving `uci` uncovers a friendly slider's attack through the vacated square —
// discovered check, or a discovered attack on a valuable piece.
export function discoveredPoint(fenBefore: string, uci: string): string | undefined {
	const c = new Chess(fenBefore);
	const m = apply(c, uci);
	if (!m || m.flags.includes('k') || m.flags.includes('q')) return undefined; // not for castling

	for (const row of c.board()) {
		for (const cell of row) {
			if (!cell || cell.color !== m.color || cell.square === m.to) continue;
			const dirs = sliderDirs(cell.type);
			if (!dirs) continue;
			for (const dir of dirs) {
				let passedFrom = false;
				for (const s of raySquares(cell.square as Square, dir)) {
					if (s === m.from) {
						passedFrom = true;
						continue; // vacated — the whole point
					}
					const p = c.get(s);
					if (!p) continue;
					if (!passedFrom) break; // blocked before the vacated square
					if (p.color !== m.color && p.type === 'k') {
						return `${m.san} discovers check from the ${NAME[cell.type]} on ${cell.square}.`;
					}
					if (p.color !== m.color && VAL[p.type] >= 3 && VAL[p.type] > VAL[cell.type]) {
						return `${m.san} uncovers the ${NAME[cell.type]} on ${cell.square}'s attack on the ${NAME[p.type]} on ${s}.`;
					}
					break;
				}
			}
		}
	}
	return undefined;
}

// After `uci`, an enemy piece is attacked by something cheaper and has no safe
// square: every escape is guarded (by a cheaper piece, or undefended into a
// capture), and no escape grabs equal-or-better material.
export function trappedPoint(fenBefore: string, uci: string): string | undefined {
	const c = new Chess(fenBefore);
	const m = apply(c, uci);
	if (!m) return undefined;
	const us = m.color;
	const minAttackerVal = (sq: Square, by: Color): number => {
		const vals = c.attackers(sq, by).map((a) => VAL[c.get(a)?.type ?? 'k']);
		return vals.length ? Math.min(...vals) : Infinity;
	};

	// most valuable first — "traps the queen" beats "traps the knight"
	const candidates: { sq: Square; type: string }[] = [];
	for (const row of c.board()) {
		for (const cell of row) {
			if (cell && cell.color !== us && VAL[cell.type] >= 3 && cell.type !== 'k') {
				candidates.push({ sq: cell.square as Square, type: cell.type });
			}
		}
	}
	candidates.sort((a, b) => VAL[b.type] - VAL[a.type]);

	for (const x of candidates) {
		if (minAttackerVal(x.sq, us) >= VAL[x.type]) continue; // no cheap attacker: not forced
		const escapes = c.moves({ square: x.sq, verbose: true });
		const allUnsafe = escapes.every((e) => {
			const grabbed = c.get(e.to as Square);
			if (grabbed && grabbed.color === us && VAL[grabbed.type] >= VAL[x.type]) {
				return false; // escapes with equal-or-better material — not trapped
			}
			const attackerVal = minAttackerVal(e.to as Square, us);
			if (attackerVal === Infinity) return false; // a genuinely safe square
			if (attackerVal < VAL[x.type]) return true; // guarded by something cheaper
			// guarded by equal/greater value: only unsafe if nothing recaptures
			const them: Color = us === 'w' ? 'b' : 'w';
			const defenders = c.attackers(e.to as Square, them).filter((d) => d !== x.sq);
			return defenders.length === 0;
		});
		if (allUnsafe) {
			return `${m.san} traps the ${NAME[x.type]} on ${x.sq} — it has no safe square.`;
		}
	}
	return undefined;
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
				const fenAfter = getFenAfter(fenBefore, playedUci);
				const continuation = fenAfter
					? getNumberedSanLine(fenAfter, playedLine.slice(1, plies))
					: '';
				if (continuation) {
					out.playedIssue = `This loses material — after ${continuation}, you're down ${-net} points.`;
				}
			}
		}
		// no named issue — narrate what the line does anyway (trades, captures)
		if (!out.playedIssue && refutationPv.length > 0) {
			const story = summarizeLine(fenBefore, playedLine.slice(0, 9));
			if (story) out.lineStory = `In this line, ${story}.`;
		}
	}
	// the line behind whatever claim (or fallback) the renderer shows
	if (refutationPv.length > 0) {
		out.evidence = { fen: fenBefore, ucis: playedLine.slice(0, 9) };
	}

	// --- what the best move achieves (priority: mate > fork > free capture > material) ---
	if (bestMate !== null && bestMate > 0 && !(playedMate !== null && playedMate > 0)) {
		const bestSan = getSanLine(fenBefore, [bestUci])[0]?.san ?? bestUci;
		out.bestPoint =
			bestMate === 1
				? `${bestSan} was immediate checkmate.`
				: `${bestSan} forces mate in ${bestMate}.`;
	} else {
		out.bestPoint = bestMovePoint(fenBefore, bestUci, bestPv);
	}

	return out;
}

// What the best move achieves, as a standalone sentence — the same detector
// chain explainMove uses, exported so importers can backfill explanations.
export function bestMovePoint(
	fenBefore: string,
	bestUci: string,
	bestPv: string[]
): string | undefined {
	const point =
		forkPoint(fenBefore, bestUci) ??
		freeCapturePoint(fenBefore, bestUci) ??
		pinOrSkewerPoint(fenBefore, bestUci) ??
		discoveredPoint(fenBefore, bestUci) ??
		trappedPoint(fenBefore, bestUci);
	if (point) return point;
	if (bestPv.length > 1) {
		const { net, plies } = quietMaterialOverLine(fenBefore, bestPv.slice(0, 9));
		if (net >= 2) {
			return `Instead, ${sanLine(fenBefore, bestPv, plies)} wins ${net} point${net === 1 ? '' : 's'} of material.`;
		}
	}
	return undefined;
}

// The motif vocabulary — which named facts a move exhibits. Used to tag
// practice items ("drill only pins") and to phrase tier-1 hints without
// giving the move away. Same never-wrong discipline: tags mirror exactly
// what the prose detectors would claim.
export type Motif =
	| 'mate'
	| 'fork'
	| 'free capture'
	| 'pin'
	| 'skewer'
	| 'discovered attack'
	| 'trapped piece'
	| 'material';

// Bump whenever a detector's semantics change so stored practice tags get
// recomputed on load. 2: pins/skewers require a profitable capture behind.
export const MOTIF_TAGS_VERSION = 2;

export function motifTags(
	fenBefore: string,
	uci: string,
	pv: string[],
	mate: number | null
): Motif[] {
	const tags: Motif[] = [];
	if (mate !== null && mate > 0) tags.push('mate');
	if (forkPoint(fenBefore, uci)) tags.push('fork');
	if (freeCapturePoint(fenBefore, uci)) tags.push('free capture');
	const ps = pinOrSkewerPoint(fenBefore, uci);
	if (ps) tags.push(ps.includes('skewers') ? 'skewer' : 'pin');
	if (discoveredPoint(fenBefore, uci)) tags.push('discovered attack');
	if (trappedPoint(fenBefore, uci)) tags.push('trapped piece');
	if (
		tags.length === 0 &&
		pv.length > 1 &&
		quietMaterialOverLine(fenBefore, pv.slice(0, 9)).net >= 2
	) {
		tags.push('material');
	}
	return tags;
}

// Why a GOOD move is good — same detectors, pointed at the played move itself.
// Returns the sentence plus the line that backs it, for hover replay.
export interface GoodMovePoint {
	text: string;
	evidence: { fen: string; ucis: string[] };
}

export function explainGoodMove(
	fenBefore: string,
	playedUci: string,
	playedPv: string[], // line starting with the played move
	playedMate: number | null
): GoodMovePoint | undefined {
	const evidence = (plies: number) => ({ fen: fenBefore, ucis: playedPv.slice(0, plies) });
	if (playedMate !== null && playedMate > 0) {
		const san = getSanLine(fenBefore, [playedUci])[0]?.san ?? playedUci;
		return {
			text: playedMate === 1 ? `${san} is checkmate.` : `${san} forces mate in ${playedMate}.`,
			evidence: evidence(12)
		};
	}
	const point =
		forkPoint(fenBefore, playedUci) ??
		freeCapturePoint(fenBefore, playedUci) ??
		pinOrSkewerPoint(fenBefore, playedUci) ??
		discoveredPoint(fenBefore, playedUci) ??
		trappedPoint(fenBefore, playedUci);
	if (point) return { text: point, evidence: evidence(1) };
	if (playedPv.length > 1) {
		const { net, plies } = quietMaterialOverLine(fenBefore, playedPv.slice(0, 9));
		if (net >= 2) {
			const fenAfter = getFenAfter(fenBefore, playedUci);
			const continuation = fenAfter ? getNumberedSanLine(fenAfter, playedPv.slice(1, plies)) : '';
			if (continuation) {
				return { text: `It wins ${net} points of material (${continuation}).`, evidence: evidence(plies) };
			}
		}
		const story = summarizeLine(fenBefore, playedPv.slice(0, 9));
		if (story) return { text: `In this line, ${story}.`, evidence: evidence(9) };
	}
	return undefined;
}
