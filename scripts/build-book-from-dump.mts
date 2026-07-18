// Bake the opening book from the PUBLIC lichess database dump (CC0, no
// auth, no rate limits) — stream one month, count positions ourselves,
// write the popular opening tree as flutter/assets/book.json.
//
//   npx tsx scripts/build-book-from-dump.mts [games] [month]
//   (defaults: 400000 games from 2026-05; a few minutes of streaming)
//
// Filters mirror the web Book's explorer defaults: blitz/rapid/classical,
// both players 1200-2200. Positions up to ply 16. SAN replay is memoized by
// (epd, san) — openings repeat massively, so chess.js runs only on cache
// misses. The map is pruned of trickle positions periodically to keep RAM
// flat, and hard-pruned (min games, top-6 moves) before writing.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';

const TARGET_GAMES = Number(process.argv[2] ?? 400_000);
const MONTH = process.argv[3] ?? '2026-05';
const MAX_PLY = 16;
const MIN_NODE_GAMES = 100; // final prune: a position must have this many
const TOP_MOVES = 6;

const OUT = resolve(
	dirname(fileURLToPath(import.meta.url)),
	'../flutter/assets/book.json'
);
const START_EPD = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

interface MoveStat {
	san: string;
	white: number;
	draws: number;
	black: number;
}
interface Node {
	white: number;
	draws: number;
	black: number;
	moves: Map<string, MoveStat>; // by uci
}
const book = new Map<string, Node>();

// (epd|san) → [uci, nextEpd] — the whole point of the memo
const sanCache = new Map<string, [string, string]>();
const chess = new Chess();

function epdOf(fen: string): string {
	const p = fen.split(' ');
	// normalize: drop counters; ep square only matters when capture possible,
	// but keep field 4 as-is for correctness (explorer does the same)
	return p.slice(0, 4).join(' ');
}

function bump(node: Node, uci: string, san: string, result: string) {
	if (result === '1-0') node.white++;
	else if (result === '0-1') node.black++;
	else node.draws++;
	let m = node.moves.get(uci);
	if (!m) {
		m = { san, white: 0, draws: 0, black: 0 };
		node.moves.set(uci, m);
	}
	if (result === '1-0') m.white++;
	else if (result === '0-1') m.black++;
	else m.draws++;
}

let accepted = 0;
let seenGames = 0;

function ingest(sans: string[], result: string) {
	let epd = START_EPD;
	for (let i = 0; i < Math.min(sans.length, MAX_PLY); i++) {
		const san = sans[i];
		const key = `${epd}|${san}`;
		let hit = sanCache.get(key);
		if (!hit) {
			// an epd fully determines the position (counters are irrelevant
			// here) — reconstruct, play the san once, memoize forever
			try {
				chess.load(`${epd} 0 1`);
				const mv = chess.move(san);
				if (!mv) return;
				hit = [mv.from + mv.to + (mv.promotion ?? ''), epdOf(chess.fen())];
				sanCache.set(key, hit);
			} catch {
				return; // unparsable/illegal — abandon this game's tail
			}
		}
		let node = book.get(epd);
		if (!node) {
			node = { white: 0, draws: 0, black: 0, moves: new Map() };
			book.set(epd, node);
		}
		bump(node, hit[0], san, result);
		epd = hit[1];
	}
}

function prune(minGames: number) {
	for (const [k, n] of book) {
		if (n.white + n.draws + n.black < minGames) book.delete(k);
	}
}

function writeAsset() {
	prune(MIN_NODE_GAMES);
	const out: Record<
		string,
		{ white: number; draws: number; black: number; moves: unknown[] }
	> = {};
	for (const [k, n] of book) {
		const moves = [...n.moves.entries()]
			.map(([uci, m]) => ({ uci, ...m }))
			.sort(
				(a, b) => b.white + b.draws + b.black - (a.white + a.draws + a.black)
			)
			.slice(0, TOP_MOVES);
		out[k] = { white: n.white, draws: n.draws, black: n.black, moves };
	}
	const doc = JSON.stringify({
		version: 1,
		source: `lichess_db_standard_rated_${MONTH}, ${accepted} games, elo 1200-2200, blitz/rapid/classical`,
		nodes: Object.keys(out).length,
		book: out
	});
	writeFileSync(OUT, doc);
	writeFileSync(OUT.replace('flutter/assets', 'static'), doc);
	console.log(
		`asset: ${Object.keys(out).length} positions, ${(doc.length / 1e6).toFixed(1)}MB → ${OUT} (+static/)`
	);
}

const url = `https://database.lichess.org/standard/lichess_db_standard_rated_${MONTH}.pgn.zst`;
console.log(`streaming ${url} (target ${TARGET_GAMES} accepted games)`);
const proc = spawn('bash', ['-c', `curl -s '${url}' | zstd -d --stdout`]);
const rl = createInterface({ input: proc.stdout });

let headers: Record<string, string> = {};
let movetext = '';

function endOfGame() {
	seenGames++;
	const event = headers['Event'] ?? '';
	const result = headers['Result'] ?? '*';
	const we = Number(headers['WhiteElo'] ?? 0);
	const be = Number(headers['BlackElo'] ?? 0);
	const speedOk = /Blitz|Rapid|Classical/.test(event) && !/Bullet/.test(event);
	const eloOk = we >= 1200 && we <= 2200 && be >= 1200 && be <= 2200;
	const resultOk = result === '1-0' || result === '0-1' || result === '1/2-1/2';
	if (speedOk && eloOk && resultOk && movetext.length > 0) {
		// strip comments/NAGs/move numbers/result → bare SAN tokens
		const sans = movetext
			.replace(/\{[^}]*\}/g, ' ')
			.replace(/\$\d+/g, ' ')
			.split(/\s+/)
			.filter((t) => t && !/^\d+\.+$/.test(t) && !/^(1-0|0-1|1\/2-1\/2|\*)$/.test(t))
			.map((t) => t.replace(/[?!]+$/, ''));
		if (sans.length >= 2) {
			ingest(sans, result);
			accepted++;
			if (accepted % 25_000 === 0) {
				console.log(
					`${accepted} games ingested (${seenGames} seen) — ${book.size} raw positions, san-cache ${sanCache.size}`
				);
				prune(3); // drop trickle to keep RAM flat
			}
			if (accepted >= TARGET_GAMES) {
				proc.kill('SIGKILL');
				rl.close();
				writeAsset();
				process.exit(0);
			}
		}
	}
	headers = {};
	movetext = '';
}

rl.on('line', (line) => {
	if (line.startsWith('[')) {
		if (movetext.length > 0) endOfGame();
		const m = line.match(/^\[(\w+) "(.*)"\]/);
		if (m) headers[m[1]] = m[2];
	} else if (line.trim().length > 0) {
		movetext += ' ' + line;
	}
});
rl.on('close', () => {
	if (movetext.length > 0) endOfGame();
	writeAsset();
});
