#!/usr/bin/env npx tsx
/**
 * Bot ELO calibration harness — bots at different settings play each other
 * headlessly so the strength labels stop being taken on faith.
 *
 * Each test point plays its ladder neighbours (plus a couple of long-range
 * sanity pairs) from a small balanced opening book, colors alternating. Move
 * selection replicates the app exactly: the shared botRecipe() band logic and
 * the same selectBotMove() sampler for the beginner band. Results feed a
 * Bradley–Terry fit; the scale is anchored so the UCI_Elo band (the only band
 * with external calibration) averages its nominal labels.
 *
 * Usage:
 *   npx tsx scripts/calibrate-bots.mts [options]
 *
 * Options:
 *   --points a,b,c   test settings (default 100,300,500,700,800,1000,1200,1320,1600,2000)
 *   --games N        games per pair (default 40; even, so colors balance)
 *   --workers N      parallel games / engine processes (default: cores - 2)
 *   --max-plies N    adjudicate unfinished games after N plies (default 160)
 *   --engine PATH    stockfish binary (default: `stockfish` on PATH)
 *   --out FILE       results JSON (default data/bot-calibration.json)
 *
 * Resumable: finished games are checkpointed in <out>.state.json — rerun with
 * the same settings to continue, delete the state file to start over.
 *
 * CAVEAT: a native binary is (much) faster than the app's single-threaded
 * WASM build. The fixed-depth bands (<1320) don't care, but the UCI_Elo band
 * searches `movetime 400` — on stronger hardware its base search is deeper, so
 * treat the anchor band's absolute level as an upper bound for the app.
 */

import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Chess } from 'chess.js';
import { selectBotMove } from '../src/lib/bot';
import {
	botResetOptions,
	parseSpec,
	setBotSubstrate,
	specToRecipe,
	type Substrate
} from '../src/lib/engine/botRecipe';
import type { EngineMove } from '../src/lib/engine/stockfish';
import { isMaiaId, maiaBandOf, maiaMoveNode, preloadMaiaBands } from './maia-node.mts';
import { isMaia3Id, maia3EloOf, maiaMove3Node, preloadMaia3 } from './maia3-node.mts';

// ---------- args ----------
const args = process.argv.slice(2);
function opt(name: string, dflt: number): number {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? Number(args[i + 1]) : dflt;
}
function optStr(name: string, dflt: string): string {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? args[i + 1] : dflt;
}
// points are requested-ELO numbers (mapped through the app's botSpec), raw
// spec ids like "sampler:a2:d2" / "skill:1:d2" / "ucielo:2400:mt400", or Maia
// nets "maia:1500" (human-imitation, lichess-anchored — see maia-node.mts).
// Pit our bands against Maia to read our scale in human-rating terms.
const POINTS = optStr('points', '100,300,500,700,800,1000,1200,1320,1600,2000')
	.split(',')
	.sort((a, b) => (Number(a) || 1e9) - (Number(b) || 1e9));
const PAIRS_ARG = optStr('pairs', ''); // explicit "idA~idB,idC~idD" (probe mode)
const GAMES = Math.max(2, Math.ceil(opt('games', 40) / 2) * 2);
const WORKERS = Math.max(1, opt('workers', os.cpus().length - 2));
const MAX_PLIES = opt('max-plies', 160);
// resolve the NATIVE binary explicitly: under `npx tsx`, node_modules/.bin is
// prepended to PATH, so a bare "stockfish" silently picks the npm package's
// WASM CLI shim — which is a different net, slower, and occasionally drops a
// bestmove (three hung workers taught us this)
const NATIVE_CANDIDATES = [
	'/opt/homebrew/bin/stockfish',
	'/usr/local/bin/stockfish',
	'/usr/bin/stockfish'
];
const ENGINE = optStr('engine', NATIVE_CANDIDATES.find((p) => existsSync(p)) ?? 'stockfish');
if (ENGINE.includes('node_modules')) {
	console.warn(`WARNING: engine resolves inside node_modules (${ENGINE}) — the WASM CLI shim`);
}
// which knot table numeric ids map through (bare-number ids → botSpec). The
// harness measures the two substrates separately: native SF by default, the
// app's WASM build when pointed at scripts/wasm-engine via --substrate wasm.
const SUBSTRATE = optStr('substrate', 'native') as Substrate;
setBotSubstrate(SUBSTRATE);
console.log(`engine: ${ENGINE} · substrate: ${SUBSTRATE}`);
const SEARCH_TIMEOUT_MS = 60_000;
const OUT = optStr('out', 'data/bot-calibration.json');
const STATE = `${OUT}.state.json`;

// probe mode: explicit pairs; otherwise ladder neighbours + long-range
// sanity pairs (fit stiffness across seams)
let pairs: [string, string][];
let allIds: string[];
if (PAIRS_ARG) {
	pairs = PAIRS_ARG.split(',').map((p) => {
		const [a, b] = p.split('~');
		return [a, b] as [string, string];
	});
	allIds = [...new Set(pairs.flat())];
} else {
	pairs = [];
	for (let i = 0; i + 1 < POINTS.length; i++) pairs.push([POINTS[i], POINTS[i + 1]]);
	for (const [a, b] of [
		[POINTS[0], POINTS[Math.min(2, POINTS.length - 1)]],
		['800', '1320']
	] as [string, string][]) {
		if (
			POINTS.includes(a) &&
			POINTS.includes(b) &&
			a !== b &&
			!pairs.some(([x, y]) => x === a && y === b)
		) {
			pairs.push([a, b]);
		}
	}
	allIds = POINTS;
}

// short balanced openings (4 plies) — each pair plays each opening twice with
// colors swapped, the standard match convention
const OPENINGS = [
	'e4 e5 Nf3 Nc6',
	'd4 d5 c4 e6',
	'e4 c5 Nf3 d6',
	'd4 Nf6 c4 e6',
	'e4 e6 d4 d5',
	'c4 e5 Nc3 Nf6',
	'd4 d5 Nf3 Nf6',
	'e4 c5 Nf3 Nc6',
	'e4 e5 Nf3 Nf6',
	'd4 Nf6 c4 g6',
	'Nf3 d5 g3 Nf6',
	'e4 c6 d4 d5'
];

// ---------- engine ----------
interface SearchOut {
	moves: EngineMove[];
	bestmove: string;
}

class Engine {
	proc!: ChildProcessWithoutNullStreams;
	busy = false;
	private buffer = '';
	private resolve: ((r: SearchOut) => void) | null = null;
	private byMultipv = new Map<number, EngineMove>();
	private watchdog: NodeJS.Timeout | null = null;

	constructor() {
		this.start();
	}

	private start() {
		this.buffer = '';
		this.proc = spawn(ENGINE);
		this.proc.on('error', (e) => {
			console.error(`cannot start engine "${ENGINE}": ${e.message}`);
			process.exit(1);
		});
		this.proc.stdout.on('data', (d) => this.onData(String(d)));
		this.proc.stdin.write('uci\nsetoption name Threads value 1\nsetoption name Hash value 32\nisready\n');
	}

	private onData(chunk: string) {
		this.buffer += chunk;
		const lines = this.buffer.split('\n');
		this.buffer = lines.pop() ?? '';
		for (const line of lines) {
			if (line.startsWith('info ') && line.includes(' pv ')) {
				const depth = Number(line.match(/ depth (\d+)/)?.[1] ?? 0);
				const multipv = Number(line.match(/ multipv (\d+)/)?.[1] ?? 1);
				const cp = line.match(/ score cp (-?\d+)/);
				const mate = line.match(/ score mate (-?\d+)/);
				const pv = line.split(' pv ')[1]?.trim().split(' ') ?? [];
				if (pv.length) {
					this.byMultipv.set(multipv, {
						pv,
						score: cp ? Number(cp[1]) / 100 : 0,
						mate: mate ? Number(mate[1]) : null,
						depth,
						multipv
					});
				}
			} else if (line.startsWith('bestmove')) {
				const best = line.split(/\s+/)[1] ?? '';
				const moves = [...this.byMultipv.values()].sort((a, b) => a.multipv - b.multipv);
				if (this.watchdog) clearTimeout(this.watchdog);
				this.watchdog = null;
				const r = this.resolve;
				this.resolve = null;
				this.busy = false;
				r?.({ moves, bestmove: best });
			}
		}
	}

	// run one search with the given options set first; options are NOT reset
	// here — the caller sends the reset block before the next mover's options.
	// A watchdog respawns the engine and resolves empty if bestmove never
	// arrives, so a flaky engine can't hang a worker forever.
	search(fen: string, options: [string, string][], go: string): Promise<SearchOut> {
		this.busy = true;
		this.byMultipv = new Map();
		const opts = options.map(([k, v]) => `setoption name ${k} value ${v}`).join('\n');
		return new Promise((resolve) => {
			this.resolve = resolve;
			this.watchdog = setTimeout(() => {
				console.warn(`engine timeout on "${go}" — respawning`);
				const r = this.resolve;
				this.resolve = null;
				this.busy = false;
				try {
					this.proc.kill();
				} catch {
					// already gone
				}
				this.start();
				r?.({ moves: [], bestmove: '' });
			}, SEARCH_TIMEOUT_MS);
			this.proc.stdin.write(`${opts}\nposition fen ${fen}\n${go}\n`);
		});
	}

	newGame() {
		this.proc.stdin.write('ucinewgame\n');
	}

	quit() {
		this.proc.stdin.write('quit\n');
	}
}

// ---------- app-faithful bot move ----------
async function botMove(engine: Engine, fen: string, id: string): Promise<string | null> {
	const recipe = specToRecipe(parseSpec(id));
	// numeric ids carry the requested ELO (drives selectBotMove's mate-spotting
	// etc.); raw spec probes use a mid-range nominal
	const elo = Number(id) || 1000;
	// reset first: the OTHER bot's options (LimitStrength, Skill) must not leak
	const options = [...botResetOptions(1), ...recipe.options];
	const res = await engine.search(fen, options, recipe.go);
	if (recipe.sample) return selectBotMove(res.moves, elo, recipe.alpha);
	if (res.bestmove && res.bestmove !== '(none)') return res.bestmove;
	return res.moves[0]?.pv[0] ?? null;
}

// full-strength eval for adjudicating games the ply cap cuts off
async function adjudicate(engine: Engine, fen: string): Promise<number> {
	const res = await engine.search(fen, botResetOptions(1), 'go depth 12');
	const m = res.moves[0];
	if (!m) return 0;
	const cp = m.mate !== null ? (m.mate > 0 ? 9999 : -9999) : m.score * 100;
	return fen.split(' ')[1] === 'w' ? cp : -cp; // white POV
}

// the game's FENs oldest-first, for Maia's history planes
function fenHistory(chess: Chess): string[] {
	const ms = chess.history({ verbose: true });
	return ms.length === 0 ? [chess.fen()] : [ms[0].before, ...ms.map((m) => m.after)];
}

// one game; returns the score for `a` (1 / 0.5 / 0)
async function playGame(
	engine: Engine,
	a: string,
	b: string,
	opening: string,
	aIsWhite: boolean
): Promise<number> {
	engine.newGame();
	const chess = new Chess();
	for (const san of opening.split(' ')) chess.move(san);
	let plies = 0;
	while (!chess.isGameOver() && plies < MAX_PLIES) {
		const mover = (chess.turn() === 'w') === aIsWhite ? a : b;
		// Maia nets move from their own ONNX (Maia-1 with history, Maia-3 from the
		// current position + ELO dial); everyone else goes through Stockfish
		const uci = isMaia3Id(mover)
			? await maiaMove3Node(chess.fen(), maia3EloOf(mover))
			: isMaiaId(mover)
				? await maiaMoveNode(fenHistory(chess), maiaBandOf(mover))
				: await botMove(engine, chess.fen(), mover);
		if (!uci) break;
		try {
			chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
		} catch {
			break; // illegal engine move — treat as adjudication point
		}
		plies++;
	}
	let whiteScore: number;
	if (chess.isCheckmate()) {
		whiteScore = chess.turn() === 'w' ? 0 : 1;
	} else if (chess.isDraw() || chess.isStalemate()) {
		whiteScore = 0.5;
	} else {
		const cp = await adjudicate(engine, chess.fen());
		whiteScore = cp >= 300 ? 1 : cp <= -300 ? 0 : 0.5;
	}
	return aIsWhite ? whiteScore : 1 - whiteScore;
}

// ---------- Bradley–Terry fit (draws = half wins) ----------
interface PairResult {
	a: string;
	b: string;
	games: number;
	aScore: number; // wins + draws/2 from a's side
}

function fitRatings(results: PairResult[], points: string[]): Map<string, number> {
	const rating = new Map(points.map((p) => [p, 0]));
	// gradient ascent on the Elo-logistic log-likelihood
	for (let iter = 0; iter < 20000; iter++) {
		const lr = 40 * Math.exp(-iter / 4000);
		const grad = new Map(points.map((p) => [p, 0]));
		for (const r of results) {
			const sa = rating.get(r.a)!;
			const sb = rating.get(r.b)!;
			const expected = 1 / (1 + Math.pow(10, (sb - sa) / 400));
			const diff = r.aScore / r.games - expected;
			grad.set(r.a, grad.get(r.a)! + diff * r.games);
			grad.set(r.b, grad.get(r.b)! - diff * r.games);
		}
		for (const p of points) rating.set(p, rating.get(p)! + (lr * grad.get(p)!) / GAMES);
	}
	// anchor: the UCI_Elo band's mean fitted value = its mean nominal label
	// (probe runs without numeric >=1320 points anchor on the first id = 0,
	// which is fine — probe fits get merged with the ladder data separately)
	const anchors = points.filter((p) => Number(p) >= 1320);
	const ref = anchors.length ? anchors : [points[0]];
	const offset =
		ref.reduce((s, p) => s + (Number(p) || 0), 0) / ref.length -
		ref.reduce((s, p) => s + rating.get(p)!, 0) / ref.length;
	for (const p of points) rating.set(p, rating.get(p)! + offset);
	return rating;
}

// ---------- state / scheduling ----------
interface State {
	games: number;
	results: Record<string, { games: number; aScore: number }>;
}
const key = (a: string, b: string) => `${a}~${b}`;
let state: State = { games: GAMES, results: {} };
if (existsSync(STATE)) {
	const prev = JSON.parse(readFileSync(STATE, 'utf8')) as State;
	if (prev.games === GAMES) {
		state = prev;
		console.log(`resuming from ${STATE}`);
	} else {
		console.log(`--games changed (${prev.games} → ${GAMES}); starting over`);
	}
}
function saveState() {
	mkdirSync(path.dirname(STATE), { recursive: true });
	writeFileSync(STATE, JSON.stringify(state));
}

interface Job {
	a: string;
	b: string;
	gameIdx: number;
}
const jobs: Job[] = [];
for (const [a, b] of pairs) {
	const done = state.results[key(a, b)]?.games ?? 0;
	for (let g = done; g < GAMES; g++) jobs.push({ a, b, gameIdx: g });
}

const totalGames = pairs.length * GAMES;
const toPlay = jobs.length;
console.log(
	`${POINTS.length} settings, ${pairs.length} pairs × ${GAMES} games = ${totalGames} games ` +
		`(${totalGames - toPlay} done, ${toPlay} to play, ${WORKERS} workers)`
);

// ---------- run ----------
// download/warm any Maia nets in the run up front (one shared session per band)
const maiaBands = [...new Set(allIds.filter(isMaiaId).map(maiaBandOf))];
if (maiaBands.length) {
	console.log(`preloading Maia bands: ${maiaBands.join(', ')}`);
	await preloadMaiaBands(maiaBands);
}
if (allIds.some(isMaia3Id)) {
	console.log('preloading Maia-3 (one net, ELO-dialed)');
	await preloadMaia3();
}

const engines = Array.from({ length: WORKERS }, () => new Engine());
let played = 0;
const t0 = Date.now();

async function worker(engine: Engine) {
	for (;;) {
		const job = jobs.shift();
		if (!job) return;
		const opening = OPENINGS[Math.floor(job.gameIdx / 2) % OPENINGS.length];
		const aIsWhite = job.gameIdx % 2 === 0;
		const score = await playGame(engine, job.a, job.b, opening, aIsWhite);
		const k = key(job.a, job.b);
		const r = (state.results[k] ??= { games: 0, aScore: 0 });
		r.games++;
		r.aScore += score;
		saveState();
		played++;
		if (played % 10 === 0 || played === toPlay) {
			const rate = played / ((Date.now() - t0) / 60000);
			console.log(
				`${played}/${toPlay} games · ${rate.toFixed(1)}/min · ` +
					`eta ${((toPlay - played) / Math.max(rate, 0.1)).toFixed(0)}min`
			);
		}
	}
}

await Promise.all(engines.map((e) => worker(e)));
for (const e of engines) e.quit();

// ---------- report ----------
const results: PairResult[] = pairs
	.map(([a, b]) => ({ a, b, ...(state.results[key(a, b)] ?? { games: 0, aScore: 0 }) }))
	.filter((r) => r.games > 0);
const fitted = fitRatings(results, allIds);

console.log('\npairwise results (a vs b, a-score):');
for (const r of results) {
	const p = r.aScore / r.games;
	const se = Math.sqrt(Math.max(p * (1 - p), 0.01) / r.games);
	console.log(
		`  ${String(r.a).padStart(4)} vs ${String(r.b).padStart(4)}: ` +
			`${r.aScore}/${r.games} (${(p * 100).toFixed(0)}% ±${(se * 100).toFixed(0)})`
	);
}

console.log('\nfitted strength (anchored on the UCI_Elo band):');
console.log('  label  fitted  delta');
let prevFit = -Infinity;
for (const p of allIds) {
	const f = fitted.get(p)!;
	const nominal = Number(p);
	const mono = nominal && f < prevFit ? '  ⚠ NON-MONOTONIC' : '';
	console.log(
		`  ${String(p).padStart(18)}  ${f.toFixed(0).padStart(6)}  ` +
			`${nominal ? (f - nominal).toFixed(0).padStart(5) : '    —'}${mono}`
	);
	if (nominal) prevFit = f;
}

mkdirSync(path.dirname(OUT), { recursive: true });
writeFileSync(
	OUT,
	JSON.stringify(
		{
			ranAt: new Date().toISOString(),
			engine: ENGINE,
			gamesPerPair: GAMES,
			points: allIds,
			results,
			fitted: Object.fromEntries([...fitted.entries()].map(([p, f]) => [p, Math.round(f)]))
		},
		null,
		'\t'
	)
);
console.log(`\nwrote ${OUT}`);
