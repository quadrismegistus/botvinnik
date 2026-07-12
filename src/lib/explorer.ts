// Lichess Opening Explorer (explorer.lichess.ovh) — CORS-open, no auth.
// Book stats for the current position, merged with live engine lines into
// one "unified moves" table: what's best (engine), what people play
// (lichess db), what masters play (masters db).
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
const cache = new Map<string, Promise<ExplorerPosition | null>>();

// The explorer requires an OAuth2 bearer token since ~2026 (any personal
// lichess API token works, no scopes needed). Stored per-browser.
const TOKEN_KEY = 'botvinnik-lichess-token';

export function getLichessToken(): string {
	return typeof localStorage === 'undefined' ? '' : (localStorage.getItem(TOKEN_KEY) ?? '');
}

export function setLichessToken(token: string) {
	localStorage.setItem(TOKEN_KEY, token.trim());
	cache.clear(); // 401-free retries for everything previously in flight
}

async function fetchExplorer(kind: 'lichess' | 'masters', fen: string): Promise<ExplorerPosition> {
	const params = new URLSearchParams({ fen, moves: '12', topGames: '0' });
	if (kind === 'lichess') {
		params.set('variant', 'standard');
		params.set('speeds', 'blitz,rapid,classical');
		params.set('ratings', '1400,1600,1800,2000,2200');
		params.set('recentGames', '0');
	}
	const token = getLichessToken();
	const res = await fetch(`https://explorer.lichess.org/${kind}?${params}`, {
		headers: token ? { Authorization: `Bearer ${token}` } : {}
	});
	if (res.status === 401 || res.status === 403) throw new Error('auth');
	if (!res.ok) throw new Error(`explorer ${res.status}`);
	const data = await res.json();
	return {
		total: (data.white ?? 0) + (data.draws ?? 0) + (data.black ?? 0),
		moves: (data.moves ?? []).map(
			(m: { uci: string; san: string; white: number; draws: number; black: number }) => ({
				uci: m.uci,
				san: m.san,
				white: m.white ?? 0,
				draws: m.draws ?? 0,
				black: m.black ?? 0
			})
		),
		opening: data.opening ?? null
	};
}

/** Cached per position (placement + side + castling + ep); failures are not cached. */
export function getExplorer(kind: 'lichess' | 'masters', fen: string) {
	const key = `${kind}|${fenKey(fen)}`;
	let p = cache.get(key);
	if (!p) {
		p = fetchExplorer(kind, fen).catch((e) => {
			cache.delete(key);
			throw e;
		});
		cache.set(key, p);
	}
	return p;
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
