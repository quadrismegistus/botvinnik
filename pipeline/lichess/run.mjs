#!/usr/bin/env node
// CLI entry point: streams a lichess monthly dump through extract -> aggregate
// and writes the versioned peer-tables envelope (README).
//
//   node pipeline/lichess/run.mjs <dump.pgn.zst> --out out/peer-tables.json [--max-games N]
//
// Progress prints to stderr every 10k games streamed; the output goes to
// stdout-adjacent --out (default pipeline/lichess/out/peer-tables.json,
// gitignored — reviewed by hand, then copied to flutter/assets/peer-tables.json
// as a deliberate step, per the README).
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { streamGames } from './stream.mjs';
import { extractGame } from './extract.mjs';
import { Aggregator } from './aggregate.mjs';
import { buildBook } from './book.mjs';
import { loadBrain } from './loadBrain.mjs';

const DEFAULT_OUT = fileURLToPath(new URL('./out/peer-tables.json', import.meta.url));

export function parseArgs(argv) {
	const args = { input: null, out: DEFAULT_OUT, maxGames: null };
	const rest = [];
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--out') args.out = argv[++i];
		else if (a === '--max-games') args.maxGames = Number(argv[++i]);
		else rest.push(a);
	}
	if (!rest[0]) {
		throw new Error(
			'usage: node pipeline/lichess/run.mjs <dump.pgn.zst> --out out/peer-tables.json [--max-games N]'
		);
	}
	args.input = rest[0];
	return args;
}

export function sourceNameFrom(path) {
	return basename(path).replace(/\.pgn\.zst$/, '');
}

export async function run(argv, { brain = loadBrain(), book = buildBook() } = {}) {
	const args = parseArgs(argv);
	const agg = new Aggregator(brain, book);

	const t0 = Date.now();
	let streamed = 0;
	let parsed = 0;
	const skipped = {};

	for await (const raw of streamGames(args.input)) {
		streamed++;
		const rec = extractGame(raw);
		if (rec.skip) {
			skipped[rec.skip] = (skipped[rec.skip] ?? 0) + 1;
		} else {
			agg.addGame(rec);
			parsed++;
		}
		if (streamed % 10000 === 0) {
			const secs = ((Date.now() - t0) / 1000).toFixed(1);
			const mem = (process.memoryUsage().rss / 1e6).toFixed(0);
			console.error(`… ${streamed} streamed, ${parsed} parsed, ${secs}s, rss ${mem}MB`);
		}
		if (args.maxGames && streamed >= args.maxGames) break;
	}

	const envelope = agg.toEnvelope({
		source: sourceNameFrom(args.input),
		brainVersion: brain.BRAIN_VERSION,
		games: { streamed, parsed, skipped }
	});

	const outPath = resolve(args.out);
	mkdirSync(dirname(outPath), { recursive: true });
	writeFileSync(outPath, JSON.stringify(envelope, null, 2));

	const totalSecs = ((Date.now() - t0) / 1000).toFixed(1);
	console.error(
		`done: ${streamed} streamed, ${parsed} parsed, skipped ${JSON.stringify(skipped)}, ${totalSecs}s -> ${outPath}`
	);

	return { envelope, outPath, streamed, parsed, skipped };
}

// Only run as a CLI when invoked directly (`node run.mjs ...`), not when
// imported by the e2e test.
if (import.meta.url === `file://${process.argv[1]}`) {
	run(process.argv.slice(2)).catch((err) => {
		console.error(err);
		process.exit(1);
	});
}
