// The opening book — BAKED, not fetched. Lichess put its explorer API
// behind auth in 2026; instead of asking every user for a token, the book
// ships as static assets built from the public CC0 database dumps:
//   static/book.json      scripts/build-book-from-dump.mts (move stats,
//                         1200-2200 blitz/rapid/classical pool)
//   static/openings.json  scripts/build-openings.mts (ECO/name table)
// Same files the Flutter app bundles. Masters stats are gone (master games
// aren't in the public dumps) — the unified table simply has no masters
// column until we bake one from an OTB collection.
import { getSan } from './engine/chess';
import type { EngineMove } from './engine/stockfish';

export interface ExplorerPosition {
	total: number; // games reaching this position
	moves: { uci: string; san: string; white: number; draws: number; black: number }[];
	opening: { eco: string; name: string } | null;
}

export interface BookStats {
	games: number;
	pct: number; // share of games at this position, 0–100
	white: number; // W/D/L shares of this move's games, 0–100
	draws: number;
	black: number;
}

export interface UnifiedMove {
	uci: string;
	san: string;
	engine?: { score: number; mate: number | null; confidence: number };
	lichess?: BookStats;
	masters?: BookStats;
}

const fenKey = (fen: string) => fen.split(' ').slice(0, 4).join(' ');

// legacy token plumbing: the baked book needs no auth, but the setter stays
// so old imports keep working (and clears nothing worth clearing)
const TOKEN_KEY = 'botvinnik-lichess-token';
export function getLichessToken(): string {
	return typeof localStorage === 'undefined' ? '' : (localStorage.getItem(TOKEN_KEY) ?? '');
}
export function setLichessToken(token: string) {
	localStorage.setItem(TOKEN_KEY, token.trim());
}

interface BakedMove {
	uci: string;
	san: string;
	white: number;
	draws: number;
	black: number;
}
interface BakedNode {
	white: number;
	draws: number;
	black: number;
	moves: BakedMove[];
}

let bookPromise: Promise<Record<string, BakedNode>> | null = null;
let openingsPromise: Promise<Record<string, [string, string]>> | null = null;

function loadBook() {
	bookPromise ??= fetch('/book.json')
		.then((r) => (r.ok ? r.json() : { book: {} }))
		.then((d) => d.book ?? {});
	return bookPromise;
}
function loadOpenings() {
	openingsPromise ??= fetch('/openings.json')
		.then((r) => (r.ok ? r.json() : { openings: {} }))
		.then((d) => d.openings ?? {});
	return openingsPromise;
}

const EMPTY: ExplorerPosition = { total: 0, moves: [], opening: null };

/** Book stats from the baked assets; 'masters' resolves empty (not baked). */
export async function getExplorer(
	kind: 'lichess' | 'masters',
	fen: string
): Promise<ExplorerPosition> {
	if (kind === 'masters') return EMPTY;
	const [book, openings] = await Promise.all([loadBook(), loadOpenings()]);
	const key = fenKey(fen);
	const node = book[key];
	const op = openings[key];
	return {
		total: node ? node.white + node.draws + node.black : 0,
		moves: node?.moves ?? [],
		opening: op ? { eco: op[0], name: op[1] } : null
	};
}

// Softmax confidence over the engine's lines (same shape as botvinnik-app's
// unified moves: temperature = 1 pawn). Mates map above any clamped cp so
// they dominate; closer mates dominate further ones.
const mateScore = (mate: number) => Math.sign(mate) * (40 - Math.min(Math.abs(mate), 20));

export function confidences(engine: EngineMove[]): number[] {
	if (engine.length === 0) return [];
	const cps = engine.map((m) =>
		m.mate !== null ? mateScore(m.mate) : Math.max(-15, Math.min(15, m.score))
	);
	const max = Math.max(...cps);
	const exps = cps.map((c) => Math.exp(c - max));
	const sum = exps.reduce((a, b) => a + b, 0);
	return exps.map((e) => (e / sum) * 100);
}

/**
 * One row per move seen by the engine or either book. Book moves sort by
 * popularity; engine-only moves keep engine rank at the bottom.
 */
export function unifyMoves(
	fen: string,
	engine: EngineMove[],
	lichess: ExplorerPosition | null,
	masters: ExplorerPosition | null
): UnifiedMove[] {
	const rows = new Map<string, UnifiedMove>();
	const conf = confidences(engine);
	engine.forEach((m, i) => {
		const uci = m.pv[0];
		if (!uci || rows.has(uci)) return;
		rows.set(uci, {
			uci,
			san: getSan(fen, uci) ?? uci,
			engine: { score: m.score, mate: m.mate, confidence: conf[i] }
		});
	});
	const add = (kind: 'lichess' | 'masters', pos: ExplorerPosition | null) => {
		if (!pos) return;
		for (const mv of pos.moves) {
			const games = mv.white + mv.draws + mv.black;
			if (games === 0) continue;
			let row = rows.get(mv.uci);
			if (!row) {
				row = { uci: mv.uci, san: mv.san };
				rows.set(mv.uci, row);
			}
			row[kind] = {
				games,
				pct: pos.total > 0 ? (games / pos.total) * 100 : 0,
				white: (mv.white / games) * 100,
				draws: (mv.draws / games) * 100,
				black: (mv.black / games) * 100
			};
		}
	};
	add('lichess', lichess);
	add('masters', masters);
	// stable sort: zero-book rows keep their (engine-rank) insertion order
	return [...rows.values()].sort(
		(a, b) => (b.lichess?.games ?? b.masters?.games ?? 0) - (a.lichess?.games ?? a.masters?.games ?? 0)
	);
}

export function formatGames(n: number): string {
	if (n >= 1e9) return `${(n / 1e9).toFixed(1)}B`;
	if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
	if (n >= 1e3) return `${Math.round(n / 1e3)}k`;
	return String(n);
}
