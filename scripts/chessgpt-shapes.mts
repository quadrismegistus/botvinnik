// Do models that learned chess from different teachers make different-SHAPED
// mistakes at the same strength?
//
// The gym answers the strength half, and the answer moved: on clean data the
// three land at 1225 / 1244 / 1303 — a 78-point spread, not the 21 first
// reported, which was measured over games half of which the model never
// played. So strength is NOT fully controlled for, and the label differences
// below should be read alongside it rather than as the teacher alone.
//
// Deliberately not run through calibrate-bots: that harness spawns an engine
// per game and respawns on a missed deadline, and a respawn mid-game costs a
// move that then looks like a blunder the model made — a fake data point in
// exactly the distribution being measured. Here each player is one long-lived
// process for the whole run.
//
//   npx tsx scripts/chessgpt-shapes.mts --games 12 --out data/chessgpt-shapes.json
//
// Grading is the app's own pipeline (gradeMove → backfillGrade), so the labels
// mean what they mean everywhere else in the app.

import { spawn, type ChildProcessByStdio } from 'node:child_process';
import type { Readable, Writable } from 'node:stream';
import { writeFileSync } from 'node:fs';
import { Chess } from 'chess.js';
import { gradeMove, backfillGrade } from '../brain/engine/insights';
import { shapedBotMove } from '../brain/bot';
import type { EngineMove } from '../brain/engine/types';

const args = process.argv.slice(2);
const opt = (n: string, d: string) => {
	const i = args.indexOf(`--${n}`);
	return i >= 0 ? args[i + 1] : d;
};
const GAMES = Number(opt('games', '12'));
const OUT = opt('out', 'data/chessgpt-shapes.json');
const DEPTH = Number(opt('depth', '12'));
const MULTIPV = 8;
// One variant per process: three of these run concurrently, each with its own
// pair of engines. Separating them is what makes a long run finish in hours
// rather than most of a day, and they share nothing, so it is safe.
const ONLY = opt('variant', '');
const MAX_PLIES = 160;

const OPENINGS = [
	'e4 e5 Nf3 Nc6', 'd4 d5 c4 e6', 'e4 c5 Nf3 d6', 'd4 Nf6 c4 e6',
	'e4 e6 d4 d5', 'c4 e5 Nc3 Nf6', 'd4 d5 Nf3 Nf6', 'e4 c5 Nf3 Nc6',
	'e4 e5 Nf3 Nf6', 'd4 Nf6 c4 g6', 'Nf3 d5 g3 Nf6', 'e4 c6 d4 d5'
];

/** A line-buffered UCI process. */
class Uci {
	// stderr is `ignore`, so this is NOT ChildProcessWithoutNullStreams — that
	// type promises a Readable stderr and tsc rejects the assignment.
	private proc: ChildProcessByStdio<Writable, Readable, null>;
	private buf = '';
	private waiters: { pred: (l: string) => boolean; res: (l: string) => void }[] = [];
	lines: EngineMove[] = [];

	constructor(cmd: string, private readonly args: string[] = []) {
		this.proc = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'ignore'] });
		this.proc.stdout.on('data', (d) => {
			this.buf += d.toString();
			let nl: number;
			while ((nl = this.buf.indexOf('\n')) >= 0) {
				const line = this.buf.slice(0, nl).trim();
				this.buf = this.buf.slice(nl + 1);
				this.onLine(line);
			}
		});
	}
	private onLine(line: string) {
		// Fields matched INDEPENDENTLY, not as one ordered pattern. Stockfish
		// emits `info depth 12 seldepth 15 multipv 1 score cp 20 ... pv e2e4`,
		// i.e. depth BEFORE multipv — an ordered regex expecting multipv first
		// matches nothing, silently yields an empty line-set, and every caller
		// then behaves as though the position had no legal moves. That failure
		// is invisible: it looks like a null result rather than a broken parse.
		const mpv = /\bmultipv (\d+)/.exec(line);
		const dep = /\bdepth (\d+)/.exec(line);
		const sco = /\bscore (cp|mate) (-?\d+)/.exec(line);
		const pvm = /\bpv (.+)$/.exec(line);
		if (line.startsWith('info') && mpv && dep && sco && pvm) {
			const mv: EngineMove = {
				multipv: +mpv[1], depth: +dep[1],
				score: sco[1] === 'cp' ? +sco[2] / 100 : 0,
				mate: sco[1] === 'mate' ? +sco[2] : null,
				pv: pvm[1].trim().split(' ')
			};
			const at = this.lines.findIndex((l) => l.multipv === mv.multipv);
			if (at >= 0) this.lines[at] = mv; else this.lines.push(mv);
		}
		for (let i = this.waiters.length - 1; i >= 0; i--) {
			if (this.waiters[i].pred(line)) this.waiters.splice(i, 1)[0].res(line);
		}
	}
	send(s: string) { this.proc.stdin.write(s + '\n'); }
	until(pred: (l: string) => boolean): Promise<string> {
		return new Promise((res) => this.waiters.push({ pred, res }));
	}
	async ready() { this.send('uci'); await this.until((l) => l === 'uciok'); this.send('isready'); await this.until((l) => l === 'readyok'); }
	quit() { this.send('quit'); setTimeout(() => this.proc.kill(), 500); }
}

/** MultiPV lines for a position, from the app's own wasm Stockfish. */
async function analyse(sf: Uci, fen: string): Promise<EngineMove[]> {
	sf.lines = [];
	sf.send(`position fen ${fen}`);
	sf.send(`go depth ${DEPTH}`);
	await sf.until((l) => l.startsWith('bestmove'));
	return [...sf.lines].sort((a, b) => a.multipv - b.multipv);
}

async function main() {
	const sf = new Uci('scripts/wasm-engine/run.sh');
	await sf.ready();
	sf.send(`setoption name MultiPV value ${MULTIPV}`);

	const ALL: Record<string, string> = {
		lichess: 'lichess_8layers_ckpt_no_optimizer.pt',
		stockfish: 'stockfish_8layers_ckpt_no_optimizer.pt',
		mix: 'lichess_stockfish_mix_8layers_ckpt_no_optimizer.pt'
	};
	const VARIANTS: Record<string, string> = ONLY
		? { [ONLY]: ALL[ONLY] }
		: ALL;
	const out: Record<string, Record<string, number>> = {};
	const meta: Record<string, Record<string, number>> = {};

	// Each player under test faces the SAME opponent — the shaped bot at the
	// strength the gym measured them at — so the positions they face are
	// comparable and any label difference is theirs.
	for (const [name, model] of Object.entries(VARIANTS)) {
		const eng = new Uci('scripts/shims/chessgpt/run.sh');
		await eng.ready();
		eng.send(`setoption name Model value ${model}`);
		eng.send('isready');
		await eng.until((l) => l === 'readyok');

		const labels: Record<string, number> = {};
		let graded = 0, plies = 0, decisive = 0, drawn = 0, refused = 0;

		for (let g = 0; g < GAMES; g++) {
			const refusedBefore = refused;
			const chess = new Chess();
			for (const san of OPENINGS[g % OPENINGS.length].split(' ')) chess.move(san);
			const modelIsWhite = g % 2 === 0;
			eng.send('ucinewgame');

			while (!chess.isGameOver() && chess.history().length < MAX_PLIES) {
				const mine = (chess.turn() === 'w') === modelIsWhite;
				const fenBefore = chess.fen();
				let uci: string | null;
				if (mine) {
					// `startpos moves`, NOT a bare FEN. Chess-GPT's input is
					// MOVETEXT, so from a position with no history the shim has to
					// search backwards for a path to the start — and from this
					// seeded 4-ply opening, playing Black, its first position is 5
					// plies deep and that search is one ply too shallow. It declined,
					// the loop broke at ply 0, and the tally below scored the game a
					// DRAW. Every ChessGPT figure this script produced was half that
					// artefact and half chess.
					eng.send(`position startpos moves ${
						chess.history({ verbose: true }).map((m) => m.lan).join(' ')}`);
					eng.send('go');
					const best = await eng.until((l) => l.startsWith('bestmove'));
					uci = best.split(' ')[1];
					// Not "the model was never asked" — on this path it was. See the
					// tally below.
					if (uci === '0000') { refused++; break; }
				} else {
					const lines = await analyse(sf, fenBefore);
					uci = shapedBotMove(lines, 1200, undefined, `${name}:${g}`, fenBefore);
				}
				if (!uci) break;

				// Grade only the model's own moves, and only when there is a real
				// pre-move analysis to grade against.
				if (mine) {
					const pre = await analyse(sf, fenBefore);
					if (pre.length) {
						const san = chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] })?.san;
						if (!san) break;
						const child = await analyse(sf, chess.fen());
						// Positional args: this is the TS function, not the Dart wrapper's
						// named-parameter shape that game_controller uses.
						const base = gradeMove(chess.history().length, fenBefore, san, uci,
							modelIsWhite ? 'w' : 'b', pre);
						if (base) {
							const grade = backfillGrade(base, child);
							if (grade.label) labels[grade.label] = (labels[grade.label] ?? 0) + 1;
						}
						graded++;
						plies++;
						continue;
					}
				}
				try { chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] }); } catch { break; }
				plies++;
			}
			// A refusal is not a DRAW — counting it as one is what turned a real
			// ~29% draw rate into the ~60% first reported here.
			//
			// But it is no longer a harness artefact either, and the first
			// version of this comment said it was. On the `position startpos
			// moves` path the shim's reconstruction cannot fail (it is handed
			// the history), so a `0000` now means the model exhausted six
			// sampling attempts without producing a legal move — a real failure
			// by a real player. Discarding those games would flatter the weaker
			// nets and erase an untrained control entirely.
			//
			// So: scored as a LOSS for the model, and counted separately so the
			// rate is visible rather than blended into the decisive column.
			if (refused > refusedBefore) decisive++;
			else if (chess.isCheckmate()) decisive++;
			else drawn++;
			out[name] = labels;
			meta[name] = { graded, plies, decisive, drawn, refused };
			writeFileSync(OUT, JSON.stringify(
				{ ranAt: new Date().toISOString(), games: GAMES, depth: DEPTH, labels: out, meta }, null, 2));
			console.log(`${name}: game ${g + 1}/${GAMES}, ${graded} graded, ${decisive} decisive, ${refused} refused`);
		}
		eng.quit();
		out[name] = labels;
		meta[name] = { graded, plies, decisive, drawn, refused };
		process.stdout.write('\n');
	}
	sf.quit();

	writeFileSync(OUT, JSON.stringify({ ranAt: new Date().toISOString(), games: GAMES, depth: DEPTH, labels: out, meta }, null, 2));
	console.log('\n=== label distribution, % of graded moves ===');
	const all = [...new Set(Object.values(out).flatMap((o) => Object.keys(o)))];
	console.log(['label'.padEnd(12), ...Object.keys(out).map((k) => k.padStart(10))].join(''));
	for (const lab of all) {
		const row = Object.entries(out).map(([k, o]) => {
			const pct = (100 * (o[lab] ?? 0)) / Math.max(1, meta[k].graded);
			return `${pct.toFixed(1)}%`.padStart(10);
		});
		console.log([lab.padEnd(12), ...row].join(''));
	}
	console.log('\n=== games ===');
	for (const [k, m] of Object.entries(meta)) console.log(`  ${k.padEnd(10)} graded ${m.graded}  decisive ${m.decisive}  drawn ${m.drawn}  refused ${m.refused}`);
	console.log(`\nwrote ${OUT}`);
}

main();
