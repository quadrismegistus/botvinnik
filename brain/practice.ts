// Practice list: positions where a mistake was played, stored in localStorage,
// scheduled with simple Leitner boxes.

import { Chess } from 'chess.js';
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
	id: string; // epdKey(fen) — the POSITION is the dedupe key (#286)
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
	/** How many times this mistake has been collected — real games that walked
	 *  into this position and lost win chance here, NOT drill attempts (#286).
	 *  Absent means 1: every item written before the counter existed. */
	seenCount?: number;
	/** When the mistake last recurred (a bump of seenCount), ISO. */
	lastSeenAt?: string;
	/** The seenKeys (game ids) whose bulk seeding already counted here. The
	 *  background grader seeds BEFORE it saves — deliberately, so a crash
	 *  re-grades rather than losing blunders — which makes re-seeding the same
	 *  game routine, and without this list every redo would inflate the count.
	 *  Live collection passes no key and always counts. */
	seenIn?: string[];
}

/** The dedupe identity of a position: the first four FEN fields, with the
 *  en-passant square kept only when a capture can actually use it. The full
 *  fen splits the same mistake across games — the halfmove clock and the
 *  FULLMOVE NUMBER are in it, so the trap you walk into on move 12 and again
 *  on move 14 was two items (#286). The ep square needs the legality check
 *  because the two fen writers disagree: chess.js records the target after
 *  any double push, dartchess only when capturable — one position, two
 *  spellings. When ep is genuinely live it stays in the key: the capture
 *  changes the answer, so it is a different puzzle. */
export function epdKey(fen: string): string {
	const parts = fen.split(' ');
	if (parts.length < 4) return fen; // not a fen; leave the key alone
	const four = parts.slice(0, 4);
	if (four[3] !== '-') {
		try {
			const board = new Chess(fen);
			if (!board.moves({ verbose: true }).some((m) => m.flags.includes('e'))) {
				four[3] = '-';
			}
		} catch {
			// unparseable: keep the recorded square rather than invent a merge
		}
	}
	return four.join(' ');
}

/** Bulk form for the bridge: one call, one marshal (see addItems). */
export function epdKeys(fens: string[]): string[] {
	return fens.map(epdKey);
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
	// A puzzle whose answer is the move you played teaches nothing, and it is
	// worse than useless: checkAttempt short-circuits to a PASS when the played
	// move equals the stored bestUci, so the drill asks you to correct a mistake
	// and then accepts that mistake as the correction.
	//
	// It happens because a grade's `bestEval` and its `evalPawns` can come from
	// two different searches — the pre-move lines and the deeper search of the
	// position the move created — so the engine's own top move can be scored as
	// having lost a few points. Refusal mode fixed that for the case it decides
	// (#242); the post-commit path deliberately keeps the deeper number, which
	// is the right basis for a grade and can still produce a small drop on a
	// best move. Found in a real queue: 1 item in 677, `played Qe2 / best Qe2`,
	// drop 6.6%.
	if (move.bestUci === move.uci) return null;
	// The grade's own line, when the writer stored one (#287) — same search as
	// bestUci, so the tags always describe the line the drill shows. A line
	// that disagrees with bestUci is discarded rather than trusted, the same
	// defence lichessImport applies to its variations.
	const bestPv =
		move.bestPv && move.bestPv[0] === move.bestUci ? move.bestPv : [move.bestUci];
	const wcBest = Math.max(0, Math.min(100, winChance(move.evalPawns, move.mate) + move.wcDrop));
	const w = Math.max(0.01, Math.min(0.99, wcBest / 100));
	const evalBestPawns = Math.max(-15, Math.min(15, Math.log(w / (1 - w)) / 0.00368208 / 100));
	return {
		fen: move.fenBefore,
		playedSan: move.san,
		playedUci: move.uci,
		bestSan: move.bestSan,
		bestUci: move.bestUci,
		bestPv,
		setupUci: setupUci ?? enPassantSetup(move.fenBefore) ?? undefined,
		// the REAL mate distance, not null (#283). The grade has always carried
		// it and _storedMoveOf used to drop it, so a quiet move that forces mate
		// reached the tagger indistinguishable from an ordinary quiet move — and
		// got filed under whatever positional fact happened to be true of it,
		// which the tier-1 hint then said out loud on a mating puzzle.
		motifs: motifTags(move.fenBefore, move.bestUci, bestPv, move.bestMate ?? null),
		evalBestPawns,
		mateBest: move.bestMate ?? null,
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

/** One more occurrence of an already-collected mistake. Returns the new list,
 *  or null when [seenKey] already counted here — the bulk paths' redo guard.
 *  A bump touches the COUNT, never the schedule: recurring in a game does not
 *  make the drill due sooner, the Leitner boxes own that. */
function bumpRepeat(
	items: PracticeItem[],
	at: number,
	seenKey?: string
): PracticeItem[] | null {
	const item = items[at];
	if (seenKey && (item.seenIn ?? []).includes(seenKey)) return null;
	const next = [...items];
	next[at] = {
		...item,
		seenCount: (item.seenCount ?? 1) + 1,
		lastSeenAt: new Date().toISOString(),
		...(seenKey ? { seenIn: [...(item.seenIn ?? []), seenKey] } : {})
	};
	return next;
}

export function addItem(
	items: PracticeItem[],
	data: Omit<PracticeItem, 'id' | 'createdAt' | 'box' | 'dueAt' | 'attempts' | 'correct'>
): PracticeItem[] | null {
	const key = epdKey(data.fen);
	const at = items.findIndex((i) => i.id === key);
	if (at >= 0) {
		// Live collection carries no seenKey: each call is one real occurrence
		// (one graded move, one refusal), so a repeat always counts (#286).
		const next = bumpRepeat(items, at);
		if (next) save(next);
		return next;
	}
	const now = new Date();
	const item: PracticeItem = {
		...data,
		id: key,
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

/**
 * Add many items in one pass — the bulk form of [addItem].
 *
 * Importing a season of lichess games seeds hundreds of puzzles at once, and
 * calling addItem per seed made the cost quadratic on the DART side: every call
 * marshals the whole growing collection into a JS expression string and decodes
 * the whole result back. Measured at 300 games (~1500 seeds): 986MB of
 * expression text and 493MB of writes, 9.3s on a desktop VM with no JS engine
 * running at all — a strict lower bound on what a phone would do.
 *
 * Same rules as addItem, applied in order: one item per POSITION, a repeat
 * bumping its counter (#286). [seenKeys] is parallel to [dataList] and names
 * the game each seed came from; a repeat is counted once per game, which is
 * what lets the background grader's crash-redo (it seeds BEFORE it saves, on
 * purpose) re-seed the same game without inflating the count. Seeds without a
 * key count every time, like addItem.
 *
 * Returns the new list, or null when NOTHING changed — no item added and no
 * counter moved — so a caller can skip the persist entirely.
 */
export function addItems(
	items: PracticeItem[],
	dataList: Omit<PracticeItem, 'id' | 'createdAt' | 'box' | 'dueAt' | 'attempts' | 'correct'>[],
	seenKeys?: (string | null)[]
): PracticeItem[] | null {
	const now = new Date().toISOString();
	let next = [...items];
	const at = new Map(next.map((i, n) => [i.id, n]));
	let changed = false;
	for (let n = 0; n < dataList.length; n++) {
		const data = dataList[n];
		const seenKey = seenKeys?.[n] ?? undefined;
		const key = epdKey(data.fen);
		const existing = at.get(key);
		if (existing !== undefined) {
			const bumped = bumpRepeat(next, existing, seenKey);
			if (bumped) {
				next = bumped;
				changed = true;
			}
			continue;
		}
		at.set(key, next.length);
		next.push({
			...data,
			id: key,
			createdAt: now,
			box: 0,
			dueAt: now, // due immediately
			attempts: 0,
			correct: 0,
			...(seenKey ? { seenIn: [seenKey] } : {})
		});
		changed = true;
	}
	if (!changed) return null;
	save(next);
	return next;
}

/**
 * One-time reshaping of a stored collection to the position key (#286): every
 * id becomes epdKey(fen), and the twins the full-fen key split apart merge
 * into one item. A merge keeps the least-learned schedule (lowest box,
 * earliest due), sums the history, and counts each old item as one occurrence
 * of the mistake — they were. The deeper grade's chess fields win; ties keep
 * the first seen. Returns null when the collection is already in shape, so
 * the caller can skip the persist — which is also what makes it safe to run
 * on every load.
 */
export function migratePracticeItems(items: PracticeItem[]): PracticeItem[] | null {
	let changed = false;
	const byKey = new Map<string, PracticeItem>();
	const order: string[] = [];
	for (const raw of items) {
		const key = epdKey(raw.fen);
		if (raw.id !== key) changed = true;
		const item = { ...raw, id: key };
		const prev = byKey.get(key);
		if (!prev) {
			byKey.set(key, item);
			order.push(key);
			continue;
		}
		changed = true;
		const base = item.depth > prev.depth ? item : prev;
		const seenIn = [...new Set([...(prev.seenIn ?? []), ...(item.seenIn ?? [])])];
		const lastSeen = [prev.lastSeenAt, item.lastSeenAt].filter(Boolean).sort().pop();
		byKey.set(key, {
			...base,
			box: Math.min(prev.box, item.box),
			dueAt: Date.parse(prev.dueAt) <= Date.parse(item.dueAt) ? prev.dueAt : item.dueAt,
			createdAt:
				Date.parse(prev.createdAt) <= Date.parse(item.createdAt)
					? prev.createdAt
					: item.createdAt,
			attempts: prev.attempts + item.attempts,
			correct: prev.correct + item.correct,
			seenCount: (prev.seenCount ?? 1) + (item.seenCount ?? 1),
			...(seenIn.length ? { seenIn } : {}),
			...(lastSeen ? { lastSeenAt: lastSeen } : {})
		});
	}
	if (!changed) return null;
	const next = order.map((k) => byKey.get(k)!);
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
