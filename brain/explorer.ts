// The unified move table: what the ENGINE says about a move and what people
// actually PLAY, merged into one ranked list. Ported from the retired Svelte
// app's `explorer.ts` (svelte-eol), which is where this arithmetic has always
// lived — the merge is the point of the panel, and the interesting rows are
// the disagreements: a popular move the engine dislikes is a trap or a
// fashion, an engine move nobody plays is a novelty.
//
// Only the pure arithmetic came across. The Svelte module also fetched
// `/book.json` and kept a legacy lichess token in localStorage; the Flutter
// app loads the baked assets itself (lib/stores/book_store.dart) and hands the
// counted node in, so nothing here touches fetch, storage, or the DOM.
//
// Masters stats are not baked (master games aren't in the public CC0 dumps),
// so callers pass null for that source today. The parameter stays because the
// merge and the sort both already handle a second book, and dropping it would
// have to be rewritten the day an OTB collection is baked.

import { getSan } from './engine/chess';
import type { EngineMove } from './engine/types';

/** One move's share of a position, as percentages — never raw counts. */
export interface BookStats {
	games: number;
	pct: number; // share of games at this position, 0-100
	white: number; // W/D/L shares of THIS move's games, 0-100
	draws: number;
	black: number;
}

export interface ExplorerMove {
	uci: string;
	san: string;
	white: number;
	draws: number;
	black: number;
}

/** A book node: the games reaching a position, and the moves played from it. */
export interface ExplorerPosition {
	total: number;
	moves: ExplorerMove[];
}

export interface UnifiedMove {
	uci: string;
	san: string;
	engine?: { score: number; mate: number | null; confidence: number };
	lichess?: BookStats;
	masters?: BookStats;
}

// Mates map above any clamped cp so they dominate the softmax; closer mates
// dominate further ones. 40 is comfortably clear of the ±15 clamp below, so a
// mate in 20 (the floor, at 20) still outranks a +15 evaluation.
const mateScore = (mate: number) => Math.sign(mate) * (40 - Math.min(Math.abs(mate), 20));

/**
 * Softmax over the engine's lines, in percent — how confident the engine is
 * that each line is the move, not how good the move is. Temperature is one
 * pawn: two lines a pawn apart come out roughly 73/27.
 *
 * The clamp matters more than it looks. Without it a +30 line exponentiates
 * to everything and every other move rounds to 0%, which says "certain" about
 * a position where the engine is merely winning several ways.
 */
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
 * One row per move seen by the engine or by either book, sorted by how often
 * it is PLAYED — engine-only moves have no game count and so fall to the
 * bottom, where they keep their engine rank (the sort is stable, and engine
 * rows are inserted in engine order).
 *
 * Popularity, not evaluation, is the sort key on purpose: the engine's own
 * ranking is already the Lines panel, and sorting by it here would bury the
 * comparison this table exists to make.
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
			san: getSan(fen, uci), // falls back to the uci itself on an illegal move
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
