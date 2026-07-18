// M4 parity fixtures: run the brain's pure functions on representative
// inputs and record {fn, args, expected} — the behavioral contract between
// the web TS (source of truth, imported directly here) and every consumer
// of the built bundle (node replay: scripts/replay-fixtures.mjs; on-device
// replay: flutter/integration_test/brain_parity_test.dart).
//
// Engine lines are part of the INPUTS, so fixtures are engine-independent —
// they pin the logic, not the search.
//
//   npx tsx scripts/emit-golden-fixtures.mts
//
// Conventions: "__OMIT__" in args marshals as an omitted (undefined) arg;
// keys listed in `ignore` are skipped during comparison at any depth
// (clock-derived fields). Numbers compare with 1e-6 tolerance.

import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
	winChance,
	whitePovWinChance,
	gradeMove,
	backfillGrade
} from '../src/lib/engine/insights';
import { getSan, getFenAfter, getSanLine, getNumberedSanLine, isCapture } from '../src/lib/engine/chess';
import { shapedBotMove, shapedSearchDepth, shapedLabelFor } from '../src/lib/bot';
import { avoidRepetition } from '../src/lib/repetition';
import { moveAccuracy, gameAccuracy, labelCounts } from '../src/lib/gameStore';
import { itemDataFromStoredMove, recordResult } from '../src/lib/practice';
import { personaById } from '../src/lib/bots';
import { threatProbeFen, judgeThreat } from '../src/lib/engine/threats';
import { controlSquares } from '../src/lib/brain-entry';
import type { EngineMove } from '../src/lib/engine/stockfish';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

interface Fixture {
	fn: string;
	args: unknown[];
	expected: unknown;
	ignore?: string[];
}
const fixtures: Fixture[] = [];
function record(fn: string, args: unknown[], expected: unknown, ignore?: string[]) {
	fixtures.push({ fn, args, expected, ...(ignore ? { ignore } : {}) });
}

// ---- winChance family ----
for (const [e, m] of [
	[0.35, null],
	[-3, null],
	[0, null],
	[null, 3],
	[null, -2],
	[15, null],
	[null, null]
] as [number | null, number | null][]) {
	record('winChance', [e, m], winChance(e, m));
}
record('whitePovWinChance', ['w', 0.35, null], whitePovWinChance('w', 0.35, null));
record('whitePovWinChance', ['b', -0.35, null], whitePovWinChance('b', -0.35, null));
record('whitePovWinChance', ['b', null, 2], whitePovWinChance('b', null, 2));

// ---- SAN helpers ----
record('getSan', [START, 'g1f3'], getSan(START, 'g1f3'));
record('getFenAfter', [START, 'e2e4'], getFenAfter(START, 'e2e4'));
const ruyPv = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5'];
record('getSanLine', [START, ruyPv], getSanLine(START, ruyPv));
record('getNumberedSanLine', [START, ruyPv, 12], getNumberedSanLine(START, ruyPv, 12));
record('isCapture', [START, 'e2e4'], isCapture(START, 'e2e4'));

// ---- grading: an even move and a blunder, graded then backfilled ----
const preLines: EngineMove[] = [
	{ pv: ['e2e4', 'e7e5', 'g1f3'], score: 0.35, mate: null, depth: 18, multipv: 1 },
	{ pv: ['d2d4', 'd7d5'], score: 0.3, mate: null, depth: 18, multipv: 2 },
	{ pv: ['g1f3', 'g8f6'], score: 0.25, mate: null, depth: 18, multipv: 3 },
	{ pv: ['c2c4'], score: 0.2, mate: null, depth: 18, multipv: 4 },
	{ pv: ['g2g4'], score: -0.9, mate: null, depth: 18, multipv: 5 }
];
const gradeGood = gradeMove(1, START, 'e4', 'e2e4', 'w', preLines);
record('gradeMove', [1, START, 'e4', 'e2e4', 'w', preLines], gradeGood);
const childGood: EngineMove[] = [
	{ pv: ['e7e5', 'g1f3', 'b8c6'], score: -0.3, mate: null, depth: 16, multipv: 1 }
];
record('backfillGrade', [gradeGood, childGood], backfillGrade(gradeGood, childGood));

// the blunder: 1.g4?? — child (black to move) wins with a big swing
const gradeBad = gradeMove(1, START, 'g4', 'g2g4', 'w', preLines);
const childBad: EngineMove[] = [
	{ pv: ['e7e5', 'f2f3', 'd8h4'], score: 2.8, mate: null, depth: 16, multipv: 1 }
];
record('backfillGrade', [gradeBad, childBad], backfillGrade(gradeBad, childBad));

// ---- the shaped bot (seeded → deterministic) ----
const botLines: EngineMove[] = [
	{ pv: ['d4d8'], score: 8.5, mate: null, depth: 12, multipv: 1 },
	...['a2a3', 'b2b3', 'c2c3', 'h2h3', 'g2g3', 'f2f3', 'a2a4', 'b2b4', 'c2c4', 'h2h4', 'g2g4'].map(
		(m, i) => ({
			pv: [m],
			score: 0.5 - i * 0.1,
			mate: null,
			depth: 12,
			multipv: i + 2
		})
	)
];
for (const seed of ['fix1', 'fix2', 'fix3']) {
	record(
		'shapedBotMove',
		[botLines, 600, { scan: true }, seed, START],
		shapedBotMove(botLines, 600, { scan: true }, seed, START)
	);
}
for (const label of [600, 900, 1200, 1500]) {
	record('shapedSearchDepth', [label], shapedSearchDepth(label));
}
record('shapedLabelFor', [1140], shapedLabelFor(1140));
record('avoidRepetition', ['d4d8', [START], botLines], avoidRepetition('d4d8', [START], botLines));

// ---- stored-game math ----
const storedMoves = [
	{ ply: 1, san: 'e4', uci: 'e2e4', color: 'w', fenBefore: START, fenAfter: '', evalPawns: 0.3, mate: null, pctBest: 100, wcDrop: 0, label: 'best' },
	{ ply: 2, san: 'e5', uci: 'e7e5', color: 'b', fenBefore: '', fenAfter: '', evalPawns: -0.3, mate: null, pctBest: 95, wcDrop: 1.2, label: 'excellent' },
	{ ply: 3, san: 'g4', uci: 'g2g4', color: 'w', fenBefore: '', fenAfter: '', evalPawns: -2.5, mate: null, pctBest: 4, wcDrop: 24, label: 'blunder' }
] as Parameters<typeof gameAccuracy>[0];
record('moveAccuracy', [0], moveAccuracy(0));
record('moveAccuracy', [25], moveAccuracy(25));
record('gameAccuracy', [storedMoves, 'w'], gameAccuracy(storedMoves, 'w'));
record('gameAccuracy', [storedMoves, 'b'], gameAccuracy(storedMoves, 'b'));
record('labelCounts', [storedMoves, 'w'], labelCounts(storedMoves, 'w'));

// ---- practice (clock-derived fields ignored) ----
const puzzleSource = {
	ply: 6, san: 'g6', uci: 'g7g6', color: 'b',
	fenBefore: 'r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3',
	fenAfter: '', evalPawns: -3.0, mate: null, pctBest: 5, wcDrop: 30, depth: 22,
	label: 'blunder', bestSan: 'Qe7', bestUci: 'd8e7'
} as Parameters<typeof itemDataFromStoredMove>[0];
record('itemDataFromStoredMove', [puzzleSource, 'd1h5'], itemDataFromStoredMove(puzzleSource, 'd1h5'));

const item = {
	...itemDataFromStoredMove(puzzleSource, 'd1h5')!,
	id: 'fix', createdAt: '2026-01-01T00:00:00Z', box: 1,
	dueAt: '2026-01-01T00:00:00Z', attempts: 2, correct: 1
};
record('recordResult', [[item], 'fix', true, false], recordResult([item], 'fix', true, false), ['dueAt']);
record('recordResult', [[item], 'fix', false, false], recordResult([item], 'fix', false, false), ['dueAt']);

// ---- roster ----
record('personaById', ['square-900'], personaById('square-900'));
record('personaById', ['fish-2000'], personaById('fish-2000'));

// ---- board overlays ----
// after 1.e4 e5 2.Nf3: black to move; the probe flips to white-to-move
const italianish = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2';
record('threatProbeFen', [italianish], threatProbeFen(italianish));
// the flipped side's best is Nxe5 — a clean pawn grab, so a real threat
const probeLine = { pv: ['f3e5'], mate: null };
record('judgeThreat', [italianish, probeLine], judgeThreat(italianish, probeLine));
// a quiet best is no threat at all
record('judgeThreat', [italianish, { pv: ['b1c3'], mate: null }],
	judgeThreat(italianish, { pv: ['b1c3'], mate: null }));
record('controlSquares', [italianish], controlSquares(italianish));
// in check: the branch where the turn-flip hands the checker a king capture,
// and where the checked side is cut back to its evasions. Without this the
// whole in-check path replays green even if it regresses.
const inCheck = '4k3/8/8/8/7q/8/8/4K2R w K - 0 1';
record('controlSquares', [inCheck], controlSquares(inCheck));

const out = resolve(dirname(fileURLToPath(import.meta.url)), '../flutter/assets/brain-fixtures.json');
writeFileSync(out, JSON.stringify({ version: 1, fixtures }, null, 1));
console.log(`${fixtures.length} fixtures → ${out}`);
