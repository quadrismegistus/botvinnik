// Direct test of the punish-rate hypothesis: don't infer from rating
// gradients, COUNT the events. Replays SquareFish's lichess games and, at
// every position, asks two questions with the model's own definition of a
// "visible gift" (dangerVisibility's glaring tier: a piece capturable by a
// cheaper attacker, or capturable and undefended, value ≥ 3):
//
//   punish rate — a visible gift was on offer; did the bot take one?
//   gift rate   — did the bot's own move leave its piece glaring?
//
// Split by model era (deployments.json) and opponent type. The v3→v4
// hypothesis predicts: punish rate jumps (the miss coin stopped firing on
// grabs), gift rate drops (the danger penalty), and human opponents offer
// more gifts than the bot pool — which is why the same model change is worth
// +570 vs humans, +287 vs bots, and ~0 vs calibration Stockfish.
//
//   npx tsx scripts/squarefish/hangs.mts [--user SquareFish-900] [--max 400]

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess, type Move } from 'chess.js';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const USER = opt('user', 'SquareFish-900');
const MAX = Number(opt('max', '400'));

const PIECE_VAL: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

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
	return era.model;
}

// the model's "glaring" tier, from the capturer's side: capture where the
// victim outvalues the attacker, or the victim is undefended (value ≥ 3)
function visibleGifts(c: Chess): Move[] {
	const gifts: Move[] = [];
	for (const m of c.moves({ verbose: true })) {
		if (!m.captured || PIECE_VAL[m.captured] < 3) continue;
		if (PIECE_VAL[m.captured] > PIECE_VAL[m.piece]) {
			gifts.push(m);
			continue;
		}
		// equal-or-lower-value victim: a gift only if undefended (no recapture)
		const probe = new Chess(c.fen());
		probe.move(m);
		const recaptured = probe.moves({ verbose: true }).some((r) => r.to === m.to && r.captured);
		if (!recaptured) gifts.push(m);
	}
	return gifts;
}

// did this just-played move leave the moved piece glaring? (dangerVisibility
// semantics, re-derived: cheaper attacker, or undefended and value ≥ 3)
function leftGlaring(c: Chess, played: Move): boolean {
	const dest = played.to;
	const movedVal = PIECE_VAL[played.promotion ?? played.piece];
	let cheapest = Infinity;
	for (const reply of c.moves({ verbose: true }))
		if (reply.to === dest && reply.captured) cheapest = Math.min(cheapest, PIECE_VAL[reply.piece]);
	if (cheapest === Infinity) return false;
	if (cheapest < movedVal - 1) return true;
	if (movedVal < 3) return false;
	const attacker = c.moves({ verbose: true }).find((m) => m.to === dest && m.captured);
	if (!attacker) return false;
	const probe = new Chess(c.fen());
	probe.move(attacker);
	const defended = probe.moves({ verbose: true }).some((m) => m.to === dest && m.captured);
	return !defended;
}

interface Tally {
	oppos: number; // positions with a visible gift on offer
	taken: number; // ... where the bot took one
	queenOppos: number;
	queenTaken: number;
	moves: number; // bot moves total
	glaring: number; // ... that left the moved piece glaring
	games: number;
}
const tallies = new Map<string, Tally>();
function tally(key: string): Tally {
	let t = tallies.get(key);
	if (!t) {
		t = { oppos: 0, taken: 0, queenOppos: 0, queenTaken: 0, moves: 0, glaring: 0, games: 0 };
		tallies.set(key, t);
	}
	return t;
}

const res = await fetch(
	`https://lichess.org/api/games/user/${USER}?max=${MAX}&moves=true&opening=false`,
	{ headers: { Accept: 'application/x-ndjson' } }
);
const text = await res.text();
let scanned = 0;
for (const line of text.split('\n')) {
	if (!line.trim()) continue;
	const g = JSON.parse(line);
	const ps = g.players;
	if (!ps.white?.user || !ps.black?.user) continue;
	const side = ps.white.user.id === USER.toLowerCase() ? 'w' : 'b';
	const opp = ps[side === 'w' ? 'black' : 'white'];
	const kind = opp.user.title === 'BOT' ? 'bots' : 'humans';
	const key = `${eraOf(g.createdAt)} vs ${kind}`;
	const t = tally(key);
	const to = tally(`OPPONENTS (${kind})`); // the gift supply, era-independent
	t.games++;
	const c = new Chess();
	for (const san of (g.moves ?? '').split(' ').filter(Boolean)) {
		const mover = c.turn();
		if (mover === side) {
			const gifts = visibleGifts(c);
			const giftSquares = new Set(gifts.map((m) => m.to));
			const queenGift = gifts.some((m) => m.captured === 'q');
			let played: Move;
			try {
				played = c.move(san);
			} catch {
				break;
			}
			t.moves++;
			if (gifts.length > 0) {
				t.oppos++;
				if (played.captured && giftSquares.has(played.to)) t.taken++;
				if (queenGift) {
					t.queenOppos++;
					if (played.captured === 'q') t.queenTaken++;
				}
			}
			if (leftGlaring(c, played)) t.glaring++;
		} else {
			// opponent move: measure the pool's own gift rate
			let played: Move;
			try {
				played = c.move(san);
			} catch {
				break;
			}
			to.moves++;
			if (leftGlaring(c, played)) to.glaring++;
		}
	}
	scanned++;
}

console.log(`${scanned} games scanned\n`);
const pct = (a: number, b: number) => (b === 0 ? '—' : `${((100 * a) / b).toFixed(1)}%`);
for (const [key, t] of [...tallies.entries()].sort()) {
	if (key.startsWith('OPPONENTS')) {
		console.log(`${key}: gift rate ${pct(t.glaring, t.moves)} of moves (${t.glaring}/${t.moves})`);
		continue;
	}
	console.log(`${key} (${t.games} games):`);
	console.log(`   punish rate: ${pct(t.taken, t.oppos)} (${t.taken}/${t.oppos} gift-positions)`);
	console.log(`   queen gifts taken: ${pct(t.queenTaken, t.queenOppos)} (${t.queenTaken}/${t.queenOppos})`);
	console.log(`   own gift rate: ${pct(t.glaring, t.moves)} of moves (${t.glaring}/${t.moves})`);
}
