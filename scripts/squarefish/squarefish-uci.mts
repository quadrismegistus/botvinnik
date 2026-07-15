// SquareFish: the shaped bot ("Squares") as a standalone UCI engine, so it
// can play on lichess under the standard lichess-bot bridge — and earn a REAL
// human-pool rating, the definitive anchor for our scale's low end.
//
//   npx tsx scripts/squarefish/squarefish-uci.mts --label 1050
//
// The engine underneath is the app's own WASM lite-single Stockfish
// (scripts/wasm-engine/run.sh — byte-identical to what the website runs), so
// the lichess bot IS the calibrated configuration: a MultiPV-12 search at the
// label's calibrated depth, with shapedBotMove's miss-the-tactic choice layer
// and a per-game sticky-miss seed (re-rolled on ucinewgame).
//
// UCI subset: uci / isready / setoption name Label value N / ucinewgame /
// position (fen|startpos) [moves ...] / go ... (clock params ignored — the
// label fixes the effort; moves take <1s) / quit. See README.md for lichess
// deployment.

import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createInterface } from 'node:readline';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';
import { shapedBotMove, shapedSearchDepth } from '../../src/lib/bot';
import { avoidRepetition } from '../../src/lib/repetition';
import type { EngineMove } from '../../src/lib/engine/stockfish';

const argv = process.argv.slice(2);
function opt(name: string, dflt: number): number {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 ? Number(argv[i + 1]) : dflt;
}
let label = opt('label', 1050);

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const ENGINE = resolve(ROOT, 'scripts/wasm-engine/run.sh');

// ---- the backing Stockfish (MultiPV lines in, one shaped move out) ----
class Backend {
	private proc: ChildProcessWithoutNullStreams;
	private buffer = '';
	private byMultipv = new Map<number, EngineMove>();
	private resolveSearch: ((moves: EngineMove[]) => void) | null = null;

	constructor() {
		this.proc = spawn(ENGINE);
		this.proc.on('error', (e) => {
			process.stderr.write(`cannot start ${ENGINE}: ${e.message}\n`);
			process.exit(1);
		});
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
				}
			} else if (line.startsWith('bestmove')) {
				const moves = [...this.byMultipv.values()].sort((a, b) => a.multipv - b.multipv);
				this.resolveSearch?.(moves);
				this.resolveSearch = null;
			}
		}
	}

	search(fen: string, depth: number): Promise<EngineMove[]> {
		this.byMultipv = new Map();
		return new Promise((res) => {
			// Watchdog: a wedged backend must kill the whole process — dying
			// loudly lets lichess-bot/systemd restart cleanly, where hanging
			// mutely flags games while looking alive. Depth-12 MultiPV-12 takes
			// ~1-3s; 30s is pathology, not patience.
			const watchdog = setTimeout(() => {
				process.stderr.write('backend search timeout — exiting for a clean restart\n');
				process.exit(1);
			}, 30_000);
			this.resolveSearch = (moves) => {
				clearTimeout(watchdog);
				res(moves);
			};
			this.send(`position fen ${fen}`);
			this.send(`go depth ${depth}`);
		});
	}

	quit() {
		this.send('quit');
	}
}

// ---- the UCI face ----
const backend = new Backend();
const chess = new Chess();
let gameSeed = `sf${Math.floor(Math.random() * 1e9)}`;

function out(line: string) {
	process.stdout.write(line + '\n');
}

function setPosition(args: string[]) {
	const movesIdx = args.indexOf('moves');
	const movesList = movesIdx >= 0 ? args.slice(movesIdx + 1) : [];
	if (args[0] === 'startpos') chess.reset();
	else if (args[0] === 'fen')
		chess.load((movesIdx >= 0 ? args.slice(1, movesIdx) : args.slice(1)).join(' '));
	for (const uci of movesList) {
		chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
	}
}

// every position reached this game, oldest first, current last — the shape
// avoidRepetition expects. The bridge always sends the full move list, so the
// history is complete.
function fenHistory(): string[] {
	const h = chess.history({ verbose: true });
	return h.length === 0 ? [chess.fen()] : [h[0].before, ...h.map((m) => m.after)];
}

async function go() {
	const moves = await backend.search(chess.fen(), shapedSearchDepth(label));
	const move = shapedBotMove(moves, label, undefined, gameSeed);
	// same guard the app applies: the shaped layer can't see game history, so
	// a winning SquareFish could shuffle into threefold — bot opponents would
	// farm that draw relentlessly
	const safe = move ? avoidRepetition(move, fenHistory(), moves) : null;
	out(`bestmove ${safe ?? moves[0]?.pv[0] ?? '(none)'}`);
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (line) => {
	const parts = line.trim().split(/\s+/);
	const cmd = parts[0];
	try {
		if (cmd === 'uci') {
			out(`id name SquareFish ${label}`);
			out('id author botvinnik-web (shaped bot over Stockfish lite-single)');
			out('option name Label type spin default 1050 min 600 max 1500');
			// declared so bridges (python-chess validates before sending) can set
			// them; accepted and ignored — the label fixes the effort, the backend
			// runs one thread, and moves take <1s regardless of clock
			out('option name Move Overhead type spin default 100 min 0 max 10000');
			out('option name Threads type spin default 1 min 1 max 128');
			out('option name Hash type spin default 32 min 1 max 65536');
			out('uciok');
		} else if (cmd === 'isready') {
			out('readyok');
		} else if (cmd === 'setoption') {
			const name = parts[parts.indexOf('name') + 1]?.toLowerCase();
			const value = Number(parts[parts.indexOf('value') + 1]);
			if (name === 'label' && value >= 600 && value <= 1500) label = value;
		} else if (cmd === 'ucinewgame') {
			chess.reset();
			gameSeed = `sf${Math.floor(Math.random() * 1e9)}`; // fresh eyes per game
			backend.send('ucinewgame');
		} else if (cmd === 'position') {
			setPosition(parts.slice(1));
		} else if (cmd === 'go') {
			void go();
		} else if (cmd === 'quit') {
			backend.quit();
			process.exit(0);
		}
	} catch (e) {
		out(`info string squarefish error: ${(e as Error).message}`);
		out('bestmove 0000');
	}
});
