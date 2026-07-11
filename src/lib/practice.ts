// Practice list: positions where a mistake was played, stored in localStorage,
// scheduled with simple Leitner boxes.

import type { MoveLabel } from './engine/insights';

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
	try {
		return JSON.parse(localStorage.getItem(KEY) ?? '[]');
	} catch {
		return [];
	}
}

function save(items: PracticeItem[]) {
	if (hasStorage()) localStorage.setItem(KEY, JSON.stringify(items));
}

// replace the stored list wholesale (used by backup import)
export function saveItems(items: PracticeItem[]) {
	save(items);
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

// due items first (oldest due first), otherwise the soonest-due upcoming item
export function nextItem(
	items: PracticeItem[],
	excludeId?: string,
	now: number = Date.now()
): PracticeItem | null {
	const pool = items.filter((i) => i.id !== excludeId);
	if (pool.length === 0) return null;
	const due = pool.filter((i) => Date.parse(i.dueAt) <= now);
	const list = due.length > 0 ? due : pool;
	return list.reduce((a, b) => (Date.parse(a.dueAt) <= Date.parse(b.dueAt) ? a : b));
}

export function recordResult(items: PracticeItem[], id: string, pass: boolean): PracticeItem[] {
	const next = items.map((i) => {
		if (i.id !== id) return i;
		const box = pass ? Math.min(i.box + 1, INTERVAL_DAYS.length - 1) : 0;
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
