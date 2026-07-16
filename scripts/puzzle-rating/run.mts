// The shaped bots' PUZZLE rating: run the miss-the-tactic choice layer over
// rated lichess puzzles and fit the rating at which it solves 50%.
//
// Why: the whole weakness model is "misses ~X% of tactical moments", and
// puzzles are distilled tactical moments with independently calibrated
// ratings (Glicko over millions of real solver attempts). A display-900
// Square posting a puzzle rating far from a human 900's typical puzzle
// rating falsifies the miss model in a specific direction — and the theme
// tags let us ask WHICH motifs it misses like whom.
//
//   npx tsx scripts/puzzle-rating/run.mts --sample data/puzzles/sample.json \
//       [--displays 600,900,1200,1500] [--out data/puzzle-rating.json]
//
// Build the sample first with sample.mts. Puzzle semantics (lichess dump):
// FEN is the position BEFORE the opponent's setup move; Moves[0] is that
// setup move, then solver/opponent moves alternate. Solved = every solver
// move matches, except any checkmating move is accepted where the expected
// move also mates (lichess's own rule).

import { readFileSync, writeFileSync } from 'node:fs';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';
import { shapedBotMove, shapedLabelFor, shapedSearchDepth } from '../../src/lib/bot';
import { SCALE_OFFSET } from '../../src/lib/bots';
import type { EngineMove } from '../../src/lib/engine/stockfish';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const SAMPLE = resolve(ROOT, opt('sample', 'data/puzzles/sample.json'));
const OUT = resolve(ROOT, opt('out', 'data/puzzle-rating.json'));
const DISPLAYS = opt('displays', '600,900,1200,1500').split(',').map(Number);
// --scan: the v4 visibility-weighted miss model (see bot.ts tacticVisibility)
const SCAN = argv.includes('--scan');

interface Puzzle {
	id: string;
	fen: string;
	moves: string[]; // uci, moves[0] = opponent setup
	rating: number;
	themes: string[];
}

// ---- engine (the squarefish-uci Backend, depth set per search) ----
class Backend {
	private proc: ChildProcessWithoutNullStreams;
	private buffer = '';
	private byMultipv = new Map<number, EngineMove>();
	private leaderAtDepth = new Map<number, string>(); // multipv-1 move per depth
	private resolveSearch: ((moves: EngineMove[]) => void) | null = null;
	/** discovery depth of the last search's best move (sustained leadership) */
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
				// discovery depth: first depth from which the final best move led
				// and KEPT leading through the end of the search
				const final = moves[0]?.pv[0];
				let d: number | undefined;
				if (final) {
					const depths = [...this.leaderAtDepth.keys()].sort((a, b) => a - b);
					for (const depth of depths) {
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
	search(fen: string, depth: number): Promise<EngineMove[]> {
		this.byMultipv = new Map();
		this.leaderAtDepth = new Map();
		return new Promise((res) => {
			this.resolveSearch = res;
			this.send(`position fen ${fen}`);
			this.send(`go depth ${depth}`);
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

// solve one puzzle at one label; sticky-miss seed per (puzzle, label)
async function solve(backend: Backend, p: Puzzle, label: number): Promise<boolean> {
	const c = new Chess(p.fen);
	const apply = (uci: string) =>
		c.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
	apply(p.moves[0]); // opponent's setup move
	let lastMoveTo = p.moves[0].slice(2, 4);
	for (let i = 1; i < p.moves.length; i += 2) {
		const expected = p.moves[i];
		const lines = await backend.search(c.fen(), shapedSearchDepth(label));
		const picked = shapedBotMove(
			lines,
			label,
			SCAN ? { scan: true } : undefined,
			`${p.id}:${label}`,
			c.fen(),
			SCAN ? backend.lastDiscoveryDepth : undefined,
			SCAN ? lastMoveTo : undefined
		);
		if (!picked) return false;
		if (picked !== expected) {
			// lichess rule: an alternative move is correct if it also mates
			if (!(isMate(c.fen(), expected) && isMate(c.fen(), picked))) return false;
			// alternative mate ends the puzzle successfully
			return true;
		}
		apply(expected);
		if (i + 1 < p.moves.length) {
			apply(p.moves[i + 1]); // opponent's reply
			lastMoveTo = p.moves[i + 1].slice(2, 4);
		}
	}
	return true;
}

// MLE puzzle rating: solve prob = logistic(theta - puzzleRating)
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
console.log(`${puzzles.length} puzzles · displays ${DISPLAYS.join('/')}`);

const out: Record<string, unknown>[] = [];
for (const display of DISPLAYS) {
	const label = shapedLabelFor(display + SCALE_OFFSET, 'wasm');
	const backend = new Backend();
	const results: { rating: number; solved: boolean; themes: string[] }[] = [];
	const t0 = Date.now();
	for (const [i, p] of puzzles.entries()) {
		const solved = await solve(backend, p, label);
		results.push({ rating: p.rating, solved, themes: p.themes });
		if ((i + 1) % 250 === 0)
			console.log(
				`  display ${display} (label ${label}): ${i + 1}/${puzzles.length} · ` +
					`${results.filter((r) => r.solved).length} solved · ${((Date.now() - t0) / 1000).toFixed(0)}s`
			);
	}
	backend.quit();
	const f = fit(results);
	// per-500-band solve rates, for the curve shape
	const bands: Record<string, string> = {};
	for (let lo = 400; lo < 2800; lo += 400) {
		const in_ = results.filter((r) => r.rating >= lo && r.rating < lo + 400);
		if (in_.length >= 20)
			bands[`${lo}-${lo + 400}`] =
				`${((100 * in_.filter((r) => r.solved).length) / in_.length).toFixed(0)}% (n=${in_.length})`;
	}
	// per-theme solve rates over common themes
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
	const row = {
		display,
		label,
		puzzleRating: f.elo,
		se: f.se,
		solved: results.filter((r) => r.solved).length,
		n: results.length,
		bands,
		themes: themeStats
	};
	out.push(row);
	console.log(
		`display ${display} → puzzle rating ${f.elo} ± ${f.se} ` +
			`(${row.solved}/${row.n} solved)`
	);
}

writeFileSync(OUT, JSON.stringify({ date: new Date().toISOString(), results: out }, null, '\t') + '\n');
console.log(`\nwritten to ${OUT}`);
