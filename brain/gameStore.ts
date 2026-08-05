// Finished-game archive in IndexedDB: PGN plus the per-move grades, labels and
// explanations the app computed while the game was played.

import { Chess } from 'chess.js';

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
	/** Search depth of the grade. Every grading writer records it and the
	 *  collect gate filters on it; it was only ever missing from this TYPE,
	 *  which is how itemDataFromStoredMove came to hardcode 22. */
	depth?: number;
	label?: MoveLabel;
	bestSan?: string;
	/** The engine's own first choice in the position before this move. */
	bestUci?: string;
	/** Mate distance on the BEST line, mover's perspective (#283). The grade has
	 *  always carried it and storage always dropped it, so everything reading a
	 *  stored move has been reasoning without it — which is how a quiet forced
	 *  mate got filed under "open file". Absent on imports, which do not know it. */
	bestMate?: number | null;
	/** True when this game's writer recorded `bestUci` on EVERY analysed ply, so
	 *  its absence here means "nobody looked" rather than "the engine agreed".
	 *
	 *  This exists because the same field meant two different things (#281).
	 *  chesscomCore used to write `best` only when the played move was not the
	 *  engine's, mirroring lichess's "present on flagged moves" — so on an import
	 *  a bestUci marked a MISS, and 15,765 of them in a 500-game archive matched
	 *  the played move exactly zero times. Live play always wrote the engine's
	 *  move; the ambiguity was entirely in the absence.
	 *
	 *  Set by live grading and by the chess.com importer. NOT set by the lichess
	 *  importer, which genuinely cannot know: lichess omits `best` when no
	 *  judgment fired, which is weaker than "you played the top move". */
	topRecorded?: true;
	/** The engine's line behind `bestUci`, from the SAME search (#287). Written
	 *  only when the move is a practice candidate (wcDrop at or over the 5%
	 *  collect floor) — those are the only moves that can become items, and the
	 *  tagger is the only reader, so storing it everywhere would grow the
	 *  archive and the sync payload ~20% to no purpose. Its absence on a
	 *  candidate means the writer predates #287; the item then keeps the
	 *  one-move line and mate patterns/sacrifices stay untagged, which no
	 *  migration can fix — the line was never recorded. */
	bestPv?: string[];
	explanation?: Explanation;
	/** Wall time spent on this move, where it is known (#267): an in-app game,
	 *  or a PGN carrying %emt/%clk. Absent everywhere else, including every
	 *  archive written before it existed. */
	thinkMs?: number;
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
	// moves refused-mode (#167) actually rejected before they could commit —
	// distinct from botUndos: nothing was ever played to take back. Off the
	// rating ruler for the same reason (see playerElo.ts).
	refusedMoves?: number;
	// both sides were bots: there is no human result in the game at all. Written
	// by the Flutter app since #144; absent means "not known to be", which is
	// right for every game archived before it.
	botBothSides?: boolean;
	// hint overlays (arrows/threats/control, i.e. not blind) were visible on any
	// human move. ABSENT on games saved before tracking began (2026-07-16):
	// hints unknown — those games can never earn a clean crown.
	botHintsUsed?: boolean;
	// the player started this one as a RATED game: the New Game sheet's mode
	// that puts the result on the record, which turns blind on and the three
	// overlays off. The rating counts exactly these (see playerElo.ts, which
	// says why this is a stored intent and not something inferred from the
	// four switches). Absent on every game archived before #168, and on every
	// casual game after it.
	rated?: boolean;
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

/**
 * Remaining clock after each move, in ms and ply order — null where the PGN
 * says nothing. Reads the `[%clk H:MM:SS(.f)]` comments lichess and chess.com
 * stamp (and our own rated games, since #268): the time axis reads clocks
 * from PGN because it is the one storage every game shape already shares —
 * imports keep their movetext verbatim, so no stored-move field and no
 * archive migration. Textual, no board replay: a comment is attributed to
 * the move token it follows, and variations are stripped first so a sideline
 * can neither add plies nor swallow the next mainline comment.
 */
export function clocksFromPgn(pgn: string): (number | null)[] {
	const blank = pgn.indexOf('\n\n');
	let movetext = blank >= 0 ? pgn.slice(blank + 2) : pgn;
	// strip ( ... ) variations, nested — a lichess/chess.com export has none,
	// but a pasted PGN can carry anything
	let depth = 0;
	let flat = '';
	for (const ch of movetext) {
		if (ch === '(') depth++;
		else if (ch === ')') depth = Math.max(0, depth - 1);
		else if (depth === 0) flat += ch;
	}
	movetext = flat;

	const out: (number | null)[] = [];
	const RESULTS = new Set(['1-0', '0-1', '1/2-1/2', '*']);
	const token = /\{([^}]*)\}|(\S+)/g;
	let m: RegExpExecArray | null;
	while ((m = token.exec(movetext))) {
		if (m[1] !== undefined) {
			if (out.length === 0) continue; // a comment before any move
			const clk = /\[%clk\s+(\d+):(\d{1,2}):(\d{1,2}(?:\.\d+)?)\]/.exec(m[1]);
			if (clk) {
				out[out.length - 1] = Math.round(
					(Number(clk[1]) * 3600 + Number(clk[2]) * 60 + Number(clk[3])) * 1000
				);
			}
			continue;
		}
		const word = m[2];
		if (/^\d+\.+$/.test(word)) continue; // a move number ("12." or "12...")
		if (RESULTS.has(word)) continue;
		if (word.startsWith('$')) continue; // NAG
		out.push(null); // a move; the comment that follows may fill it in
	}
	return out;
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

/** How often a side played the engine's own first choice (#276). */
export interface EngineCorrelation {
	/** Moves that matched the top line. */
	played: number;
	/** Moves the question could be asked of — graded, and with a real choice. */
	total: number;
}

/**
 * How often `color` played the move the engine had first.
 *
 * Deliberately beside accuracy rather than instead of it, because the two
 * disagree in a useful way. Accuracy is a weighted average of win-chance loss
 * and is dominated by the worst move in the game, so one blunder buries forty
 * good moves. "You found the engine's move 31 times out of 40" is a different
 * and more legible fact, and a game with high correlation and low accuracy is
 * one where you saw everything and then hung a rook — which is a specific and
 * useful thing to be told.
 *
 * Two exclusions, both of which would otherwise make the number a lie:
 *
 *   * **Forced moves.** A position with one legal move is not a choice, and a
 *     game of recaptures would score 100%. Counting them measures how forcing
 *     the game was, not how well it was played.
 *   * **Ungraded moves.** No `bestUci` means the question was never asked. An
 *     import that was never analysed returns null rather than zero.
 *
 * Castling reaches the archive spelled two ways — dartchess normalises to
 * king-takes-rook (e1h1) while the importers write king-two-squares (e1g1) —
 * so both sides of the comparison go through the SAN of the move rather than
 * its UCI. Comparing the raw strings scored every castling move as a miss.
 *
 * Returns null when nothing could be counted; the caller shows a dash, not 0%.
 */
export function engineCorrelation(
	moves: StoredMove[],
	color: 'w' | 'b'
): EngineCorrelation | null {
	let played = 0;
	let total = 0;
	for (const m of moves) {
		if (m.color !== color) continue;
		// Not `bestUci` alone: on a lichess import its absence is uninformative,
		// so a game whose writer did not promise to record every ply cannot be
		// counted. See the field's own comment.
		//
		// `pctBest` is accepted as the same promise by another name, for games
		// already in the archive. This app's own graders — live and background —
		// have always written it, and have always written `bestUci`
		// unconditionally beside it; no importer writes it at all (null on every
		// one of 26,326 imported moves in the archive in data/). Requiring the
		// new flag alone would have made the row a dash on every game the player
		// had already played, which is most of them, and there is no migration
		// that could fix that after the fact.
		if (!(m.topRecorded || m.pctBest != null) || !m.bestUci) continue;
		try {
			const chess = new Chess(m.fenBefore);
			// Deduped on from+to: chess.moves() expands a promotion into four,
			// so a position whose only move is a promotion would read as four
			// choices and score as a free hit — in exactly the endgames this
			// rule exists to exclude.
			const choices = new Set(chess.moves({ verbose: true }).map((v) => v.from + v.to));
			if (choices.size < 2) continue; // no choice was on offer
			const mine = sanOf(m.fenBefore, m.uci);
			const best = sanOf(m.fenBefore, m.bestUci);
			if (mine === null || best === null) continue; // unreadable either side
			total++;
			if (mine === best) played++;
		} catch {
			continue; // a record chess.js cannot even set up: skip the move, not the game
		}
	}
	return total === 0 ? null : { played, total };
}

/**
 * The SAN of `uci` in `fen`, or null if it is not a legal move there.
 *
 * Castling is why this exists. dartchess spells it king-TAKES-ROOK (e1h1) and
 * chess.js rejects that outright in standard chess, so without the rewrite
 * below every castling move in the archive was unreadable and silently skipped
 * — and the two spellings never compared equal as raw strings either.
 */
function sanOf(fen: string, uci: string): string | null {
	try {
		const c = new Chess(fen);
		const from = uci.slice(0, 2);
		let to = uci.slice(2, 4);
		const moved = c.get(from as never);
		const landed = c.get(to as never);
		// Only a rook on its ORIGINAL file can be a castling target. Accepting
		// any friendly rook rewrote a king's move onto a rook on f1 into O-O-O,
		// which is a match for a move that was never made.
		if (
			moved?.type === 'k' &&
			landed?.type === 'r' &&
			landed.color === moved.color &&
			(to[0] === 'a' || to[0] === 'h')
		) {
			to = (to[0] === 'h' ? 'g' : 'c') + to[1];
		}
		return c.move({ from, to, promotion: uci.length > 4 ? uci[4] : undefined }).san;
	} catch {
		return null;
	}
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
// (fork / pin / skewer / trap / free capture / discovered) against the current
// detectors and rewrite or drop the sentence. Only bestPoint/playedPoint can
// carry these claims, and their detectors need nothing beyond fenBefore + the
// move — the material fallback (which needs the full PV) can't fire with a
// 1-move line, so a dead claim falls through to the remaining detectors or is
// dropped, never invented.
const STALE_CLAIM =
	/ (?:forks|pins|skewers|traps) the | simply wins the | discovers check from | attack on the /;

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
