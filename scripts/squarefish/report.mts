// SquareFish rating report: fetch the bot's lichess games and split them into
// the three populations that mean different things, because the front-page
// rating stopped meaning anything when bot games were enabled (2026-07-15):
//
//   bots      — engine-pool measurement (opponent title BOT)
//   strangers — THE HUMAN-POOL ANCHOR: the number label-978 was deployed to earn
//   self      — the developer's own games (default ElonMarx), excluded from the
//               anchor for the same reason takebacks are excluded from the app's
//               player fit: he knows the bot's blind spots by design
//
// Per population: W-L-D, average opponent, quick performance rating, and an
// MLE Elo fit (logistic model, one virtual draw vs the mean opponent as the
// regularizer, SE from the observed Fisher information) — the same estimator
// shape as src/lib/playerElo.ts, over lichess opponents' at-game ratings.
//
//   npx tsx scripts/squarefish/report.mts [--user SquareFish-900]
//       [--self ElonMarx[,other]] [--snapshot]
//
// --snapshot appends a dated row to data/squarefish-report.json so
// convergence is watchable over time.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const USER = opt('user', 'SquareFish-900');
const SELF = new Set(opt('self', 'ElonMarx').toLowerCase().split(','));
const SNAPSHOT = argv.includes('--snapshot');
const TARGET = 900; // the display rating label-978 was calibrated to

interface Row {
	score: number; // 1 win, 0.5 draw, 0 loss (SquareFish's POV)
	opp: string;
	oppRating: number;
	perf: string;
	rated: boolean;
	status: string;
	createdAt: number; // ms epoch — era-split against deployments.json
}

// model eras: deployments.json records each cutover; games split by timestamp
// so the v3 anchor and the v4 measurement never blend
interface Deployment {
	from: string;
	model: string;
	label: number;
}
const DEPLOYMENTS: Deployment[] = JSON.parse(
	readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'deployments.json'), 'utf8')
);
function eraOf(createdAt: number): string {
	let era = DEPLOYMENTS[0];
	for (const d of DEPLOYMENTS) if (createdAt >= Date.parse(d.from)) era = d;
	return `${era.model} (label ${era.label})`;
}

async function fetchGames(): Promise<Row[]> {
	const res = await fetch(
		`https://lichess.org/api/games/user/${USER}?max=500&moves=false&opening=false`,
		{ headers: { Accept: 'application/x-ndjson' } }
	);
	if (!res.ok) throw new Error(`lichess API ${res.status}`);
	const text = await res.text();
	const rows: Row[] = [];
	for (const line of text.split('\n')) {
		if (!line.trim()) continue;
		const g = JSON.parse(line);
		const ps = g.players;
		const side = ps.white?.user?.id === USER.toLowerCase() ? 'white' : 'black';
		const opp = ps[side === 'white' ? 'black' : 'white'];
		if (!opp?.user || opp.rating === undefined) continue; // anonymous/aborted
		rows.push({
			score: g.winner === undefined ? 0.5 : g.winner === side ? 1 : 0,
			opp: (opp.user.title === 'BOT' ? 'BOT:' : '') + opp.user.name,
			oppRating: opp.rating,
			perf: g.perf,
			rated: !!g.rated,
			status: g.status,
			createdAt: g.createdAt ?? 0
		});
	}
	return rows;
}

// logistic Elo MLE with one virtual draw vs the mean opponent (regularizer),
// SE from numerical Fisher information — playerElo.ts's estimator shape
function fitElo(rows: Row[]): { elo: number; se: number } | null {
	if (rows.length === 0) return null;
	const mean = rows.reduce((a, r) => a + r.oppRating, 0) / rows.length;
	const obs = [...rows.map((r) => ({ s: r.score, o: r.oppRating })), { s: 0.5, o: mean }];
	const ll = (theta: number) =>
		obs.reduce((a, { s, o }) => {
			const e = 1 / (1 + 10 ** ((o - theta) / 400));
			return a + s * Math.log(e) + (1 - s) * Math.log(1 - e);
		}, 0);
	let best = 400;
	let bestLl = -Infinity;
	for (let t = 400; t <= 2600; t++) {
		const v = ll(t);
		if (v > bestLl) {
			bestLl = v;
			best = t;
		}
	}
	const h = (ll(best + 25) - 2 * bestLl + ll(best - 25)) / (25 * 25); // curvature
	const se = h < 0 ? Math.round(1 / Math.sqrt(-h)) : Infinity;
	return { elo: best, se };
}

function report(label: string, rows: Row[]): { n: number; fit: ReturnType<typeof fitElo> } {
	const rated = rows.filter((r) => r.rated);
	const W = rows.filter((r) => r.score === 1).length;
	const L = rows.filter((r) => r.score === 0).length;
	const D = rows.length - W - L;
	console.log(`\n── vs ${label}: ${rows.length} games (${rated.length} rated) — ${W}W ${L}L ${D}D`);
	if (rated.length === 0) return { n: 0, fit: null };
	const avg = rated.reduce((a, r) => a + r.oppRating, 0) / rated.length;
	const Wr = rated.filter((r) => r.score === 1).length;
	const Lr = rated.filter((r) => r.score === 0).length;
	const perfR = Math.round(avg + (400 * (Wr - Lr)) / rated.length);
	const fit = fitElo(rated);
	console.log(`   avg opponent ${Math.round(avg)} · performance ${perfR}`);
	if (fit) console.log(`   MLE fit ${fit.elo} ± ${fit.se}`);
	// casual-inclusive fit: casual games carry the opponent's rating too, and
	// our MLE never needed lichess to move anyone's rating — but casual play
	// is lower-effort and self-selected (experimenters, exploit-probers,
	// serial rematchers), so it reports as a SEPARATE line, never blended
	// into the rated anchor. Unique-opponent count makes farming visible.
	const casual = rows.filter((r) => !r.rated);
	if (casual.length > 0) {
		const all = rows;
		const af = fitElo(all);
		const uniq = new Set(all.map((r) => r.opp)).size;
		const aW = all.filter((r) => r.score === 1).length;
		const aL = all.filter((r) => r.score === 0).length;
		console.log(
			`   incl. ${casual.length} casual: ${all.length} games (${uniq} unique opps), ` +
				`${aW}W ${aL}L ${all.length - aW - aL}D` +
				(af ? ` — fit ${af.elo} ± ${af.se}` : '')
		);
	}
	// era split — the anchor is per-MODEL; never blend across a cutover
	const eras = [...new Set(rated.map((r) => eraOf(r.createdAt)))];
	if (eras.length > 1 || DEPLOYMENTS.length > 1) {
		for (const era of eras) {
			const er = rated.filter((r) => eraOf(r.createdAt) === era);
			const ef = fitElo(er);
			const eW = er.filter((r) => r.score === 1).length;
			const eL = er.filter((r) => r.score === 0).length;
			console.log(
				`     · ${era}: ${er.length} rated, ${eW}W ${eL}L ${er.length - eW - eL}D` +
					(ef ? ` — fit ${ef.elo} ± ${ef.se}` : '')
			);
		}
	}
	return { n: rated.length, fit };
}

const rows = await fetchGames();
const bots = rows.filter((r) => r.opp.startsWith('BOT:'));
const humans = rows.filter((r) => !r.opp.startsWith('BOT:'));
const self = humans.filter((r) => SELF.has(r.opp.toLowerCase()));
const strangers = humans.filter((r) => !SELF.has(r.opp.toLowerCase()));

console.log(`${USER} — ${rows.length} games with rated opponents fetched`);
const anchor = report('strangers (THE HUMAN ANCHOR)', strangers);
const engine = report('bots (engine pool)', bots);
report(`self (${[...SELF].join(', ')} — excluded from the anchor)`, self);

console.log('\n── verdict');
if (anchor.fit && anchor.n >= 10) {
	const d = anchor.fit.elo - TARGET;
	console.log(
		`   human anchor: ${anchor.fit.elo} ± ${anchor.fit.se} vs target ${TARGET} (${d >= 0 ? '+' : ''}${d})`
	);
} else {
	console.log(`   human anchor: not enough stranger games yet (${anchor.n} rated; want ≥10)`);
}
if (engine.fit && anchor.fit && anchor.n >= 10) {
	console.log(`   engine-vs-human pool gap for the shaped family: ${engine.fit.elo - anchor.fit.elo}`);
} else if (engine.fit) {
	console.log(`   engine pool so far: ${engine.fit.elo} ± ${engine.fit.se} (gap needs the human anchor)`);
}

if (SNAPSHOT) {
	const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
	const file = resolve(ROOT, 'data/squarefish-report.json');
	const hist = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : [];
	hist.push({
		date: new Date().toISOString(),
		games: rows.length,
		strangers: { n: anchor.n, fit: anchor.fit },
		bots: { n: engine.n, fit: engine.fit }
	});
	writeFileSync(file, JSON.stringify(hist, null, '\t') + '\n');
	console.log(`\nsnapshot appended to ${file}`);
}
