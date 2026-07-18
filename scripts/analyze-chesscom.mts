#!/usr/bin/env npx tsx
/**
 * Offline chess.com archive analyzer — phase 2 of the game-import roadmap.
 *
 * Downloads a player's monthly archives, analyzes every position with native
 * Stockfish (parallel workers, FEN-deduped within the run), grades moves with
 * the app's own import code, and writes a botvinnik backup JSON that the app's
 * "Import data" button merges in.
 *
 * Usage:
 *   npx tsx scripts/analyze-chesscom.mts <username> [options]
 *
 * Options:
 *   --months N        only the N most recent months (default: all)
 *   --max-games N     stop after N games (default: unlimited)
 *   --nodes N         Stockfish nodes per position (default 300000, ~d16-18)
 *   --workers N       parallel engine processes (default: cores - 2)
 *   --threshold N     win%-drop to collect as practice (default 15)
 *   --full N          keep full per-move data for the N newest games,
 *                     summary+PGN only for older ones (default 500)
 *   --practice-cap N  keep at most N practice items, newest first (default 1000)
 *   --engine PATH     stockfish binary (default: `stockfish` on PATH)
 *   --out FILE        output path (default data/chesscom-<user>-backup.json)
 *
 * Resumable: progress is checkpointed per month in <out>.state.json.
 */

import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { ccGameToAnalysed, fetchChesscomArchives, fetchChesscomMonth } from '../brain/chesscomCore';
import { analysedGameToStored, type PracticeCandidate } from '../brain/lichessImport';
import type { StoredGame } from '../brain/gameStore';

// ---------- args ----------
const args = process.argv.slice(2);
const username = args.find((a) => !a.startsWith('--'));
if (!username) {
	console.error('usage: npx tsx scripts/analyze-chesscom.mts <username> [--months N] ...');
	process.exit(1);
}
function opt(name: string, dflt: number): number {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? Number(args[i + 1]) : dflt;
}
function optStr(name: string, dflt: string): string {
	const i = args.indexOf(`--${name}`);
	return i >= 0 ? args[i + 1] : dflt;
}
const MONTHS = opt('months', Infinity);
const MAX_GAMES = opt('max-games', Infinity);
const NODES = opt('nodes', 300_000);
const WORKERS = opt('workers', Math.max(1, os.cpus().length - 2));
const THRESHOLD = opt('threshold', 15);
const FULL = opt('full', 500);
const PRACTICE_CAP = opt('practice-cap', 1000);
const ENGINE = optStr('engine', 'stockfish');
const OUT = optStr('out', `data/chesscom-${username.toLowerCase()}-backup.json`);
const STATE = `${OUT}.state.json`;

// ---------- engine pool ----------
interface EvalResult {
	cp?: number; // side-to-move perspective
	mate?: number;
	pv: string[];
}

class Engine {
	proc: ChildProcessWithoutNullStreams;
	busy = false;
	private buffer = '';
	private resolve: ((r: EvalResult) => void) | null = null;
	private last: EvalResult = { pv: [] };

	constructor() {
		this.proc = spawn(ENGINE);
		this.proc.stdout.on('data', (d) => this.onData(String(d)));
		this.proc.stdin.write('uci\nsetoption name Threads value 1\nsetoption name Hash value 64\nisready\n');
	}

	private onData(chunk: string) {
		this.buffer += chunk;
		const lines = this.buffer.split('\n');
		this.buffer = lines.pop() ?? '';
		for (const line of lines) {
			if (line.startsWith('info ') && line.includes(' pv ')) {
				const cp = line.match(/ score cp (-?\d+)/);
				const mate = line.match(/ score mate (-?\d+)/);
				const pv = line.split(' pv ')[1]?.trim().split(' ') ?? [];
				this.last = {
					cp: cp ? Number(cp[1]) : undefined,
					mate: mate ? Number(mate[1]) : undefined,
					pv
				};
			} else if (line.startsWith('bestmove')) {
				const r = this.resolve;
				this.resolve = null;
				this.busy = false;
				r?.(this.last);
			}
		}
	}

	analyze(fen: string): Promise<EvalResult> {
		this.busy = true;
		this.last = { pv: [] };
		return new Promise((resolve) => {
			this.resolve = resolve;
			this.proc.stdin.write(`position fen ${fen}\ngo nodes ${NODES}\n`);
		});
	}

	quit() {
		this.proc.stdin.write('quit\n');
	}
}

const engines = Array.from({ length: WORKERS }, () => new Engine());
const cache = new Map<string, Promise<EvalResult>>(); // normalized fen -> result
let searched = 0;
let cacheHits = 0;

function evalPosition(fen: string): Promise<EvalResult> {
	const key = fen.split(' ').slice(0, 4).join(' ');
	const hit = cache.get(key);
	if (hit) {
		cacheHits++;
		return hit;
	}
	const p = (async () => {
		// wait for a free engine
		let engine: Engine | undefined;
		while (!engine) {
			engine = engines.find((e) => !e.busy);
			if (!engine) await new Promise((r) => setTimeout(r, 5));
		}
		searched++;
		return engine.analyze(fen);
	})();
	cache.set(key, p);
	return p;
}

// ---------- main ----------
interface State {
	doneMonths: string[];
}

async function main() {
	mkdirSync(path.dirname(OUT), { recursive: true });
	const state: State = existsSync(STATE)
		? JSON.parse(readFileSync(STATE, 'utf8'))
		: { doneMonths: [] };
	const existing: { games: StoredGame[]; practice: unknown[] } = existsSync(OUT)
		? JSON.parse(readFileSync(OUT, 'utf8'))
		: { games: [], practice: [] };
	const games: StoredGame[] = existing.games;
	const gameIds = new Set(games.map((g) => g.id));
	const practice: (PracticeCandidate & Record<string, unknown>)[] =
		existing.practice as never[];
	const practiceFens = new Set(practice.map((p) => p.fen));

	const archives = await fetchChesscomArchives(username!); // newest first
	const months = archives.slice(0, MONTHS === Infinity ? undefined : MONTHS);
	console.log(`${username}: ${archives.length} months, analyzing ${months.length} (newest first)`);
	console.log(`engine: ${ENGINE} ×${WORKERS} workers, ${NODES} nodes/position\n`);

	let gamesDone = 0;
	const t0 = Date.now();

	for (const monthUrl of months) {
		const monthKey = monthUrl.split('/games/')[1];
		if (state.doneMonths.includes(monthKey)) {
			console.log(`${monthKey}: already done, skipping`);
			continue;
		}
		if (gamesDone >= MAX_GAMES) break;

		const ccGames = await fetchChesscomMonth(monthUrl); // newest first
		console.log(`${monthKey}: ${ccGames.length} games`);

		for (const cc of ccGames) {
			if (gamesDone >= MAX_GAMES) break;
			if (gameIds.has(`chesscom-${cc.uuid}`)) continue;
			const lichessShaped = await ccGameToAnalysed(cc, evalPosition);
			if (!lichessShaped) continue;
			const mapped = analysedGameToStored(lichessShaped, username!, 'chesscom');
			if (!mapped) continue;

			const stored = mapped.stored;
			if (games.length >= FULL) stored.moves = []; // summary + PGN only for the deep past
			games.push(stored);
			gameIds.add(stored.id);

			const now = new Date().toISOString();
			for (const p of mapped.practice) {
				if (p.drop < THRESHOLD || practiceFens.has(p.fen)) continue;
				practiceFens.add(p.fen);
				practice.push({
					...p,
					id: p.fen,
					createdAt: now,
					box: 0,
					dueAt: now,
					attempts: 0,
					correct: 0
				});
			}

			gamesDone++;
			if (gamesDone % 10 === 0) {
				const rate = gamesDone / ((Date.now() - t0) / 60000);
				console.log(
					`  ${gamesDone} games | ${searched} searched, ${cacheHits} cache hits | ${rate.toFixed(1)} games/min`
				);
			}
		}

		state.doneMonths.push(monthKey);
		writeBackup(games, practice);
		writeFileSync(STATE, JSON.stringify(state));
	}

	writeBackup(games, practice);
	console.log(
		`\ndone: ${games.length} games, ${practice.length} practice items ` +
			`(${searched} positions searched, ${cacheHits} dedupe hits = ${Math.round((cacheHits / Math.max(1, searched + cacheHits)) * 100)}%)`
	);
	console.log(`wrote ${OUT} — use "Import data" in the app to merge it in.`);
	engines.forEach((e) => e.quit());
	process.exit(0);
}

function writeBackup(games: StoredGame[], practice: unknown[]) {
	// months are processed newest-first, so the newest mistakes are at the FRONT
	const capped = (practice as { createdAt: string }[]).slice(0, PRACTICE_CAP);
	if (practice.length > capped.length) {
		console.log(`  (practice capped at ${PRACTICE_CAP} of ${practice.length})`);
	}
	writeFileSync(
		OUT,
		JSON.stringify({
			app: 'botvinnik',
			version: 1,
			exportedAt: new Date().toISOString(),
			practice: capped,
			games
		})
	);
}

main().catch((e) => {
	console.error(e);
	engines.forEach((eng) => eng.quit());
	process.exit(1);
});
