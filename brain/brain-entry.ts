// The "brain" bundle entry: everything the Flutter app calls from the pure-TS
// layer, re-exported under one global. Built by `npm run build:brain` (esbuild
// IIFE, --global-name=brain) into flutter/assets/brain.js and evaluated in an
// embedded JS engine (flutter_js / JavaScriptCore). Keep this file exports-only:
// anything imported here must stay free of DOM/Svelte/Worker/fetch/storage —
// the Flutter side supplies engine searches, persistence, and HTTP.
//
// BRAIN_VERSION: bump on any breaking change to a signature or shape crossing
// the Dart bridge; flutter/lib/brain/js_bridge.dart asserts it at boot so a
// stale bundled asset fails loudly instead of skewing silently.

export const BRAIN_VERSION = 1;

// ---- shaped bot + numeric recipe (move selection) ----
export {
	shapedBotMove,
	shapedSearchDepth,
	shapedLabelFor,
	shapedParams,
	shapedStrengthRange,
	selectBotMove,
	botDelay,
	BOT_MODEL
} from './bot';
export {
	botSpec,
	botRecipe,
	specToRecipe,
	parseSpec,
	samplerAlphaFor,
	setBotSubstrate,
	getBotSubstrate,
	botEloMin,
	botEloMax
} from './engine/botRecipe';
export { avoidRepetition } from './repetition';

// ---- roster ----
export { PERSONAS, availablePersonas, personaById, personaInternalElo, SCALE_OFFSET } from './bots';

// ---- grading ----
export { winChance, whitePovWinChance, gradeMove, backfillGrade } from './engine/insights';
export { CLASS, LABEL_ORDER } from './classifications';

// ---- explanations ----
export { explainMove, explainGoodMove, bestMovePoint, motifTags, MOTIF_TAGS_VERSION } from './engine/explain';

// ---- SAN / fen helpers (so Dart never re-implements chess.js rendering) ----
export { getSan, getSanLine, getNumberedSanLine, getFenAfter, isCapture } from './engine/chess';

// ---- board overlays ----
export { threatProbeFen, judgeThreat } from './engine/threats';
import { computeControl } from './engine/control';
/** computeControl returns a Map (JSON-hostile) — flatten for the bridge. */
export function controlSquares(fen: string): Record<string, 'w' | 'b'> {
	return Object.fromEntries(computeControl(fen));
}

// ---- practice (pure scheduling only — Dart persists the item array) ----
export {
	itemDataFromStoredMove,
	puzzleSetupMove,
	enPassantSetup,
	addItem,
	removeItem,
	dueCount,
	puzzleDifficulty,
	masteryStats,
	nextItem,
	recordResult
} from './practice';

// ---- stored-game math (pure parts of gameStore) ----
export { moveAccuracy, gameAccuracy, labelCounts, LABEL_VERSION } from './gameStore';
export { estimatePlayerElo } from './playerElo';
