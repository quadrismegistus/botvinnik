// SquareFish in-game chat: the bot explains its decisions in lichess chat.
// Two parts per message: a human-sounding reaction + a terse technical bracket
// showing the shaping internals. Fits within lichess's 140-char limit.
//
// Chat budget: ~8 messages per game (lichess caps at 12; save room for
// greeting/goodbye). Only chat-worthy moments fire — tactical misses,
// missed opponent blunders, conversion fumbles. Quiet mush is silent.

import type { DecisionTrace } from '../../src/lib/bot';

// ---- selection: is this moment worth a chat message? ----

export interface ChatState {
	budget: number;
	quietBudget: number;
	lastChatPly: number; // half-move number of the last chat
	ply: number;
}

export function newChatState(): ChatState {
	return { budget: 8, quietBudget: 2, lastChatPly: -10, ply: 0 };
}

const COOLDOWN_PLIES = 6; // at least 3 full moves between chats

export function isChatWorthy(trace: DecisionTrace, state: ChatState): boolean {
	if (state.budget <= 0) return false;
	if (state.ply - state.lastChatPly < COOLDOWN_PLIES) return false;

	if (trace.branch === 'tactical-miss') return true;
	if (trace.branch === 'conversion' && trace.playedMove !== trace.bestMove) return true;
	if (trace.branch === 'quiet' && trace.bestWin - trace.playedWin >= 12 && state.quietBudget > 0) return true;
	return false;
}

// ---- formatting: the 140-char message ----

const MISS_LINES = [
	'Oof, how did I miss that?!',
	"I can't believe I didn't see that.",
	'Walked right into it.',
	'That was right there and I missed it!',
	"Ahh, I'm kicking myself.",
	'Wow, completely blind to that.',
	'How did I not see that?!',
	'Nope, totally missed it.',
];

const MISS_GRAB_LINES = [
	'Wait, that was just hanging??',
	'That was FREE and I missed it?!',
	"I literally didn't see it sitting there.",
	'Right in front of me the whole time!',
];

const MISS_MATE_LINES = [
	"That was CHECKMATE?! I need to look at checks first.",
	"Wait... that's mate?!",
	'Mate in how many?! I had no idea.',
];

const QUIET_LINES = [
	"Hmm, not sure about that one.",
	'I had a feeling there was something better.',
	'Felt ok but maybe not.',
	'This position is tricky.',
];

const CONVERSION_LINES = [
	"...I had that won, didn't I.",
	'How do I keep doing this?!',
	'I need to learn how to finish games.',
	'Winning to... whatever this is.',
];

const OPENING_LINES = [
	"I have my own system.",
	"Don't ask me why, it felt right.",
	"Is this an opening? I'm making it one.",
	'a4 energy.',
];

function pickLine(lines: string[], ply: number): string {
	return lines[ply % lines.length];
}

function winPct(w: number): string {
	return `w${Math.round(w)}%`;
}

function formatBracket(t: DecisionTrace): string {
	const played = `${t.playedMove} (${winPct(t.playedWin)})`;
	const best = `${t.bestMove} (${winPct(t.bestWin)})`;

	if (t.branch === 'tactical-miss' && t.effectiveP !== undefined && t.roll !== undefined) {
		const dc = Math.round(t.effectiveP * 10);
		const roll = Math.round(t.roll * 10);
		return `[DC ${dc}, rolled ${roll} — played ${played} vs ${best}]`;
	}
	return `[played ${played} vs ${best}]`;
}

function humanPart(t: DecisionTrace, ply: number): string {
	if (t.branch === 'tactical-miss') {
		if (t.visKind === 'mate-soon') return pickLine(MISS_MATE_LINES, ply);
		if (t.visKind === 'grab' || t.visKind === 'recapture') return pickLine(MISS_GRAB_LINES, ply);
		return pickLine(MISS_LINES, ply);
	}
	if (t.branch === 'conversion') return pickLine(CONVERSION_LINES, ply);
	if (t.branch === 'quiet') {
		if (t.openingDamp !== undefined && t.openingDamp < 0.6) return pickLine(OPENING_LINES, ply);
		return pickLine(QUIET_LINES, ply);
	}
	return '';
}

export function formatChat(trace: DecisionTrace, ply: number): string {
	const human = humanPart(trace, ply);
	const bracket = formatBracket(trace);
	const full = `${human} ${bracket}`;
	// hard cap at 140 chars (lichess limit) — truncate the human part if needed
	if (full.length <= 140) return full;
	const maxHuman = 140 - bracket.length - 2;
	if (maxHuman < 10) return bracket.slice(0, 140);
	return `${human.slice(0, maxHuman)}.. ${bracket}`;
}
