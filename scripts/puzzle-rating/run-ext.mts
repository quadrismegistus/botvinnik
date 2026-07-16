// Puzzle ratings for the NON-shaped roster: the other engine families run
// over the same stratified sample (see sample.mts / run.mts), so puzzle
// ratings are comparable across the whole roster. Reuses the gym's engine
// plumbing (gym-ext.json semantics): plain UCI engines answer with their
// move; dala answers by policy-sampling lc0's VerboseMoveStats, exactly as
// the gym and the app play it.
//
//   npx tsx scripts/puzzle-rating/run-ext.mts [--sample data/puzzles/sample.json]
//       [--out data/puzzle-rating-ext.json]
//
// All bots run in parallel (each is its own single-threaded process).

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
const OUT = resolve(ROOT, opt('out', 'data/puzzle-rating-ext.json'));

interface Puzzle {
	id: string;
	fen: string;
	moves: string[];
	rating: number;
	themes: string[];
}

interface BotSpec {
	name: string; // report name, with the persona's display rating
	cmd: string; // repo-relative command line (gym-ext.json style)
	options?: Record<string, string>;
	go: string;
	select?: 'policy'; // dala: sample lc0's P% distribution instead of bestmove
}

const BOTS: BotSpec[] = [
	{ name: 'horizon-550', cmd: 'node scripts/shims/jsce-uci.mjs', options: { Level: '1' }, go: 'go' },
	{ name: 'horizon-860', cmd: 'node scripts/shims/jsce-uci.mjs', options: { Level: '2' }, go: 'go' },
	{ name: 'bernstein-1200', cmd: 'scripts/engines/retro/bernstein --ply=2', go: 'go movetime 500' },
	{ name: 'sargon-1230', cmd: 'scripts/engines/retro/sargon --ply=1', go: 'go movetime 500' },
	{ name: 'turochamp-1300', cmd: 'scripts/engines/retro/turochamp --ply=1', go: 'go movetime 500' },
	{
		name: 'dala-911',
		cmd: 'scripts/engines/lc0-src/build/release/lc0 --weights=scripts/engines/dala/dala-700-00235000.pb.gz',
		options: { VerboseMoveStats: 'true' },
		go: 'go nodes 1',
		select: 'policy'
	},
	{
		name: 'dala-1095',
		cmd: 'scripts/engines/lc0-src/build/release/lc0 --weights=scripts/engines/dala/dala-900-00285000.pb.gz',
		options: { VerboseMoveStats: 'true' },
		go: 'go nodes 1',
		select: 'policy'
	},
	{
		name: 'dala-1315',
		cmd: 'scripts/engines/lc0-src/build/release/lc0 --weights=scripts/engines/dala/dala-1300-00300000.pb.gz',
		options: { VerboseMoveStats: 'true' },
		go: 'go nodes 1',
		select: 'policy'
	},
	{
		name: 'fish-2000',
		cmd: 'scripts/wasm-engine/run.sh',
		options: { 'UCI_LimitStrength': 'true', 'UCI_Elo': '2240' }, // display 2000 + SCALE_OFFSET
		go: 'go movetime 400'
	}
];

// minimal UCI client, gym-ext semantics
class Engine {
	private proc: ChildProcessWithoutNullStreams;
	private buffer = '';
	private policy: { uci: string; p: number }[] = [];
	private waiting: { until: (l: string) => string | null; res: (v: string) => void } | null = null;

	constructor(spec: BotSpec) {
		const [bin, ...args] = spec.cmd.split(' ');
		this.proc = spawn(bin, args, { cwd: ROOT });
		this.proc.stdout.on('data', (d) => this.onData(String(d)));
		this.proc.on('error', (e) => {
			throw new Error(`${spec.name}: ${e.message}`);
		});
	}
	send(cmd: string) {
		this.proc.stdin.write(cmd + '\n');
	}
	private onData(chunk: string) {
		this.buffer += chunk;
		const lines = this.buffer.split('\n');
		this.buffer = lines.pop() ?? '';
		for (const line of lines) {
			const m = line.match(/^info string ([a-h][1-8][a-h][1-8][qrbn]?)\s.*\(P: *([\d.]+)%\)/);
			if (m) this.policy.push({ uci: m[1], p: Number(m[2]) });
			if (this.waiting) {
				const v = this.waiting.until(line);
				if (v !== null) {
					const res = this.waiting.res;
					this.waiting = null;
					res(v);
				}
			}
		}
	}
	waitFor(until: (l: string) => string | null, timeoutMs = 30_000): Promise<string> {
		return new Promise((res, rej) => {
			const t = setTimeout(() => rej(new Error('uci timeout')), timeoutMs);
			this.waiting = {
				until,
				res: (v) => {
					clearTimeout(t);
					res(v);
				}
			};
		});
	}
	async init(spec: BotSpec) {
		this.send('uci');
		await this.waitFor((l) => (l.startsWith('uciok') ? '' : null));
		for (const [k, v] of Object.entries(spec.options ?? {}))
			this.send(`setoption name ${k} value ${v}`);
		this.send('isready');
		await this.waitFor((l) => (l.startsWith('readyok') ? '' : null));
	}
	async move(fen: string, spec: BotSpec): Promise<string | null> {
		this.policy = [];
		this.send(`position fen ${fen}`);
		this.send(spec.go);
		const best = await this.waitFor((l) =>
			l.startsWith('bestmove') ? (l.split(/\s+/)[1] ?? '') : null
		);
		if (spec.select === 'policy' && this.policy.length > 0) {
			// weighted-random over the net's move priors — the persona's actual play
			const total = this.policy.reduce((a, m) => a + m.p, 0);
			let r = Math.random() * total;
			for (const m of this.policy) {
				r -= m.p;
				if (r <= 0) return m.uci;
			}
		}
		return best && best !== '(none)' && best !== '0000' ? best : null;
	}
	quit() {
		try {
			this.send('quit');
			this.proc.kill();
		} catch {
			/* gone */
		}
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

async function solve(engine: Engine, spec: BotSpec, p: Puzzle): Promise<boolean> {
	const c = new Chess(p.fen);
	const apply = (uci: string) =>
		c.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
	apply(p.moves[0]);
	for (let i = 1; i < p.moves.length; i += 2) {
		const expected = p.moves[i];
		const picked = await engine.move(c.fen(), spec);
		if (!picked) return false;
		if (picked !== expected) {
			if (!(isMate(c.fen(), expected) && isMate(c.fen(), picked))) return false;
			return true; // alternative mate
		}
		apply(expected);
		if (i + 1 < p.moves.length) apply(p.moves[i + 1]);
	}
	return true;
}

function fit(results: { rating: number; solved: boolean }[]): { elo: number; se: number } {
	const ll = (theta: number) =>
		results.reduce((a, r) => {
			const e = 1 / (1 + 10 ** ((r.rating - theta) / 400));
			return a + Math.log(r.solved ? e : 1 - e);
		}, 0);
	let best = 400;
	let bestLl = -Infinity;
	for (let t = 400; t <= 3000; t++) {
		const v = ll(t);
		if (v > bestLl) {
			bestLl = v;
			best = t;
		}
	}
	const h = (ll(best + 25) - 2 * bestLl + ll(best - 25)) / 625;
	return { elo: best, se: h < 0 ? Math.round(1 / Math.sqrt(-h)) : Infinity };
}

const puzzles: Puzzle[] = JSON.parse(readFileSync(SAMPLE, 'utf8'));
console.log(`${puzzles.length} puzzles · ${BOTS.length} bots in parallel`);

async function runBot(spec: BotSpec) {
	const engine = new Engine(spec);
	try {
		await engine.init(spec);
		const results: { rating: number; solved: boolean; themes: string[] }[] = [];
		const t0 = Date.now();
		for (const [i, p] of puzzles.entries()) {
			let solved = false;
			try {
				solved = await solve(engine, spec, p);
			} catch {
				solved = false; // engine hiccup on this puzzle counts as a fail
			}
			results.push({ rating: p.rating, solved, themes: p.themes });
			if ((i + 1) % 500 === 0)
				console.log(
					`  ${spec.name}: ${i + 1}/${puzzles.length} · ${((Date.now() - t0) / 60000).toFixed(1)}m`
				);
		}
		const f = fit(results);
		const bands: Record<string, string> = {};
		for (let lo = 400; lo < 2800; lo += 400) {
			const in_ = results.filter((r) => r.rating >= lo && r.rating < lo + 400);
			if (in_.length >= 20)
				bands[`${lo}-${lo + 400}`] =
					`${((100 * in_.filter((r) => r.solved).length) / in_.length).toFixed(0)}%`;
		}
		const themeStats: Record<string, string> = {};
		const counts = new Map<string, { n: number; s: number }>();
		for (const r of results)
			for (const t of r.themes) {
				const c = counts.get(t) ?? { n: 0, s: 0 };
				c.n++;
				if (r.solved) c.s++;
				counts.set(t, c);
			}
		for (const [t, c] of [...counts].sort((a, b) => b[1].n - a[1].n).slice(0, 12))
			themeStats[t] = `${((100 * c.s) / c.n).toFixed(0)}% (n=${c.n})`;
		console.log(
			`${spec.name} → puzzle rating ${f.elo} ± ${f.se} (${results.filter((r) => r.solved).length}/${results.length})`
		);
		return {
			name: spec.name,
			puzzleRating: f.elo,
			se: f.se,
			solved: results.filter((r) => r.solved).length,
			n: results.length,
			bands,
			themes: themeStats
		};
	} finally {
		engine.quit();
	}
}

const settled = await Promise.allSettled(BOTS.map(runBot));
const out = settled
	.map((s, i) =>
		s.status === 'fulfilled' ? s.value : { name: BOTS[i].name, error: String(s.reason) }
	)
	.filter(Boolean);
for (const s of settled)
	if (s.status === 'rejected') console.error('bot failed:', s.reason);

writeFileSync(OUT, JSON.stringify({ date: new Date().toISOString(), results: out }, null, '\t') + '\n');
console.log(`\nwritten to ${OUT}`);
