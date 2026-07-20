// Scan-model multiplier sweep against the two ends of the puzzle bench.
//
// The amplitude problem: v4.0 multipliers give display-900 87% on easy
// puzzles (humans ~99%) and 16% on 2400+ (humans ~2%). This sweeps the
// multiplier grid to find the profile that reaches the human envelope.
//
// SPEED: the searched positions along a puzzle's solution line are fixed
// (the bot's choice only decides pass/fail), so the engine runs ONCE per
// solver ply and every config re-evaluates the cached MultiPV lines in pure
// JS. A 32-config sweep costs one bench pass plus milliseconds.
//
//   npx tsx scripts/puzzle-rating/sweep.mts [--display 900]

import { readFileSync, writeFileSync } from 'node:fs';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';
import { shapedBotMove, shapedLabelFor, shapedSearchDepth, type ScanMults } from '../../brain/bot';
import { SCALE_OFFSET } from '../../brain/bots';
import type { EngineMove } from '../../brain/engine/types';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DISPLAY = Number(opt('display', '900'));
const LABEL = shapedLabelFor(DISPLAY + SCALE_OFFSET, 'wasm');
const DEPTH = shapedSearchDepth(LABEL);

interface Puzzle {
	id: string;
	fen: string;
	moves: string[];
	rating: number;
	themes: string[];
}

// ---- engine with per-depth leader tracking (as run.mts) ----
class Backend {
	private proc: ChildProcessWithoutNullStreams;
	private buffer = '';
	private byMultipv = new Map<number, EngineMove>();
	private leaderAtDepth = new Map<number, string>();
	private resolveSearch: ((moves: EngineMove[]) => void) | null = null;
	lastDiscoveryDepth: number | undefined;

	constructor() {
		this.proc = spawn(resolve(ROOT, 'scripts/wasm-engine/run.sh'));
		this.proc.stdout.on('data', (d) => this.onData(String(d)));
		this.send('uci');
		this.send('setoption name Threads value 1');
		this.send('setoption name MultiPV value 12');
	}
	send(cmd: string) {
		this.proc.stdin.write(cmd + '\n');
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
					if (multipv === 1) this.leaderAtDepth.set(depth, pv[0]);
				}
			} else if (line.startsWith('bestmove')) {
				const moves = [...this.byMultipv.values()].sort((a, b) => a.multipv - b.multipv);
				const final = moves[0]?.pv[0];
				let d: number | undefined;
				if (final) {
					for (const depth of [...this.leaderAtDepth.keys()].sort((a, b) => a - b)) {
						if (this.leaderAtDepth.get(depth) === final) d = d ?? depth;
						else d = undefined;
					}
				}
				this.lastDiscoveryDepth = d;
				this.resolveSearch?.(moves);
				this.resolveSearch = null;
			}
		}
	}
	search(fen: string): Promise<EngineMove[]> {
		this.byMultipv = new Map();
		this.leaderAtDepth = new Map();
		return new Promise((res) => {
			this.resolveSearch = res;
			this.send(`position fen ${fen}`);
			this.send(`go depth ${DEPTH}`);
		});
	}
	quit() {
		this.send('quit');
	}
}

function isMate(fen: string, uci: string): boolean {
	try {
		const c = new Chess(fen);
		c.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
		return c.isCheckmate();
	} catch {
		return false;
	}
}

// ---- phase 1: cache the searches along each solution line ----
interface CachedPly {
	fen: string;
	expected: string;
	lines: EngineMove[];
	d: number | undefined;
	expectedMates: boolean;
}
interface CachedPuzzle {
	id: string;
	rating: number;
	plies: CachedPly[];
}

const all: Puzzle[] = JSON.parse(
	readFileSync(resolve(ROOT, 'data/puzzles/sample.json'), 'utf8')
);
const puzzles = all.filter((p) => p.rating < 800 || p.rating >= 2000);
const nEasy = puzzles.filter((p) => p.rating < 800).length;
console.log(
	`display ${DISPLAY} (label ${LABEL}, depth ${DEPTH}) · ${puzzles.length} puzzles ` +
		`(${nEasy} easy <800, ${puzzles.length - nEasy} hard ≥2000)`
);

const backend = new Backend();
const cached: CachedPuzzle[] = [];
const t0 = Date.now();
for (const [i, p] of puzzles.entries()) {
	const c = new Chess(p.fen);
	const apply = (uci: string) =>
		c.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
	apply(p.moves[0]);
	const plies: CachedPly[] = [];
	for (let k = 1; k < p.moves.length; k += 2) {
		const fen = c.fen();
		const lines = await backend.search(fen);
		plies.push({
			fen,
			expected: p.moves[k],
			lines,
			d: backend.lastDiscoveryDepth,
			expectedMates: isMate(fen, p.moves[k])
		});
		apply(p.moves[k]);
		if (k + 1 < p.moves.length) apply(p.moves[k + 1]);
	}
	cached.push({ id: p.id, rating: p.rating, plies });
	if ((i + 1) % 200 === 0)
		console.log(`  cached ${i + 1}/${puzzles.length} · ${((Date.now() - t0) / 1000).toFixed(0)}s`);
}
backend.quit();
console.log(`search cache built in ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);

// ---- phase 2: the grid, evaluated on the cache ----
function solveCached(p: CachedPuzzle, mults: Partial<ScanMults> | undefined): boolean {
	for (const ply of p.plies) {
		const picked = shapedBotMove(
			ply.lines,
			LABEL,
			mults === undefined ? undefined : { scan: true, scanMults: mults },
			`${p.id}:${LABEL}`,
			ply.fen,
			mults === undefined ? undefined : ply.d
		);
		if (!picked) return false;
		if (picked !== ply.expected) {
			return ply.expectedMates && isMate(ply.fen, picked); // alternative mate
		}
	}
	return true;
}

function evalConfig(mults: Partial<ScanMults> | undefined): { easy: number; hard: number } {
	let eS = 0,
		eN = 0,
		hS = 0,
		hN = 0;
	for (const p of cached) {
		const solved = solveCached(p, mults);
		if (p.rating < 800) {
			eN++;
			if (solved) eS++;
		} else {
			hN++;
			if (solved) hS++;
		}
	}
	return { easy: (100 * eS) / eN, hard: (100 * hS) / hN };
}

// visScale scales the whole visible group; quiet and pCap sweep independently
const rows: { name: string; easy: number; hard: number; loss: number }[] = [];
const TARGET = { easy: 99, hard: 3 };
function record(name: string, r: { easy: number; hard: number }) {
	const loss = Math.abs(r.easy - TARGET.easy) + Math.abs(r.hard - TARGET.hard);
	rows.push({ name, ...r, loss });
}

record('v3 (no scan)', evalConfig(undefined));
record('v4.0 defaults', evalConfig({}));
for (const s of [1.0, 0.6, 0.35, 0.2, 0.12]) {
	for (const quiet of [1.6, 2.2, 2.8, 3.4]) {
		for (const pCap of [0.92, 0.97]) {
			for (const qs of [0.6, 0.35, 0.2]) {
				record(
					`vis×${s} quiet=${quiet} pCap=${pCap} qs=${qs}`,
					evalConfig({
						mateSoon: 0.2 * s,
						grab: 0.15 * s,
						capture: 0.4 * s,
						check: 0.5 * s,
						quiet,
						quietShallow: quiet * qs,
						deepBase: 0.6 + (quiet - 1.6) * 0.3,
						deepSlope: 0.5,
						deepCap: Math.max(2.5, quiet),
						pCap
					})
				);
			}
		}
	}
}

rows.sort((a, b) => a.loss - b.loss);
console.log(`target: easy ${TARGET.easy}% · hard ${TARGET.hard}%  (display ${DISPLAY})\n`);
for (const r of rows.slice(0, 12))
	console.log(
		`${r.name.padEnd(30)} easy ${r.easy.toFixed(1)}% · hard ${r.hard.toFixed(1)}% · loss ${r.loss.toFixed(1)}`
	);
console.log('  …');
for (const r of rows.slice(-3))
	console.log(
		`${r.name.padEnd(30)} easy ${r.easy.toFixed(1)}% · hard ${r.hard.toFixed(1)}% · loss ${r.loss.toFixed(1)}`
	);

writeFileSync(
	resolve(ROOT, 'data/puzzle-sweep.json'),
	JSON.stringify({ date: new Date().toISOString(), display: DISPLAY, rows }, null, '\t') + '\n'
);
