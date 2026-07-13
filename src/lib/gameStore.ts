// Finished-game archive in IndexedDB: PGN plus the per-move grades, labels and
// explanations the app computed while the game was played.

import { bestMovePoint, type Explanation } from './engine/explain';
import type { MoveLabel } from './engine/insights';
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
	botElo: number | null;
	botColor: 'w' | 'b' | null; // side the human did NOT play (drives review orientation)
	moveCount: number;
	whiteAccuracy: number | null;
	blackAccuracy: number | null;
	labelCounts: { w: LabelCounts; b: LabelCounts };
	moves: StoredMove[];
	// imported games: real player names and where they came from
	white?: string;
	black?: string;
	source?: 'lichess' | 'chesscom';
}

// lichess's move-accuracy curve over win% loss
export function moveAccuracy(wcDrop: number): number {
	const a = 103.1668 * Math.exp(-0.04354 * Math.max(0, wcDrop)) - 3.1669;
	return Math.max(0, Math.min(100, a));
}

// simple mean of per-move accuracies over the graded moves of one side
export function gameAccuracy(moves: StoredMove[], color: 'w' | 'b'): number | null {
	const graded = moves.filter((m) => m.color === color && m.label !== undefined);
	if (graded.length === 0) return null;
	const sum = graded.reduce((a, m) => a + moveAccuracy(m.wcDrop), 0);
	return sum / graded.length;
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

// run the re-verify pass over loaded games and persist whatever it corrected;
// returns how many games were rewritten
export async function sanitizeStoredExplanations(games: StoredGame[]): Promise<number> {
	const changed = sanitizeExplanations(games);
	for (const g of changed) await saveGame(g);
	return changed.length;
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
