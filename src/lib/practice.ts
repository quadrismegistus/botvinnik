// Practice list: positions where a mistake was played, stored in localStorage,
// scheduled with simple Leitner boxes.

import { winChance, type MoveLabel } from './engine/insights';
import { MOTIF_TAGS_VERSION, motifTags } from './engine/explain';
import type { StoredMove } from './gameStore';

export interface AttemptResult {
	san: string;
	pass: boolean;
	label?: MoveLabel; // same classification the insight card shows
	drop: number;
	evalPawns: number | null;
	mate: number | null;
	refutationUci?: string | null; // opponent's best reply to a failed attempt
	refutationSan?: string | null;
	playedIssue?: string; // fact-based explanation of what went wrong
	bestPoint?: string; // what the best move achieves — show only after reveal
	playedPoint?: string; // why a passing move is good
	lineStory?: string; // material narrative of the refutation line
	evidence?: { fen: string; ucis: string[] }; // line behind the issue/story
}

export interface PracticeItem {
	id: string; // the fen — doubles as the dedupe key
	fen: string; // position before the mistake; side to move must find a good move
	playedSan: string;
	playedUci: string;
	bestSan: string;
	bestUci: string;
	bestPv?: string[]; // best move's full line, for explanations
	setupUci?: string; // opponent's move that led into this position, to replay for context
	motifs?: string[]; // named facts on the best line (Motif values), for tagging/filtering
	tagV?: number; // MOTIF_TAGS_VERSION the motifs were computed with
	evalBestPawns: number; // mover's perspective
	mateBest: number | null;
	wcBest: number; // win% of the best move at collect time
	drop: number; // win% lost by the played move
	depth: number;
	createdAt: string;
	box: number; // Leitner box 0..4
	dueAt: string;
	attempts: number;
	correct: number;
	lastResult?: 'pass' | 'fail';
}

const KEY = 'botvinnik-practice-v1';
// box -> days until next review after landing in that box
const INTERVAL_DAYS = [0.007, 1, 3, 7, 21]; // box 0 ≈ 10 minutes

function hasStorage(): boolean {
	return typeof localStorage !== 'undefined';
}

export function loadItems(): PracticeItem[] {
	if (!hasStorage()) return [];
	let items: PracticeItem[];
	try {
		items = JSON.parse(localStorage.getItem(KEY) ?? '[]');
	} catch {
		return [];
	}
	// lazy backfill: items whose motifs predate the current tagger (or motif
	// tagging entirely) get recomputed once and persisted
	let changed = false;
	for (const item of items) {
		if (!item.motifs || (item.tagV ?? 1) < MOTIF_TAGS_VERSION) {
			item.motifs = motifTags(item.fen, item.bestUci, item.bestPv ?? [item.bestUci], item.mateBest);
			item.tagV = MOTIF_TAGS_VERSION;
			changed = true;
		}
	}
	if (changed) save(items);
	return items;
}

function save(items: PracticeItem[]) {
	if (hasStorage()) localStorage.setItem(KEY, JSON.stringify(items));
}

// replace the stored list wholesale (used by backup import)
export function saveItems(items: PracticeItem[]) {
	save(items);
}

// Build a practice item from a reviewed game move. Returns null unless the move
// has a best move, a starting position, and actually cost win chance. The stored
// eval is mover-perspective AND after the played move, so the best move's win
// chance is the played win chance plus what the played move dropped; we invert
// the lichess sigmoid to recover a comparable eval for practice grading.
export function itemDataFromStoredMove(
	move: StoredMove,
	setupUci?: string
): Omit<PracticeItem, 'id' | 'createdAt' | 'box' | 'dueAt' | 'attempts' | 'correct'> | null {
	if (!move.bestSan || !move.bestUci || !move.fenBefore || move.wcDrop <= 0) return null;
	const wcBest = Math.max(0, Math.min(100, winChance(move.evalPawns, move.mate) + move.wcDrop));
	const w = Math.max(0.01, Math.min(0.99, wcBest / 100));
	const evalBestPawns = Math.max(-15, Math.min(15, Math.log(w / (1 - w)) / 0.00368208 / 100));
	return {
		fen: move.fenBefore,
		playedSan: move.san,
		playedUci: move.uci,
		bestSan: move.bestSan,
		bestUci: move.bestUci,
		bestPv: [move.bestUci],
		setupUci: setupUci ?? enPassantSetup(move.fenBefore) ?? undefined,
		motifs: motifTags(move.fenBefore, move.bestUci, [move.bestUci], null),
		evalBestPawns,
		mateBest: null,
		wcBest,
		drop: move.wcDrop,
		depth: 22
	};
}

// The opponent's last move to replay for context. Prefer the stored setup move;
// otherwise, when the position has an en-passant target, the double pawn push is
// fully determined by that square — reconstruct it so en-passant puzzles (where
// the capture is unknowable from a static board) always show what just happened.
export function puzzleSetupMove(item: PracticeItem): string | null {
	return item.setupUci ?? enPassantSetup(item.fen);
}

export function enPassantSetup(fen: string): string | null {
	const ep = fen.split(' ')[3];
	if (!ep || ep === '-' || ep.length < 2) return null;
	const file = ep[0];
	if (ep[1] === '6') return `${file}7${file}5`; // Black just pushed a pawn two squares
	if (ep[1] === '3') return `${file}2${file}4`; // White just pushed a pawn two squares
	return null;
}

export function addItem(
	items: PracticeItem[],
	data: Omit<PracticeItem, 'id' | 'createdAt' | 'box' | 'dueAt' | 'attempts' | 'correct'>
): PracticeItem[] | null {
	if (items.some((i) => i.fen === data.fen)) return null;
	const now = new Date();
	const item: PracticeItem = {
		...data,
		id: data.fen,
		createdAt: now.toISOString(),
		box: 0,
		dueAt: now.toISOString(), // due immediately
		attempts: 0,
		correct: 0
	};
	const next = [...items, item];
	save(next);
	return next;
}

export function removeItem(items: PracticeItem[], id: string): PracticeItem[] {
	const next = items.filter((i) => i.id !== id);
	save(next);
	return next;
}

export function dueCount(items: PracticeItem[], now: number = Date.now()): number {
	return items.filter((i) => Date.parse(i.dueAt) <= now).length;
}

export type Difficulty = 'easy' | 'medium' | 'hard';
const TACTICAL_MOTIFS = [
	'mate',
	'back-rank mate',
	'smothered mate',
	'free capture',
	'material',
	'fork',
	'pin',
	'skewer',
	'promotion'
];

// Difficulty FOR THIS PLAYER: grounded in their own attempt history once there
// is any, falling back to position features (a bigger blunder or a concrete
// tactical motif is more findable) for fresh items. Drives the list badges and
// the optional ease-in ordering.
export function puzzleDifficulty(item: PracticeItem): Difficulty {
	if (item.attempts >= 2) {
		const rate = item.correct / item.attempts;
		if (item.lastResult === 'fail' && rate < 0.5) return 'hard';
		if (rate >= 0.75 || item.box >= 3) return 'easy';
		return 'medium';
	}
	if (item.box >= 3) return 'easy';
	const tactical = item.motifs?.some((m) => TACTICAL_MOTIFS.includes(m)) ?? false;
	if (item.drop >= 25 || (tactical && item.drop >= 12)) return 'easy';
	if (item.drop < 10 && !tactical) return 'hard';
	return 'medium';
}

export interface MasteryStats {
	mastered: number; // reached box ≥3 (survived a few cold passes)
	learning: number; // attempted but not yet mastered
	fresh: number; // never attempted
	total: number;
}
export function masteryStats(items: PracticeItem[]): MasteryStats {
	let mastered = 0,
		learning = 0,
		fresh = 0;
	for (const i of items) {
		if (i.attempts === 0) fresh++;
		else if (i.box >= 3) mastered++;
		else learning++;
	}
	return { mastered, learning, fresh, total: items.length };
}

// Pick a due item at random, weighted toward the more overdue, so the
// spaced-repetition priority still holds but you don't replay the exact same
// order every session. Falls back to the soonest-due upcoming item when
// nothing is due yet.
export function nextItem(
	items: PracticeItem[],
	excludeId?: string,
	now: number = Date.now(),
	motif?: string,
	rand: () => number = Math.random,
	easyFirst = false
): PracticeItem | null {
	let pool = items.filter((i) => i.id !== excludeId);
	if (motif) pool = pool.filter((i) => i.motifs?.includes(motif));
	if (pool.length === 0) return null;

	const due = pool.filter((i) => Date.parse(i.dueAt) <= now);
	if (due.length === 0) {
		// nothing due — just serve the one that comes up soonest
		return pool.reduce((a, b) => (Date.parse(a.dueAt) <= Date.parse(b.dueAt) ? a : b));
	}

	// weight = minutes overdue + 1, so every due item has a real chance but the
	// long-overdue ones surface more often; ease-in additionally tilts toward the
	// easier ones (they still all appear — hard ones just come up less early)
	const weights = due.map((i) => {
		let w = Math.max(1, (now - Date.parse(i.dueAt)) / 60_000 + 1);
		if (easyFirst) {
			const d = puzzleDifficulty(i);
			w *= d === 'easy' ? 3 : d === 'hard' ? 0.5 : 1;
		}
		return w;
	});
	const total = weights.reduce((a, b) => a + b, 0);
	let r = rand() * total;
	for (let k = 0; k < due.length; k++) {
		r -= weights[k];
		if (r <= 0) return due[k];
	}
	return due[due.length - 1];
}

export function recordResult(
	items: PracticeItem[],
	id: string,
	pass: boolean,
	hinted = false
): PracticeItem[] {
	const next = items.map((i) => {
		if (i.id !== id) return i;
		// a hinted pass holds the box (still counts the attempt); a cold pass
		// promotes, and a failure always resets to box 0
		const box = pass ? (hinted ? i.box : Math.min(i.box + 1, INTERVAL_DAYS.length - 1)) : 0;
		const dueAt = new Date(Date.now() + INTERVAL_DAYS[box] * 86_400_000).toISOString();
		return {
			...i,
			box,
			dueAt,
			attempts: i.attempts + 1,
			correct: i.correct + (pass ? 1 : 0),
			lastResult: (pass ? 'pass' : 'fail') as 'pass' | 'fail'
		};
	});
	save(next);
	return next;
}
