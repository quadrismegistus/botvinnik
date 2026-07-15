// Finished-game archive in IndexedDB: PGN plus the per-move grades, labels and
// explanations the app computed while the game was played.

import { bestMovePoint, type Explanation } from './engine/explain';
import { isCapture } from './engine/chess';
import { winChance, type MoveLabel } from './engine/insights';

// Bump when the move-label rules change (added Miss, tightened Brilliant at v1).
// Games carry labelVersion; older ones are re-labeled from stored eval data on
// load (relabelGames), newer ones are stamped at save and skipped.
export const LABEL_VERSION = 1;
import { GAMES_STORE, openDb } from './engine/db';

export interface StoredMove {
	ply: number;
	san: string;
	uci: string;
	color: 'w' | 'b';
	fenBefore: string;
	fenAfter: string;
	evalPawns: number | null;
	mate: number | null;
	pctBest: number | null;
	wcDrop: number; // win% lost vs the best move (0 when ungraded)
	label?: MoveLabel;
	bestSan?: string;
	bestUci?: string;
	explanation?: Explanation;
}

export type LabelCounts = Partial<Record<MoveLabel, number>>;

export interface StoredGame {
	id: string;
	endedAt: string;
	result: string; // '1-0' | '0-1' | '1/2-1/2' | '*' (abandoned)
	pgn: string;
	botElo: number | null; // app-internal WASM scale (persona games store personaInternalElo)
	botPersona?: string; // roster persona id (bots.ts); absent for slider/legacy games
	botFallback?: boolean; // some moves came from the Stockfish stand-in, not the persona's engine
	botUndos?: number; // takebacks the human used — assisted result, off the rating ruler
	botColor: 'w' | 'b' | null; // side the human did NOT play (drives review orientation)
	moveCount: number;
	whiteAccuracy: number | null;
	blackAccuracy: number | null;
	labelCounts: { w: LabelCounts; b: LabelCounts };
	labelVersion?: number; // ruleset the labels were computed under (see LABEL_VERSION)
	moves: StoredMove[];
	// imported games: real player names and where they came from
	white?: string;
	black?: string;
	source?: 'lichess' | 'chesscom';
}

// lichess's move-accuracy curve over win% loss, incl. lila's +1 "uncertainty
// bonus" (AccuracyPercent.fromWinPercents)
export function moveAccuracy(wcDrop: number): number {
	const a = 103.1668 * Math.exp(-0.04354 * Math.max(0, wcDrop)) - 3.1669 + 1;
	return Math.max(0, Math.min(100, a));
}

function stdDev(xs: number[]): number {
	if (xs.length === 0) return 0;
	const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
	return Math.sqrt(xs.reduce((a, b) => a + (b - mean) * (b - mean), 0) / xs.length);
}

// Game accuracy per side, mirroring lichess (lila AccuracyPercent.gameAccuracy):
// per-move accuracies weighted by local win% VOLATILITY (sliding-window stddev,
// clamped 0.5–12 — sharp phases count more than dead-level shuffling), averaged
// with the unweighted HARMONIC mean, which is what actually punishes blunders.
// The old plain mean barely noticed a single terrible move, which is why our
// numbers ran far above chess.com's CAPS for the same game.
export function gameAccuracy(moves: StoredMove[], color: 'w' | 'b'): number | null {
	if (!moves.some((m) => m.color === color && m.label !== undefined)) return null;

	// white-POV win% after every ply, start position in front; unevaluated
	// plies carry the previous value forward (neutral for the volatility)
	const wps: number[] = [50];
	let last = 50;
	for (const m of moves) {
		if (m.evalPawns !== null || m.mate !== null) {
			const wc = winChance(m.evalPawns, m.mate);
			last = m.color === 'w' ? wc : 100 - wc;
		}
		wps.push(last);
	}

	const windowSize = Math.max(2, Math.min(8, Math.floor(wps.length / 10)));
	// one window per move: pad with copies of the first window, then slide
	const windows: number[][] = [];
	for (let k = 0; k < windowSize - 2; k++) windows.push(wps.slice(0, windowSize));
	for (let s = 0; s + windowSize <= wps.length; s++) windows.push(wps.slice(s, s + windowSize));

	let weightSum = 0;
	let weightedSum = 0;
	let invSum = 0;
	let n = 0;
	moves.forEach((m, i) => {
		if (m.color !== color || m.label === undefined) return;
		const acc = moveAccuracy(m.wcDrop);
		const weight = Math.max(0.5, Math.min(12, stdDev(windows[Math.min(i, windows.length - 1)] ?? wps)));
		weightedSum += acc * weight;
		weightSum += weight;
		invSum += 1 / acc; // acc 0 → Infinity → harmonic 0, as in lila
		n++;
	});
	const weighted = weightedSum / weightSum;
	const harmonic = n / invSum;
	return Math.max(0, Math.min(100, (weighted + harmonic) / 2));
}

export function labelCounts(moves: StoredMove[], color: 'w' | 'b'): LabelCounts {
	const out: LabelCounts = {};
	for (const m of moves) {
		if (m.color !== color || !m.label) continue;
		out[m.label] = (out[m.label] ?? 0) + 1;
	}
	return out;
}

export async function saveGame(game: StoredGame): Promise<void> {
	const db = await openDb();
	if (!db) return;
	try {
		db.transaction(GAMES_STORE, 'readwrite').objectStore(GAMES_STORE).put(game);
	} catch {
		// storage failures are never fatal
	}
}

export async function listGames(): Promise<StoredGame[]> {
	const db = await openDb();
	if (!db) return [];
	return new Promise((resolve) => {
		try {
			const req = db.transaction(GAMES_STORE, 'readonly').objectStore(GAMES_STORE).getAll();
			req.onsuccess = () => {
				const games = (req.result as StoredGame[]) ?? [];
				games.sort((a, b) => Date.parse(b.endedAt) - Date.parse(a.endedAt));
				resolve(games);
			};
			req.onerror = () => resolve([]);
		} catch {
			resolve([]);
		}
	});
}

// Stored explanation prose is frozen at analysis time, so when a detector's
// rules tighten, already-saved sentences can claim motifs the detectors no
// longer stand behind. Re-verify the claim families whose rules have changed
// (fork / pin / skewer) against the current detectors and rewrite or drop the
// sentence. Only bestPoint/playedPoint can carry these claims, and their
// detectors need nothing beyond fenBefore + the move — the material fallback
// (which needs the full PV) can't fire with a 1-move line, so a dead claim
// falls through to the remaining detectors or is dropped, never invented.
const STALE_CLAIM = / (?:forks|pins|skewers) the /;

export function sanitizeExplanations(games: StoredGame[]): StoredGame[] {
	const changed: StoredGame[] = [];
	for (const g of games) {
		let dirty = false;
		for (const m of g.moves) {
			const e = m.explanation;
			if (!e) continue;
			for (const field of ['bestPoint', 'playedPoint'] as const) {
				const text = e[field];
				if (!text || !STALE_CLAIM.test(text)) continue;
				const uci = field === 'bestPoint' ? m.bestUci : m.uci;
				const fresh = uci ? bestMovePoint(m.fenBefore, uci, [uci]) : undefined;
				if (fresh === text) continue; // the claim still holds verbatim
				if (fresh) e[field] = fresh;
				else delete e[field];
				dirty = true;
			}
		}
		if (dirty) changed.push(g);
	}
	return changed;
}

// pure: recompute stored per-side accuracies with the current formula (only
// possible for games that kept their full move data)
export function refreshAccuracies(games: StoredGame[]): StoredGame[] {
	const changed: StoredGame[] = [];
	const differs = (a: number | null, b: number | null) =>
		a === null || b === null ? a !== b : Math.abs(a - b) > 0.05;
	for (const g of games) {
		if (g.moves.length === 0) continue;
		const w = gameAccuracy(g.moves, 'w');
		const b = gameAccuracy(g.moves, 'b');
		if (differs(w, g.whiteAccuracy) || differs(b, g.blackAccuracy)) {
			g.whiteAccuracy = w;
			g.blackAccuracy = b;
			changed.push(g);
		}
	}
	return changed;
}

// Re-derive one move's label under the current ruleset from stored eval data
// (no engine). Only touches the cases the ruleset changed: Brilliant's floor
// and the new Miss. Everything else keeps its label.
function relabelMove(m: StoredMove): MoveLabel | undefined {
	if (!m.label) return m.label;
	const wcPlayed = winChance(m.evalPawns, m.mate);
	// Brilliant now needs the sacrifice to leave you clearly better (>=55). An
	// already-brilliant move passed the sacrifice test, so just re-check the
	// floor — demote to best when it merely held equality.
	if (m.label === 'brilliant') return wcPlayed < 55 ? 'best' : 'brilliant';
	// Miss: a missed material-winning capture you were still ok after. The best
	// move's full line isn't stored, so this leans on the >=10% drop as the
	// proxy that the capture mattered (slightly looser than live labeling).
	if (m.label === 'inaccuracy' || m.label === 'mistake' || m.label === 'blunder') {
		if (
			m.bestUci &&
			m.bestUci !== m.uci &&
			m.wcDrop >= 10 &&
			wcPlayed >= 40 &&
			isCapture(m.fenBefore, m.bestUci)
		)
			return 'miss';
	}
	return m.label;
}

// pure: bring games labeled under an older ruleset up to the current one and
// recompute their label counts. Games already at LABEL_VERSION are skipped;
// unchanged older games stay unstamped and are harmlessly re-checked next load.
export function relabelGames(games: StoredGame[]): StoredGame[] {
	const changed: StoredGame[] = [];
	for (const g of games) {
		if (g.labelVersion === LABEL_VERSION) continue;
		let dirty = false;
		for (const m of g.moves) {
			const next = relabelMove(m);
			if (next !== m.label) {
				m.label = next;
				dirty = true;
			}
		}
		if (dirty) {
			g.labelVersion = LABEL_VERSION;
			g.labelCounts = { w: labelCounts(g.moves, 'w'), b: labelCounts(g.moves, 'b') };
			changed.push(g);
		}
	}
	return changed;
}

// run the load-time repair passes (stale claim prose, accuracy formula, and
// move-label ruleset changes) and persist whatever they corrected; returns
// the number of games rewritten
export async function sanitizeStoredGames(games: StoredGame[]): Promise<number> {
	const changed = new Set([
		...sanitizeExplanations(games),
		...refreshAccuracies(games),
		...relabelGames(games)
	]);
	for (const g of changed) await saveGame(g);
	return changed.size;
}

export async function deleteGame(id: string): Promise<void> {
	const db = await openDb();
	if (!db) return;
	try {
		db.transaction(GAMES_STORE, 'readwrite').objectStore(GAMES_STORE).delete(id);
	} catch {
		// ignore
	}
}
