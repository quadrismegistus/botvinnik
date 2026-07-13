import { base } from '$app/paths';
import { getCached, putCached } from './analysisCache';
import { botRecipe, botResetOptions } from './botRecipe';

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

// The engine speaks UCI over a pluggable transport: the default is the WASM
// build in a web worker; a Tauri shell can swap in a native-process transport
// via setEngineTransport() before the first search.
export interface EngineTransport {
	send(cmd: string): void;
	terminate(): void;
}
export type TransportFactory = (
	onLine: (line: string) => void,
	onError: (message: string) => void
) => EngineTransport;

const wasmWorkerTransport: TransportFactory = (onLine, onError) => {
	const w = new Worker(`${base}/wasm/stockfish.js`);
	w.onmessage = (e) => onLine(e.data);
	w.onerror = (e) => onError(e.message);
	return {
		send: (cmd) => w.postMessage(cmd),
		terminate: () => w.terminate()
	};
};

let transportFactory: TransportFactory = wasmWorkerTransport;

// Live analysis runs on a time slice with a depth ceiling — the engine stops
// at whichever comes first, and the UI keeps whatever depth streamed in.
export interface AnalysisBudget {
	depth: number; // ceiling
	movetimeMs: number; // time slice
}
let analysisBudget: AnalysisBudget = { depth: 22, movetimeMs: 3000 };

export function getAnalysisBudget(): AnalysisBudget {
	return analysisBudget;
}

export function setEngineTransport(factory: TransportFactory, budget?: AnalysisBudget) {
	transportFactory = factory;
	if (budget) analysisBudget = budget;
}

let worker: EngineTransport | null = null;
let ready = false;
let searching = false;
let activeSearch: SearchRequest | null = null;
let pendingSearch: SearchRequest | null = null;
let currentMoves: Map<number, EngineMove> = new Map();

function ensureWorker(): EngineTransport {
	if (worker) return worker;
	console.log('[stockfish] Creating engine...');
	worker = transportFactory(
		(line) => handleMessage(line),
		(message) => {
			console.error('[stockfish] Engine error, restarting:', message);
			// self-heal: rebuild the engine and re-run whatever search was wanted
			const wanted = pendingSearch ?? activeSearch;
			worker?.terminate();
			worker = null;
			ready = false;
			searching = false;
			activeSearch = null;
			pendingSearch = wanted;
			if (wanted) ensureWorker();
		}
	);
	worker.send('uci');
	return worker;
}

function startSearch(req: SearchRequest) {
	activeSearch = req;
	currentMoves = new Map();
	searching = true;
	for (const [name, value] of req.options ?? []) {
		worker?.send(`setoption name ${name} value ${value}`);
	}
	worker?.send('position fen ' + req.fen);
	const restrict = req.searchMoves?.length ? ' searchmoves ' + req.searchMoves.join(' ') : '';
	worker?.send((req.go ?? 'go depth ' + req.depth) + restrict);
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
		worker?.send('setoption name MultiPV value ' + MULTIPV);
		worker?.send('isready');
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
		// bound reports (fail-high/low near a stop) carry truncated PVs — skip them
		if (/ (upper|lower)bound /.test(line)) return;
		const move = parseInfoLine(line, activeSearch.minInfoDepth ?? 6);
		if (move) {
			// if the engine still truncated the PV of the same root move, keep the
			// longer continuation we already had
			const prev = currentMoves.get(move.multipv);
			if (prev && prev.pv[0] === move.pv[0] && move.pv.length < prev.pv.length && move.pv.length < 4) {
				move.pv = prev.pv;
			}
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
				worker?.send(`setoption name ${name} value ${value}`);
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
		worker?.send('stop');
	} else {
		maybeStartPending();
	}
}

let analyzeSeq = 0;

export function analyze(
	fen: string,
	depth: number,
	onUpdate: Listener,
	movetimeMs?: number
): Promise<EngineResult> {
	ensureWorker();
	const seq = ++analyzeSeq;
	// with a time budget the depth ceiling is aspirational — a cache entry
	// within a few plies of it came from a full slice; don't re-burn the slice
	const goodEnough = movetimeMs ? Math.max(12, depth - 4) : depth;
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
				if (cachedDepth >= goodEnough) {
					resolve({ moves: cached.lines, bestmove: cached.lines[0].pv[0], depth: cachedDepth });
					return;
				}
			}
			queueSearch({
				fen,
				depth,
				go: movetimeMs ? `go depth ${depth} movetime ${movetimeMs}` : undefined,
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
	// the band logic lives in botRecipe.ts, shared with the calibration harness
	const recipe = botRecipe(elo);
	return new Promise((resolve) => {
		queueSearch({
			fen,
			depth: 0,
			onUpdate,
			resolve,
			go: recipe.go,
			options: recipe.options,
			resetOptions: botResetOptions(MULTIPV),
			minInfoDepth: 1
		});
	});
}

export function stopEngine() {
	if (searching) worker?.send('stop');
}

export function destroyEngine() {
	worker?.send('quit');
	worker?.terminate();
	worker = null;
	ready = false;
	searching = false;
	activeSearch = null;
	pendingSearch = null;
}
