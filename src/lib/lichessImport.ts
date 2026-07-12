// Phase 1 of the game-import roadmap item: pull a user's analysed games from
// the Lichess API (CORS-enabled, no auth) and mine them using the server's
// per-move evals — no local engine time. Win-chance drops, labels, accuracies
// and practice items all fall out of the numbers Lichess already computed.

import { Chess, type Square } from 'chess.js';
import { bestMovePoint, type Explanation } from './engine/explain';
import { winChance, type MoveLabel } from './engine/insights';
import { gameAccuracy, labelCounts, type StoredGame, type StoredMove } from './gameStore';
import { enPassantSetup, type PracticeItem } from './practice';

// one entry per half-move; White's point of view
export interface LichessEval {
	eval?: number; // centipawns
	mate?: number;
	best?: string; // uci, present on flagged moves
	variation?: string; // SAN line of the better continuation
	judgment?: { name: string; comment: string };
}

export interface LichessGame {
	id: string;
	variant: string;
	speed: string;
	status: string;
	winner?: 'white' | 'black';
	lastMoveAt: number;
	players: {
		white: { user?: { name: string }; rating?: number };
		black: { user?: { name: string }; rating?: number };
	};
	moves: string; // space-separated SAN
	pgn?: string;
	analysis?: LichessEval[];
}

export interface PracticeCandidate {
	fen: string;
	playedSan: string;
	playedUci: string;
	bestSan: string;
	bestUci: string;
	bestPv: string[];
	setupUci?: string;
	evalBestPawns: number;
	mateBest: number | null;
	wcBest: number;
	drop: number;
	depth: number;
}

export interface LichessImportResult {
	games: StoredGame[];
	practice: PracticeCandidate[];
	skipped: number; // non-standard / unanalysed / already imported
	username: string; // as lichess spells it
}

const START_EVAL = { eval: 15 } as LichessEval; // lichess's nominal eval of the start position

function wcWhite(e: LichessEval | undefined, fallback: LichessEval): number {
	const entry = e ?? fallback;
	if (entry.mate !== undefined) return entry.mate > 0 ? 100 : 0;
	return winChance((entry.eval ?? 0) / 100, null);
}

function labelForDrop(drop: number): MoveLabel {
	if (drop >= 20) return 'blunder';
	if (drop >= 10) return 'mistake';
	if (drop >= 5) return 'inaccuracy';
	return drop <= 2 ? 'excellent' : 'good';
}

// SAN variation text -> uci list, walked from the position before the move
function variationToUcis(fenBefore: string, variation: string, max = 12): string[] {
	const out: string[] = [];
	try {
		const c = new Chess(fenBefore);
		for (const san of variation.split(/\s+/).slice(0, max)) {
			const m = c.move(san);
			if (!m) break;
			out.push(m.from + m.to + (m.promotion ?? ''));
		}
	} catch {
		// stop at first unparsable san
	}
	return out;
}

// Grade a game from per-half-move white-POV evals. The chess.com offline
// analyzer fabricates the same shape from local Stockfish output, so both
// import paths grade identically.
export function analysedGameToStored(
	game: LichessGame,
	username: string,
	source: 'lichess' | 'chesscom' = 'lichess'
): { stored: StoredGame; practice: PracticeCandidate[]; humanColor: 'w' | 'b' | null } | null {
	if (game.variant !== 'standard' || !game.analysis?.length || !game.moves) return null;

	const lower = username.toLowerCase();
	const humanColor: 'w' | 'b' | null =
		game.players.white.user?.name.toLowerCase() === lower
			? 'w'
			: game.players.black.user?.name.toLowerCase() === lower
				? 'b'
				: null;

	const c = new Chess();
	const moves: StoredMove[] = [];
	const practice: PracticeCandidate[] = [];
	const sans = game.moves.split(' ');

	for (let i = 0; i < sans.length; i++) {
		const fenBefore = c.fen();
		let m;
		try {
			m = c.move(sans[i]);
		} catch {
			return null; // corrupt movetext — skip the game entirely
		}
		if (!m) return null;
		const uci = m.from + m.to + (m.promotion ?? '');
		const color = m.color as 'w' | 'b';

		const before = game.analysis[i - 1] ?? START_EVAL;
		const after = game.analysis[i];
		// last move of a decisive game may have no eval entry — mate on the board
		const wcAfterWhite = after
			? wcWhite(after, before)
			: c.isCheckmate()
				? color === 'w'
					? 100
					: 0
				: wcWhite(undefined, before);
		const wcBeforeWhite = wcWhite(before, START_EVAL);
		const moverBefore = color === 'w' ? wcBeforeWhite : 100 - wcBeforeWhite;
		const moverAfter = color === 'w' ? wcAfterWhite : 100 - wcAfterWhite;
		const wcDrop = Math.max(0, moverBefore - moverAfter);

		const cpAfter = after?.eval;
		const mateAfter = after?.mate;
		const evalPawns =
			cpAfter !== undefined ? ((color === 'w' ? cpAfter : -cpAfter) / 100) : null;
		const mate =
			mateAfter !== undefined ? (color === 'w' ? mateAfter : -mateAfter) : null;

		const bestUci = after?.best;
		let bestPv = bestUci && after?.variation ? variationToUcis(fenBefore, after.variation) : [];
		// the server's SAN variation always starts with the best move; if parsing ever
		// drifts, never feed a mismatched line to the detectors or practice items
		if (bestUci && bestPv[0] !== bestUci) bestPv = [bestUci];
		let bestSan: string | undefined;
		if (bestUci) {
			try {
				const t = new Chess(fenBefore);
				const bm = t.move({
					from: bestUci.slice(0, 2) as Square,
					to: bestUci.slice(2, 4) as Square,
					promotion: bestUci.length > 4 ? bestUci[4] : undefined
				});
				bestSan = bm?.san;
			} catch {
				bestSan = undefined;
			}
		}

		const label = labelForDrop(wcDrop);

		// Cheap explanation backfill: only on flagged mistakes, and only when the
		// best-move detectors find a real motif — never fabricate prose. bestMovePoint
		// walks a handful of chess.js positions, so flagged-only keeps this affordable
		// inside bulk imports of thousands of games.
		let explanation: Explanation | undefined;
		if (
			(label === 'inaccuracy' || label === 'mistake' || label === 'blunder') &&
			bestUci &&
			bestPv.length >= 1
		) {
			const point = bestMovePoint(fenBefore, bestUci, bestPv);
			if (point) {
				explanation = { bestPoint: point, evidence: { fen: fenBefore, ucis: bestPv.slice(0, 9) } };
			}
		}

		moves.push({
			ply: i + 1,
			san: m.san,
			uci,
			color,
			fenBefore,
			fenAfter: c.fen(),
			evalPawns,
			mate,
			pctBest: null,
			wcDrop,
			label,
			bestSan,
			bestUci,
			explanation
		});

		// practice candidates: the importing user's own graded mistakes
		if (humanColor === color && bestUci && bestSan) {
			practice.push({
				fen: fenBefore,
				playedSan: m.san,
				playedUci: uci,
				bestSan,
				bestUci,
				bestPv: bestPv.length ? bestPv : [bestUci],
				// opponent's move into this position (previous ply), for replay context
				setupUci: moves[i - 1]?.uci ?? enPassantSetup(fenBefore) ?? undefined,
				// the best move roughly preserves the pre-move eval
				evalBestPawns:
					before.eval !== undefined ? ((color === 'w' ? before.eval : -before.eval) / 100) : 0,
				mateBest: null,
				wcBest: moverBefore,
				drop: wcDrop,
				depth: 22, // lichess server analysis depth (nominal)
			});
		}
	}

	const result =
		game.winner === 'white'
			? '1-0'
			: game.winner === 'black'
				? '0-1'
				: game.status === 'draw' || game.status === 'stalemate'
					? '1/2-1/2'
					: '*';

	const stored: StoredGame = {
		id: `${source}-${game.id}`,
		endedAt: new Date(game.lastMoveAt).toISOString(),
		result,
		pgn: game.pgn ?? '',
		botElo: null,
		botColor: humanColor === 'w' ? 'b' : humanColor === 'b' ? 'w' : null,
		moveCount: moves.length,
		whiteAccuracy: gameAccuracy(moves, 'w'),
		blackAccuracy: gameAccuracy(moves, 'b'),
		labelCounts: { w: labelCounts(moves, 'w'), b: labelCounts(moves, 'b') },
		moves,
		white: game.players.white.user?.name ?? 'Anonymous',
		black: game.players.black.user?.name ?? 'Anonymous',
		source
	};

	return { stored, practice, humanColor };
}

export function lichessGameToStored(game: LichessGame, username: string) {
	return analysedGameToStored(game, username, 'lichess');
}

export async function fetchLichessGames(
	username: string,
	max = 20
): Promise<LichessGame[]> {
	const url =
		`https://lichess.org/api/games/user/${encodeURIComponent(username)}` +
		`?max=${max}&analysed=true&evals=true&pgnInJson=true&moves=true&sort=dateDesc`;
	const res = await fetch(url, { headers: { Accept: 'application/x-ndjson' } });
	if (res.status === 404) throw new Error(`Lichess user "${username}" not found`);
	if (!res.ok) throw new Error(`Lichess API error ${res.status}`);
	const text = await res.text();
	return text
		.split('\n')
		.filter((l) => l.trim())
		.map((l) => JSON.parse(l) as LichessGame);
}

export async function importLichessGames(
	username: string,
	existingIds: Set<string>,
	collectThreshold: number,
	max = 20
): Promise<LichessImportResult> {
	const raw = await fetchLichessGames(username, max);
	const games: StoredGame[] = [];
	const practice: PracticeCandidate[] = [];
	let skipped = 0;
	for (const g of raw) {
		const mapped = lichessGameToStored(g, username);
		if (!mapped || existingIds.has(mapped.stored.id)) {
			skipped++;
			continue;
		}
		games.push(mapped.stored);
		practice.push(...mapped.practice.filter((p) => p.drop >= collectThreshold));
	}
	return { games, practice, skipped, username };
}
