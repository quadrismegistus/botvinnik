// Stratified sample from the lichess puzzle dump (reservoir per rating band,
// reliable puzzles only). Streams the ~900MB CSV through zstd without ever
// holding it.
//
//   npx tsx scripts/puzzle-rating/sample.mts [--per-band 125] \
//       [--dump data/puzzles/lichess_db_puzzle.csv.zst] [--out data/puzzles/sample.json]

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
function opt(name: string, dflt: string): string {
	const i = argv.indexOf(`--${name}`);
	return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt;
}
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const DUMP = resolve(ROOT, opt('dump', 'data/puzzles/lichess_db_puzzle.csv.zst'));
const OUT = resolve(ROOT, opt('out', 'data/puzzles/sample.json'));
const PER_BAND = Number(opt('per-band', '125'));
const BAND = 200; // rating band width
const LO = 400;
const HI = 2800;

interface Puzzle {
	id: string;
	fen: string;
	moves: string[];
	rating: number;
	themes: string[];
}

const bands = new Map<number, { seen: number; keep: Puzzle[] }>();
for (let b = LO; b < HI; b += BAND) bands.set(b, { seen: 0, keep: [] });

const zstd = spawn('zstd', ['-dc', DUMP]);
const rl = createInterface({ input: zstd.stdout });
let header = true;
let total = 0;

rl.on('line', (line) => {
	if (header) {
		header = false;
		return;
	}
	// PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags
	const cols = line.split(',');
	if (cols.length < 8) return;
	const rating = Number(cols[3]);
	const rd = Number(cols[4]);
	const plays = Number(cols[6]);
	if (rd >= 100 || plays < 200) return; // reliable ratings only
	const band = Math.floor((rating - LO) / BAND) * BAND + LO;
	const slot = bands.get(band);
	if (!slot) return;
	total++;
	slot.seen++;
	const p: Puzzle = {
		id: cols[0],
		fen: cols[1],
		moves: cols[2].split(' '),
		rating,
		themes: cols[7].split(' ')
	};
	// reservoir sampling: uniform without a second pass
	if (slot.keep.length < PER_BAND) slot.keep.push(p);
	else {
		const j = Math.floor(Math.random() * slot.seen);
		if (j < PER_BAND) slot.keep[j] = p;
	}
});

rl.on('close', () => {
	const sample = [...bands.values()].flatMap((s) => s.keep);
	sample.sort((a, b) => a.rating - b.rating);
	writeFileSync(OUT, JSON.stringify(sample) + '\n');
	console.log(`${sample.length} puzzles sampled from ${total} eligible → ${OUT}`);
	for (const [b, s] of bands) console.log(`  ${b}-${b + BAND}: ${s.keep.length} of ${s.seen}`);
});
