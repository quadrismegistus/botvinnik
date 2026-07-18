// chess.com game → the lichess-shaped analysed game our grading code eats.
// The evaluator is injected: the in-app importer uses the engine ImportPool,
// the offline script uses its own native process pool — identical grading.

import { Chess, type Square } from 'chess.js';
import type { UciEval } from './engine/importPool';
import type { LichessEval, LichessGame } from './lichessImport';

export interface CcGame {
	uuid: string;
	pgn?: string;
	rules: string;
	time_class: string;
	end_time: number;
	white: { username: string; rating: number; result: string };
	black: { username: string; rating: number; result: string };
}

function toWhitePov(r: UciEval, whiteToMove: boolean): LichessEval {
	const sign = whiteToMove ? 1 : -1;
	if (r.mate !== undefined) return { mate: sign * r.mate };
	return { eval: sign * (r.cp ?? 0) };
}

// Analyze every position of a chess.com game and fabricate the lichess
// analysis shape (entry i = after move i, best/variation from the position
// before move i). Returns null for non-standard/corrupt/trivial games.
export async function ccGameToAnalysed(
	cc: CcGame,
	evalPosition: (fen: string) => Promise<UciEval>,
	signal?: { aborted: boolean }
): Promise<LichessGame | null> {
	if (cc.rules !== 'chess' || !cc.pgn) return null;
	const c = new Chess();
	try {
		c.loadPgn(cc.pgn);
	} catch {
		return null;
	}
	const history = c.history({ verbose: true });
	if (history.length < 4) return null;

	const walker = new Chess();
	const fens: string[] = [walker.fen()];
	for (const m of history) {
		walker.move(m.san);
		fens.push(walker.fen());
	}
	const results = await Promise.all(
		fens.map(async (fen) => {
			if (signal?.aborted) return null;
			const probe = new Chess(fen);
			if (probe.isGameOver()) return null; // terminal — no search needed
			return evalPosition(fen);
		})
	);
	if (signal?.aborted) return null;

	const analysis: LichessEval[] = [];
	for (let i = 0; i < history.length; i++) {
		const posAfter = fens[i + 1];
		const whiteToMoveAfter = posAfter.split(' ')[1] === 'w';
		const rAfter = results[i + 1];
		let entry: LichessEval;
		if (rAfter) {
			entry = toWhitePov(rAfter, whiteToMoveAfter);
		} else {
			// terminal position: the side to move is mated, or it's a draw
			const probe = new Chess(posAfter);
			entry = probe.isCheckmate() ? { mate: whiteToMoveAfter ? -1 : 1 } : { eval: 0 };
		}
		const rBefore = results[i];
		if (rBefore && rBefore.pv.length) {
			const playedUci = history[i].from + history[i].to + (history[i].promotion ?? '');
			if (rBefore.pv[0] !== playedUci) {
				entry.best = rBefore.pv[0];
				const t = new Chess(fens[i]);
				const sans: string[] = [];
				for (const uci of rBefore.pv.slice(0, 10)) {
					try {
						const m = t.move({
							from: uci.slice(0, 2) as Square,
							to: uci.slice(2, 4) as Square,
							promotion: uci.length > 4 ? uci[4] : undefined
						});
						if (!m) break;
						sans.push(m.san);
					} catch {
						break;
					}
				}
				entry.variation = sans.join(' ');
			}
		}
		analysis.push(entry);
	}

	const winner =
		cc.white.result === 'win' ? ('white' as const) : cc.black.result === 'win' ? ('black' as const) : undefined;
	return {
		id: cc.uuid,
		variant: 'standard',
		speed: cc.time_class,
		status: winner ? 'mate' : 'draw',
		winner,
		lastMoveAt: cc.end_time * 1000,
		players: {
			white: { user: { name: cc.white.username }, rating: cc.white.rating },
			black: { user: { name: cc.black.username }, rating: cc.black.rating }
		},
		moves: history.map((m) => m.san).join(' '),
		pgn: cc.pgn,
		analysis
	};
}

export async function fetchChesscomArchives(username: string): Promise<string[]> {
	const res = await fetch(
		`https://api.chess.com/pub/player/${encodeURIComponent(username.toLowerCase())}/games/archives`
	);
	if (res.status === 404) throw new Error(`chess.com user "${username}" not found`);
	if (!res.ok) throw new Error(`chess.com API error ${res.status}`);
	const data = (await res.json()) as { archives: string[] };
	return data.archives.reverse(); // newest first
}

export async function fetchChesscomMonth(url: string): Promise<CcGame[]> {
	const res = await fetch(url);
	if (!res.ok) throw new Error(`chess.com API error ${res.status}`);
	const data = (await res.json()) as { games: CcGame[] };
	return data.games.sort((a, b) => b.end_time - a.end_time);
}
