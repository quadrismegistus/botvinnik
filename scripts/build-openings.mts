// Bake the opening-name table: lichess-org/chess-openings (the canonical
// ECO/name dataset, ~3.5k entries) → {epd: [eco, name]} asset. One-time
// fetch from raw.githubusercontent; rerun to refresh.
//
//   npx tsx scripts/build-openings.mts

import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Chess } from 'chess.js';

const OUT = resolve(
	dirname(fileURLToPath(import.meta.url)),
	'../flutter/assets/openings.json'
);

const files = ['a.tsv', 'b.tsv', 'c.tsv', 'd.tsv', 'e.tsv'];
const base = 'https://raw.githubusercontent.com/lichess-org/chess-openings/master/';

function epd(fen: string): string {
	return fen.split(' ').slice(0, 4).join(' ');
}

const table: Record<string, [string, string]> = {};
let rows = 0;
for (const f of files) {
	const res = await fetch(base + f);
	if (!res.ok) throw new Error(`${f}: http ${res.status}`);
	const text = await res.text();
	for (const line of text.split('\n').slice(1)) {
		const [eco, name, pgn] = line.split('\t');
		if (!eco || !name || !pgn) continue;
		const chess = new Chess();
		try {
			// pgn column is a movetext like "1. e4 e5 2. Nf3"
			for (const tok of pgn.split(/\s+/)) {
				if (/^\d+\.$/.test(tok) || tok === '') continue;
				chess.move(tok);
			}
		} catch {
			continue;
		}
		table[epd(chess.fen())] = [eco, name];
		rows++;
	}
}

const doc = JSON.stringify({ version: 1, openings: table });
writeFileSync(OUT, doc);
console.log(`${rows} openings → ${OUT}`);
