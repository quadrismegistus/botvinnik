// Finished-game archive in IndexedDB: PGN plus the per-move grades, labels and
// explanations the app computed while the game was played.

import type { Explanation } from './engine/explain';
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
	botColor: 'w' | 'b' | null;
	moveCount: number;
	whiteAccuracy: number | null;
	blackAccuracy: number | null;
	labelCounts: { w: LabelCounts; b: LabelCounts };
	moves: StoredMove[];
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

export async function deleteGame(id: string): Promise<void> {
	const db = await openDb();
	if (!db) return;
	try {
		db.transaction(GAMES_STORE, 'readwrite').objectStore(GAMES_STORE).delete(id);
	} catch {
		// ignore
	}
}
