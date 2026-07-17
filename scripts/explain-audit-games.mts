// Part B of the explanation audit: coverage on REAL blunders, not puzzles.
// Puzzles are curated tactics — almost by construction our detectors have
// something to say. The insight cards' actual population is the mistakes in
// Ryan's own games (data/chesscom-elonmarxx-backup.json, 4505 analyzed
// games). The backup stores labels but no PVs, so each sampled move gets two
// native-Stockfish searches (best line from fenBefore, refutation after the
// played move), then explainMove() runs exactly as the app would run it and
// we tally which claim family fired — or whether the card would fall back to
// a bare refutation arrow.
//
//   npx tsx scripts/explain-audit-games.mts [--n 400] [--depth 14]
//     [--backup data/chesscom-elonmarxx-backup.json] [--engine PATH]

import { readFileSync, existsSync } from 'node:fs';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { Chess } from 'chess.js';
import { explainMove, type Explanation } from '../src/lib/engine/explain';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const N = Number(opt('n', '400'));
const DEPTH = Number(opt('depth', '14'));
const BACKUP = opt('backup', 'data/chesscom-elonmarxx-backup.json');
// node_modules/.bin shadows PATH under npx tsx — resolve native by absolute path
const NATIVE_CANDIDATES = ['/opt/homebrew/bin/stockfish', '/usr/local/bin/stockfish', '/usr/bin/stockfish'];
const ENGINE = opt('engine', NATIVE_CANDIDATES.find((p) => existsSync(p)) ?? 'stockfish');

interface Line {
	pv: string[];
	mate: number | null;
}
class Engine {
	private proc!: ChildProcessWithoutNullStreams;
	private buffer = '';
	private last: Line = { pv: [], mate: null };
	private resolve: ((l: Line) => void) | null = null;
	private watchdog: ReturnType<typeof setTimeout> | null = null;

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
		this.proc.stdin.write('uci\nsetoption name Threads value 1\nsetoption name Hash value 64\nisready\n');
	}
	private onData(chunk: string) {
		this.buffer += chunk;
		const lines = this.buffer.split('\n');
		this.buffer = lines.pop() ?? '';
		for (const line of lines) {
			if (line.startsWith('info ') && line.includes(' pv ')) {
				const mate = line.match(/ score mate (-?\d+)/);
				const pv = line.split(' pv ')[1]?.trim().split(' ') ?? [];
				if (pv.length) this.last = { pv, mate: mate ? Number(mate[1]) : null };
			} else if (line.startsWith('bestmove')) {
				if (this.watchdog) clearTimeout(this.watchdog);
				this.watchdog = null;
				const r = this.resolve;
				this.resolve = null;
				r?.(this.last);
			}
		}
	}
	search(fen: string): Promise<Line> {
		this.last = { pv: [], mate: null };
		return new Promise((resolve) => {
			this.resolve = resolve;
			this.watchdog = setTimeout(() => {
				console.warn('engine timeout — respawning');
				try {
					this.proc.kill();
				} catch {
					// already gone
				}
				this.start();
				const r = this.resolve;
				this.resolve = null;
				r?.({ pv: [], mate: null });
			}, 30_000);
			this.proc.stdin.write(`position fen ${fen}\ngo depth ${DEPTH}\n`);
		});
	}
	quit() {
		this.proc.stdin.write('quit\n');
	}
}

// deterministic sample — reruns audit the same moves
let seed = 42;
function rand(): number {
	seed = (seed * 1103515245 + 12345) & 0x7fffffff;
	return seed / 0x7fffffff;
}

interface Candidate {
	fenBefore: string;
	uci: string;
	label: string;
}
const backup = JSON.parse(readFileSync(BACKUP, 'utf8'));
const WANT = new Set(['blunder', 'mistake', 'inaccuracy']);
const pool: Candidate[] = [];
for (const g of backup.games) {
	// only the user's own moves — that's who the insight cards talk to
	const me = g.white?.toLowerCase() === 'elonmarxx' ? 'w' : 'b';
	for (const m of g.moves ?? []) {
		if (m.color !== me || !WANT.has(m.label) || !m.fenBefore || !m.uci) continue;
		pool.push({ fenBefore: m.fenBefore, uci: m.uci, label: m.label });
	}
}
// shuffle, then take a label-balanced sample
for (let i = pool.length - 1; i > 0; i--) {
	const j = Math.floor(rand() * (i + 1));
	[pool[i], pool[j]] = [pool[j], pool[i]];
}
const perLabel = Math.ceil(N / 3);
const taken = new Map<string, number>();
const sample = pool.filter((c) => {
	const t = taken.get(c.label) ?? 0;
	if (t >= perLabel) return false;
	taken.set(c.label, t + 1);
	return true;
});
console.log(
	`pool: ${pool.length} labeled moves; sampling ${sample.length} (per label: ${[...taken.entries()].map(([k, v]) => `${k} ${v}`).join(', ')}) at depth ${DEPTH}\n`
);

function issueFamily(e: Explanation): string | undefined {
	const t = e.playedIssue;
	if (!t) return undefined;
	// "allows … mate", NOT a bare /mate/ — "loses material" contains "mate"
	if (/allows/.test(t)) return 'mate allowed';
	if (/undefended —/.test(t)) return 'hanging piece';
	if (/loses material/.test(t)) return 'loses material';
	if (/loses a pawn/.test(t)) return 'loses a pawn';
	return 'other';
}
function pointFamily(e: Explanation): string | undefined {
	const t = e.bestPoint;
	if (!t) return undefined;
	if (/checkmate|forces mate/.test(t)) return 'mate';
	if (/sacrifices/.test(t)) return 'sacrifice';
	if (/ forks /.test(t)) return 'fork';
	if (/simply wins/.test(t)) return 'free capture';
	if (/ pins /.test(t)) return 'pin';
	if (/ skewers /.test(t)) return 'skewer';
	if (/discovers|uncovers/.test(t)) return 'discovered';
	if (/ traps /.test(t)) return 'trapped';
	if (/makes a new/.test(t)) return 'promotion';
	if (/material/.test(t)) return 'material';
	if (/wins a pawn/.test(t)) return 'wins a pawn';
	return 'other';
}

interface Bucket {
	n: number;
	engineAgreesBest: number;
	issue: Map<string, number>;
	point: Map<string, number>;
	storyOnly: number;
	nothing: number;
}
const buckets = new Map<string, Bucket>();
function bucket(label: string): Bucket {
	let b = buckets.get(label);
	if (!b) {
		b = { n: 0, engineAgreesBest: 0, issue: new Map(), point: new Map(), storyOnly: 0, nothing: 0 };
		buckets.set(label, b);
	}
	return b;
}
const bump = (m: Map<string, number>, k: string) => m.set(k, (m.get(k) ?? 0) + 1);

const engine = new Engine();
let done = 0;
const examplesOfNothing: string[] = [];
for (const c of sample) {
	const best = await engine.search(c.fenBefore);
	if (!best.pv.length) continue;
	if (best.pv[0] === c.uci) {
		// our depth disagrees with the stored label — engine calls it best
		bucket(c.label).engineAgreesBest++;
		bucket(c.label).n++;
		done++;
		continue;
	}
	const chess = new Chess(c.fenBefore);
	try {
		chess.move({ from: c.uci.slice(0, 2), to: c.uci.slice(2, 4), promotion: c.uci[4] });
	} catch {
		continue;
	}
	const after = await engine.search(chess.fen());
	// scores at fenAfter are from the OPPONENT's perspective — flip for the mover
	const playedMate = after.mate === null ? null : -after.mate;
	const e = explainMove({
		fenBefore: c.fenBefore,
		playedUci: c.uci,
		refutationPv: after.pv,
		bestUci: best.pv[0],
		bestPv: best.pv,
		playedMate,
		bestMate: best.mate,
		isBest: false
	});
	const b = bucket(c.label);
	b.n++;
	const fi = issueFamily(e);
	const fp = pointFamily(e);
	if (fi) bump(b.issue, fi);
	if (fp) bump(b.point, fp);
	if (!fi && !fp) {
		if (e.lineStory) b.storyOnly++;
		else {
			b.nothing++;
			if (examplesOfNothing.length < 8) examplesOfNothing.push(`${c.label}: ${c.fenBefore} played ${c.uci} best ${best.pv[0]}`);
		}
	}
	done++;
	if (done % 50 === 0) console.log(`  ...${done}/${sample.length}`);
}
engine.quit();

const pct = (a: number, b: number) => (b === 0 ? '  —' : `${((100 * a) / b).toFixed(0).padStart(3)}%`);
console.log('\nCOVERAGE ON REAL MISTAKES (what the insight card can say)\n');
for (const label of ['blunder', 'mistake', 'inaccuracy']) {
	const b = buckets.get(label);
	if (!b) continue;
	const graded = b.n - b.engineAgreesBest;
	console.log(`${label} (${b.n} sampled, ${b.engineAgreesBest} re-judged best at d${DEPTH} → ${graded} graded):`);
	const anyIssue = [...b.issue.values()].reduce((a, x) => a + x, 0);
	const anyPoint = [...b.point.values()].reduce((a, x) => a + x, 0);
	console.log(`  playedIssue ${pct(anyIssue, graded)}   ${[...b.issue.entries()].sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(', ')}`);
	console.log(`  bestPoint   ${pct(anyPoint, graded)}   ${[...b.point.entries()].sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(', ')}`);
	console.log(`  lineStory only ${pct(b.storyOnly, graded)}   nothing at all ${pct(b.nothing, graded)}\n`);
}
if (examplesOfNothing.length) {
	console.log('sample positions where we had NOTHING to say:');
	for (const x of examplesOfNothing) console.log(`  ${x}`);
}
