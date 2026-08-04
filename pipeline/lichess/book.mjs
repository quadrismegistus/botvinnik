// T6 (book-ply half only — see README): a book of SAN move-sequence prefixes
// built from the vendored lichess-org/chess-openings TSVs (CC0, data/openings/
// a.tsv..e.tsv), used to find the ply of a game's first out-of-book move.
//
// Pure string matching against a trie — no chess.js replay, no EPD/FEN. The
// README/task allowed either "an epd-or-SAN-prefix lookup"; this pipeline
// picks SAN-prefix because it needs nothing beyond the SAN tokens
// extract.mjs already produces textually, for the book AND for real games
// alike, which is what keeps a production month's book lookup O(1)-replay
// (no per-game board walk, unlike flutter's own openings.json build in
// scripts/build-openings.mts, which is EPD-keyed but only needs to replay
// ~3.8k short reference lines once, not hundreds of millions of real games).
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { cleanSan } from './extract.mjs';

const DEFAULT_OPENINGS_DIR = fileURLToPath(new URL('./data/openings/', import.meta.url));
const MOVE_NUM_RE = /^\d+\.+$/;

class TrieNode {
	constructor() {
		/** @type {Map<string, TrieNode>} */
		this.children = new Map();
	}
}

/**
 * Build the book trie from every *.tsv in `dir`. Each row's `pgn` column
 * (e.g. "1. e4 e5 2. Nf3 Nc6") contributes one path from the root; every
 * intermediate node along that path is automatically a valid "still in
 * book" position, at no extra cost, which is the whole reason a trie is the
 * right shape here instead of a flat set of terminal lines.
 */
export function buildBook(dir = DEFAULT_OPENINGS_DIR) {
	const root = new TrieNode();
	let lines = 0;
	for (const file of readdirSync(dir).sort()) {
		if (!file.endsWith('.tsv')) continue;
		const text = readFileSync(dir + file, 'utf8');
		const rows = text.split('\n');
		for (let i = 1; i < rows.length; i++) {
			// eco \t name \t pgn
			const row = rows[i];
			if (!row.trim()) continue;
			const tab1 = row.indexOf('\t');
			const tab2 = row.indexOf('\t', tab1 + 1);
			if (tab1 < 0 || tab2 < 0) continue;
			const pgn = row.slice(tab2 + 1).trim();
			if (!pgn) continue;
			let node = root;
			for (const tok of pgn.split(/\s+/)) {
				if (MOVE_NUM_RE.test(tok)) continue;
				const san = cleanSan(tok);
				let next = node.children.get(san);
				if (!next) {
					next = new TrieNode();
					node.children.set(san, next);
				}
				node = next;
			}
			lines++;
		}
	}
	return { root, lines };
}

/**
 * Ply (1-indexed) of the first move that leaves the book, given a game's
 * clean SAN move list. Returns null if the game stayed in book for its
 * whole length (or exhausted the deepest matching reference line without
 * diverging from it — the book simply runs out of coverage there, which is
 * not the same claim as "this player deviated").
 *
 * @param {{ root: TrieNode }} book
 * @param {string[]} sanMoves already-clean SAN (extract.mjs's `moves[i].san`)
 * @param {number} cap safety ceiling on how many plies to check
 */
export function plyOfFirstDeviation(book, sanMoves, cap = 60) {
	let node = book.root;
	const limit = Math.min(sanMoves.length, cap);
	for (let i = 0; i < limit; i++) {
		const next = node.children.get(sanMoves[i]);
		if (!next) return i + 1;
		node = next;
	}
	return null;
}
