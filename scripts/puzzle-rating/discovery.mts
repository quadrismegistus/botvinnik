// Discovery depth vs human difficulty: is "only deep search prefers it" a
// valid proxy for "hard for a human to see"?
//
// For each sample puzzle, search the solver's position to depth 12 and record
// the FIRST depth at which the engine's top move equals the puzzle's solution
// (iterative deepening streams a preferred move per depth — normally thrown
// away). Correlate that discovery depth with the puzzle's human-measured
// rating. A real correlation certifies discovery depth as the v4 visibility
// signal, replacing the hand-built scan categories (Guid–Bratko-style
// complexity, validated in-house).
//
//   npx tsx scripts/puzzle-rating/discovery.mts [--sample data/puzzles/sample.json]

import { readFileSync, writeFileSync } from 'node:fs';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SAMPLE = resolve(ROOT, opt('sample', 'data/puzzles/sample.json'));
const OUT = resolve(ROOT, opt('out', 'data/puzzle-discovery.json'));
const MAX_DEPTH = 12;

interface Puzzle {
	id: string;
	fen: string;
	moves: string[];
	rating: number;
	themes: string[];
}

// single-PV engine that reports the top move at every iterative depth
class DepthTracker {
	private proc: ChildProcessWithoutNullStreams;
	private buffer = '';
	private perDepth = new Map<number, string>();
	private resolveSearch: ((v: Map<number, string>) => void) | null = null;

	constructor() {
		this.proc = spawn(resolve(ROOT, 'scripts/wasm-engine/run.sh'));
		this.proc.stdout.on('data', (d) => this.onData(String(d)));
		this.send('uci');
		this.send('setoption name Threads value 1');
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
				const mv = line.split(' pv ')[1]?.trim().split(' ')[0];
				if (depth > 0 && mv) this.perDepth.set(depth, mv);
			} else if (line.startsWith('bestmove')) {
				this.resolveSearch?.(this.perDepth);
				this.resolveSearch = null;
			}
		}
	}
	search(fen: string): Promise<Map<number, string>> {
		this.perDepth = new Map();
		return new Promise((res) => {
			this.resolveSearch = res;
			this.send(`position fen ${fen}`);
			this.send(`go depth ${MAX_DEPTH}`);
		});
	}
	quit() {
		this.send('quit');
	}
}

const puzzles: Puzzle[] = JSON.parse(readFileSync(SAMPLE, 'utf8'));
const engine = new DepthTracker();
const rows: { rating: number; d: number; themes: string[] }[] = [];
let engineDisagrees = 0;
const t0 = Date.now();

for (const [i, p] of puzzles.entries()) {
	const c = new Chess(p.fen);
	const mv0 = p.moves[0];
	c.move({ from: mv0.slice(0, 2), to: mv0.slice(2, 4), promotion: mv0[4] });
	const solution = p.moves[1];
	const perDepth = await engine.search(c.fen());
	// discovery depth: first depth from which the solution LEADS AND KEEPS
	// leading — a flicker at depth 2 that's abandoned isn't "seen at 2"
	let d: number | null = null;
	for (let depth = 1; depth <= MAX_DEPTH; depth++) {
		const at = perDepth.get(depth);
		if (at === undefined) continue; // depth skipped in output — inherit current run
		if (at === solution) {
			if (d === null) d = depth;
		} else d = null;
	}
	if (d === null) engineDisagrees++;
	else rows.push({ rating: p.rating, d, themes: p.themes });
	if ((i + 1) % 300 === 0)
		console.log(`${i + 1}/${puzzles.length} · ${((Date.now() - t0) / 1000).toFixed(0)}s`);
}
engine.quit();

// Pearson + Spearman-ish (rank via sort) correlation
function pearson(xs: number[], ys: number[]): number {
	const n = xs.length;
	const mx = xs.reduce((a, b) => a + b, 0) / n;
	const my = ys.reduce((a, b) => a + b, 0) / n;
	let sxy = 0,
		sxx = 0,
		syy = 0;
	for (let i = 0; i < n; i++) {
		sxy += (xs[i] - mx) * (ys[i] - my);
		sxx += (xs[i] - mx) ** 2;
		syy += (ys[i] - my) ** 2;
	}
	return sxy / Math.sqrt(sxx * syy);
}
function ranks(xs: number[]): number[] {
	const idx = xs.map((v, i) => [v, i] as const).sort((a, b) => a[0] - b[0]);
	const r = new Array(xs.length);
	idx.forEach(([, i], rank) => (r[i] = rank));
	return r;
}

const rs = rows.map((r) => r.rating);
const ds = rows.map((r) => r.d);
const rP = pearson(rs, ds);
const rS = pearson(ranks(rs), ranks(ds));

console.log(`\n${rows.length} puzzles where the engine agrees with the solution ` +
	`(${engineDisagrees} disagreements skipped)`);
console.log(`discovery depth vs puzzle rating: Pearson r = ${rP.toFixed(3)}, Spearman ρ = ${rS.toFixed(3)}`);

// mean discovery depth per rating band, and solve-relevant view: rating per depth
console.log('\nmean discovery depth by puzzle-rating band:');
for (let lo = 400; lo < 2800; lo += 400) {
	const in_ = rows.filter((r) => r.rating >= lo && r.rating < lo + 400);
	if (in_.length < 20) continue;
	const mean = in_.reduce((a, r) => a + r.d, 0) / in_.length;
	console.log(`  ${lo}-${lo + 400}: d* = ${mean.toFixed(2)} (n=${in_.length})`);
}
console.log('\nmean puzzle rating by discovery depth:');
for (let d = 1; d <= MAX_DEPTH; d++) {
	const in_ = rows.filter((r) => r.d === d);
	if (in_.length < 15) continue;
	const mean = in_.reduce((a, r) => a + r.rating, 0) / in_.length;
	console.log(`  d*=${d}: rating ${mean.toFixed(0)} (n=${in_.length})`);
}

writeFileSync(
	OUT,
	JSON.stringify({ date: new Date().toISOString(), pearson: rP, spearman: rS, rows }, null, '\t') + '\n'
);
console.log(`\nwritten to ${OUT}`);
