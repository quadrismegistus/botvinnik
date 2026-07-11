import { getCached, putCached } from './analysisCache';

export const MULTIPV = 5;

export interface EngineMove {
	pv: string[];
	score: number;
	mate: number | null;
	depth: number;
	multipv: number;
}

export interface EngineResult {
	moves: EngineMove[];
	bestmove: string;
	depth: number;
}

type Listener = (moves: EngineMove[]) => void;

interface SearchRequest {
	fen: string;
	depth: number;
	onUpdate: Listener;
	resolve: (result: EngineResult) => void;
	searchMoves?: string[];
	go?: string; // full go-command override (e.g. 'go movetime 400')
	options?: [string, string][]; // setoption pairs applied before the search
	resetOptions?: [string, string][]; // applied after bestmove
	minInfoDepth?: number; // info lines below this depth are ignored (default 6)
}

let worker: Worker | null = null;
let ready = false;
let searching = false;
let activeSearch: SearchRequest | null = null;
let pendingSearch: SearchRequest | null = null;
let currentMoves: Map<number, EngineMove> = new Map();

function ensureWorker(): Worker {
	if (worker) return worker;
	console.log('[stockfish] Creating worker...');
	worker = new Worker('/wasm/stockfish.js');
	worker.onmessage = (e) => handleMessage(e.data);
	worker.onerror = (e) => {
		console.error('[stockfish] Worker error, restarting:', e.message, e);
		// self-heal: rebuild the worker and re-run whatever search was wanted
		const wanted = pendingSearch ?? activeSearch;
		worker?.terminate();
		worker = null;
		ready = false;
		searching = false;
		activeSearch = null;
		pendingSearch = wanted;
		if (wanted) ensureWorker();
	};
	worker.postMessage('uci');
	return worker;
}

function startSearch(req: SearchRequest) {
	activeSearch = req;
	currentMoves = new Map();
	searching = true;
	for (const [name, value] of req.options ?? []) {
		worker?.postMessage(`setoption name ${name} value ${value}`);
	}
	worker?.postMessage('position fen ' + req.fen);
	const restrict = req.searchMoves?.length ? ' searchmoves ' + req.searchMoves.join(' ') : '';
	worker?.postMessage((req.go ?? 'go depth ' + req.depth) + restrict);
}

function maybeStartPending() {
	if (ready && !searching && pendingSearch) {
		const req = pendingSearch;
		pendingSearch = null;
		startSearch(req);
	}
}

function handleMessage(line: string) {
	if (typeof line !== 'string') return;

	if (line === 'uciok' && !ready) {
		worker?.postMessage('setoption name MultiPV value ' + MULTIPV);
		worker?.postMessage('isready');
		return;
	}

	if (line === 'readyok') {
		ready = true;
		maybeStartPending();
		return;
	}

	if (line.startsWith('info') && line.includes(' pv ')) {
		// while a new search is queued, incoming lines belong to the old position — drop them
		if (!activeSearch || pendingSearch) return;
		const move = parseInfoLine(line, activeSearch.minInfoDepth ?? 6);
		if (move) {
			currentMoves.set(move.multipv, move);
			activeSearch.onUpdate(
				Array.from(currentMoves.values()).sort((a, b) => a.multipv - b.multipv)
			);
		}
	}

	if (line.startsWith('bestmove')) {
		searching = false;
		if (activeSearch) {
			const bestmove = line.split(' ')[1];
			const moves = Array.from(currentMoves.values()).sort((a, b) => a.multipv - b.multipv);
			const depth = moves.length > 0 ? Math.max(...moves.map((m) => m.depth)) : 0;
			const finished = activeSearch;
			activeSearch = null;
			// restore engine options before anything else runs on this worker
			for (const [name, value] of finished.resetOptions ?? []) {
				worker?.postMessage(`setoption name ${name} value ${value}`);
			}
			finished.resolve({ moves, bestmove, depth });
		}
		maybeStartPending();
	}
}

function parseInfoLine(line: string, minDepth: number): EngineMove | null {
	const depthMatch = line.match(/\bdepth (\d+)/);
	const multipvMatch = line.match(/\bmultipv (\d+)/);
	const pvMatch = line.match(/\bpv (.+)/);
	const scoreMatch = line.match(/\bscore (cp|mate) (-?\d+)/);

	if (!depthMatch || !pvMatch || !scoreMatch) return null;

	const depth = parseInt(depthMatch[1]);
	if (depth < minDepth) return null;

	const scoreType = scoreMatch[1];
	const scoreVal = parseInt(scoreMatch[2]);

	return {
		pv: pvMatch[1].trim().split(/\s+/),
		score: scoreType === 'cp' ? scoreVal / 100 : 0,
		mate: scoreType === 'mate' ? scoreVal : null,
		depth,
		multipv: multipvMatch ? parseInt(multipvMatch[1]) : 1
	};
}

function queueSearch(req: SearchRequest) {
	if (pendingSearch) {
		// superseded before it ever started — resolve empty so callers don't hang
		pendingSearch.resolve({ moves: [], bestmove: '', depth: 0 });
	}
	pendingSearch = req;
	if (searching) {
		worker?.postMessage('stop');
	} else {
		maybeStartPending();
	}
}

let analyzeSeq = 0;

export function analyze(fen: string, depth: number, onUpdate: Listener): Promise<EngineResult> {
	ensureWorker();
	const seq = ++analyzeSeq;
	return new Promise((resolve) => {
		void (async () => {
			const cached = await getCached(fen, MULTIPV).catch(() => null);
			if (seq !== analyzeSeq) {
				// superseded while reading the cache — don't queue a stale search
				resolve({ moves: [], bestmove: '', depth: 0 });
				return;
			}
			const cachedDepth = cached?.lines.length ? cached.depth : 0;
			if (cached && cachedDepth > 0) {
				onUpdate(cached.lines);
				if (cachedDepth >= depth) {
					resolve({ moves: cached.lines, bestmove: cached.lines[0].pv[0], depth: cachedDepth });
					return;
				}
			}
			queueSearch({
				fen,
				depth,
				// while refining a shallower cache hit, don't regress the UI with
				// early low-depth updates
				onUpdate: (moves) => {
					const d = moves.reduce((m, l) => Math.max(m, l.depth), 0);
					if (d >= cachedDepth) onUpdate(moves);
				},
				resolve: (result) => {
					if (result.moves.length > 0) void putCached(fen, MULTIPV, result.moves, result.depth);
					resolve(result);
				}
			});
		})();
	});
}

// Evaluate one specific move in a position (UCI `go searchmoves`). Cheap:
// costs about one single-PV search at the given depth.
export function analyzeMove(fen: string, uci: string, depth: number): Promise<EngineResult> {
	ensureWorker();
	return new Promise((resolve) => {
		queueSearch({ fen, depth, onUpdate: () => {}, resolve, searchMoves: [uci] });
	});
}

// Pick the bot's move with a dedicated strength-limited search. Never touches
// the analysis cache in either direction — weakened output isn't real analysis,
// and a weak bot mustn't be handed full-strength cached lines.
// Three bands:
//  - ≥1320: the engine's calibrated UCI_Elo.
//  - 800–1319: low Skill Level + shallow depth (standard weak-bot recipe).
//  - <800: even depth-1 NNUE won't hang pieces, so instead we eval (nearly)
//    every legal move at depth 1–2 via wide MultiPV and let the caller sample
//    with a very flat softmax — true beginner play. Caller must pick from
//    result.moves, not bestmove, in this band.
export function analyzeBotMove(
	fen: string,
	elo: number,
	onUpdate: Listener = () => {}
): Promise<EngineResult> {
	ensureWorker();
	const clamped = Math.max(100, Math.min(3600, elo));
	let options: [string, string][];
	let go: string;
	if (clamped >= 1320) {
		options = [
			['MultiPV', '1'],
			['UCI_LimitStrength', 'true'],
			['UCI_Elo', String(Math.min(3190, clamped))]
		];
		go = 'go movetime 400';
	} else if (clamped >= 800) {
		const t = (clamped - 800) / (1320 - 800); // 0..1 over this band
		options = [
			['MultiPV', '1'],
			['Skill Level', String(Math.round(t * 6))] // 0..6
		];
		go = 'go depth ' + (1 + Math.round(t * 4)); // depth 1..5
	} else {
		options = [['MultiPV', '24']];
		go = 'go depth ' + (clamped < 500 ? 1 : 2);
	}
	const resetOptions: [string, string][] = [
		['UCI_LimitStrength', 'false'],
		['Skill Level', '20'],
		['MultiPV', String(MULTIPV)]
	];
	return new Promise((resolve) => {
		queueSearch({
			fen,
			depth: 0,
			onUpdate,
			resolve,
			go,
			options,
			resetOptions,
			minInfoDepth: 1
		});
	});
}

export function stopEngine() {
	if (searching) worker?.postMessage('stop');
}

export function destroyEngine() {
	worker?.postMessage('quit');
	worker?.terminate();
	worker = null;
	ready = false;
	searching = false;
	activeSearch = null;
	pendingSearch = null;
}
