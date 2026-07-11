// Per-position analysis cache in IndexedDB. Keyed by the position-identity
// part of the FEN (piece placement, side to move, castling, en passant —
// move counters dropped) plus engine identity and MultiPV, so results are
// only reused where they're actually equivalent.

import { ANALYSIS_STORE as STORE, openDb } from './db';
import type { EngineMove } from './stockfish';

export interface CachedAnalysis {
	key: string;
	fen: string;
	lines: EngineMove[];
	depth: number;
	updatedAt: number;
	lastUsedAt: number;
}

const MAX_ENTRIES = 20_000;
const PRUNE_BATCH = 1_000;
const MIN_DEPTH_TO_STORE = 12;

let putsSincePrune = 0;

export function cacheKey(fen: string, multipv: number): string {
	return fen.split(' ').slice(0, 4).join(' ') + '|mpv' + multipv + '|sf18-lite';
}

export async function getCached(fen: string, multipv: number): Promise<CachedAnalysis | null> {
	const db = await openDb();
	if (!db) return null;
	return new Promise((resolve) => {
		try {
			const store = db.transaction(STORE, 'readwrite').objectStore(STORE);
			const req = store.get(cacheKey(fen, multipv));
			req.onsuccess = () => {
				const rec = req.result as CachedAnalysis | undefined;
				if (rec) {
					rec.lastUsedAt = Date.now();
					store.put(rec);
				}
				resolve(rec ?? null);
			};
			req.onerror = () => resolve(null);
		} catch {
			resolve(null);
		}
	});
}

export async function putCached(
	fen: string,
	multipv: number,
	lines: EngineMove[],
	depth: number
): Promise<void> {
	if (depth < MIN_DEPTH_TO_STORE || lines.length === 0) return;
	const db = await openDb();
	if (!db) return;
	try {
		const now = Date.now();
		const rec: CachedAnalysis = {
			key: cacheKey(fen, multipv),
			fen,
			lines,
			depth,
			updatedAt: now,
			lastUsedAt: now
		};
		db.transaction(STORE, 'readwrite').objectStore(STORE).put(rec);
		if (++putsSincePrune >= 50) {
			putsSincePrune = 0;
			prune(db);
		}
	} catch {
		// cache write failures are never fatal
	}
}

// drop least-recently-used entries once over the cap
function prune(db: IDBDatabase) {
	try {
		const store = db.transaction(STORE, 'readwrite').objectStore(STORE);
		const countReq = store.count();
		countReq.onsuccess = () => {
			const excess = countReq.result - MAX_ENTRIES;
			if (excess <= 0) return;
			const target = excess + PRUNE_BATCH;
			let deleted = 0;
			const cursorReq = store.index('lastUsedAt').openCursor();
			cursorReq.onsuccess = () => {
				const cur = cursorReq.result;
				if (!cur || deleted >= target) return;
				cur.delete();
				deleted++;
				cur.continue();
			};
		};
	} catch {
		// ignore
	}
}
