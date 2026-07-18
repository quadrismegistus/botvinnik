// Bake the opening book: crawl the public lichess opening explorer ONCE and
// write the popular opening tree as a static asset — the app answers Book
// queries offline, no API at runtime.
//
//   npx tsx scripts/crawl-book.mts
//
// BFS from the start position; a child position is enqueued when its move
// has enough games (relative + absolute floor), up to a node cap and ply
// cap. Resumable: progress persists to data/book-crawl-state.json every 25
// nodes, so a killed crawl continues where it stopped. Polite: ~1.1s между
// requests (explorer.lichess.ovh asks for gentleness).

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const STATE = resolve(ROOT, 'data/book-crawl-state.json');
const OUT = resolve(ROOT, 'flutter/assets/book.json');

const MAX_NODES = 4000; // ≈ a 3-4MB asset
const MAX_PLY = 16;
const MIN_GAMES = 3000; // absolute floor for a move to be kept at all
const MIN_SHARE = 0.02; // …or ≥2% of its parent's games
const TOP_MOVES = 6;
const DELAY_MS = 1100;

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/** normalized key: fen fields 1-4 (piece placement, turn, castling, ep) */
function epd(fen: string): string {
	return fen.split(' ').slice(0, 4).join(' ');
}

interface BookMove {
	uci: string;
	san: string;
	white: number;
	draws: number;
	black: number;
}
interface BookNode {
	white: number;
	draws: number;
	black: number;
	moves: BookMove[];
}
interface State {
	book: Record<string, BookNode>;
	queue: { fen: string; ply: number }[];
	seen: string[];
}

let state: State;
if (existsSync(STATE)) {
	state = JSON.parse(readFileSync(STATE, 'utf8'));
	console.log(`resuming: ${Object.keys(state.book).length} nodes, ${state.queue.length} queued`);
} else {
	state = { book: {}, queue: [{ fen: START, ply: 0 }], seen: [epd(START)] };
}
const seen = new Set(state.seen);

function saveState() {
	state.seen = [...seen];
	mkdirSync(dirname(STATE), { recursive: true });
	writeFileSync(STATE, JSON.stringify(state));
}

function writeAsset() {
	const nodes = Object.keys(state.book).length;
	writeFileSync(OUT, JSON.stringify({ version: 1, nodes, book: state.book }));
	const mb = (JSON.stringify(state.book).length / 1e6).toFixed(1);
	console.log(`asset: ${nodes} positions, ~${mb}MB → ${OUT}`);
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function fetchNode(fen: string): Promise<BookNode | null> {
	const url =
		'https://explorer.lichess.ovh/lichess?variant=standard' +
		'&speeds=blitz,rapid,classical&ratings=1200,1400,1600,1800,2000' +
		`&fen=${encodeURIComponent(fen)}&moves=${TOP_MOVES}&topGames=0&recentGames=0`;
	for (let attempt = 0; attempt < 5; attempt++) {
		try {
			const res = await fetch(url);
			if (res.status === 429) {
				console.log('429 — backing off 60s');
				await sleep(60_000);
				continue;
			}
			if (!res.ok) throw new Error(`http ${res.status}`);
			const j = (await res.json()) as {
				white: number;
				draws: number;
				black: number;
				moves: { uci: string; san: string; white: number; draws: number; black: number }[];
			};
			return {
				white: j.white,
				draws: j.draws,
				black: j.black,
				moves: j.moves.map((m) => ({
					uci: m.uci,
					san: m.san,
					white: m.white,
					draws: m.draws,
					black: m.black
				}))
			};
		} catch (e) {
			console.log(`retry ${attempt + 1}: ${(e as Error).message}`);
			await sleep(5000 * (attempt + 1));
		}
	}
	return null;
}

let sinceSave = 0;
while (state.queue.length > 0 && Object.keys(state.book).length < MAX_NODES) {
	const { fen, ply } = state.queue.shift()!;
	const key = epd(fen);
	if (state.book[key]) continue;

	const node = await fetchNode(fen);
	if (node === null) {
		console.log('giving up on', key);
		continue;
	}
	state.book[key] = node;

	const total = node.white + node.draws + node.black;
	if (ply < MAX_PLY) {
		for (const m of node.moves) {
			const games = m.white + m.draws + m.black;
			if (games < MIN_GAMES && games < total * MIN_SHARE) continue;
			if (games < 200) continue; // never descend into a trickle
			const chess = new Chess(fen);
			const mv = chess.move({ from: m.uci.slice(0, 2), to: m.uci.slice(2, 4), promotion: m.uci[4] });
			if (!mv) continue;
			const childFen = chess.fen();
			const childKey = epd(childFen);
			if (!seen.has(childKey)) {
				seen.add(childKey);
				state.queue.push({ fen: childFen, ply: ply + 1 });
			}
		}
	}

	const n = Object.keys(state.book).length;
	if (n % 25 === 0) {
		console.log(`${n} nodes, ${state.queue.length} queued (ply ${ply})`);
		saveState();
	}
	if (++sinceSave >= 200) {
		sinceSave = 0;
		writeAsset(); // periodic partial asset so the app can use it early
	}
	await sleep(DELAY_MS);
}

saveState();
writeAsset();
console.log('crawl complete');
