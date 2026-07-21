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
// The one bot family that needs no engine at all — it IS the engine, and a
// tiny synchronous one, so it can live behind the bridge. Imported only here,
// which is what keeps js-chess-engine off the Svelte app's EAGER path: the
// web reaches it through a dynamic import in jsce.ts instead, so it arrives
// as a lazy chunk and this module costs the web build nothing.
export { horizonMove } from './horizon';

// ---- roster ----
export { PERSONAS, availablePersonas, personaById, personaInternalElo, SCALE_OFFSET } from './bots';

// ---- grading ----
export { winChance, whitePovWinChance, gradeMove, backfillGrade } from './engine/insights';
export { CLASS, LABEL_ORDER } from './classifications';

// ---- explanations ----
export { explainMove, explainGoodMove, bestMovePoint, motifTags, MOTIF_TAGS_VERSION } from './engine/explain';

// ---- opening book × engine (the unified move table) ----
// The Book pane's rows: the engine's lines merged with the baked book's counts
// and ranked by popularity. Dart loads the book assets and passes the node in.
export { unifyMoves, confidences } from './explorer';

// ---- SAN / fen helpers (so Dart never re-implements chess.js rendering) ----
export { getSan, getSanLine, getNumberedSanLine, getFenAfter, isCapture } from './engine/chess';

// ---- board overlays ----
export { threatProbeFen, judgeThreat, judgeTacticalWin } from './engine/threats';
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
	addItems,
	removeItem,
	dueCount,
	puzzleDifficulty,
	masteryStats,
	nextItem,
	recordResult
} from './practice';

// ---- importing an analysed game from lichess (and, later, chess.com) ----
// The MAPPER only. `fetchLichessGames`/`importLichessGames` live in the same
// module and are deliberately NOT exported: they call `fetch`, which this
// bundle's contract (see the header) forbids, and which JavaScriptCore does
// not have at all — a native call would throw "fetch is not defined" rather
// than fail a request. So Dart does the HTTP (lib/brain/lichess_import_api.dart
// streams the ndjson) and hands each parsed game over here one at a time; the
// dedupe and the practice-threshold filter that `importLichessGames` wraps
// around this are five lines of Dart on that side.
//
// What crosses back is `{ stored, practice, humanColor }`: a StoredGame the
// archive can save verbatim, plus the PracticeCandidate list mined from
// lichess's own stored evals — which is what makes an import seed the practice
// queue with real blunders where a pasted PGN carries no grades at all.
export { lichessGameToStored, analysedGameToStored } from './lichessImport';

// ---- stored-game math (pure parts of gameStore) ----
export { moveAccuracy, gameAccuracy, labelCounts, LABEL_VERSION } from './gameStore';
export { estimatePlayerElo } from './playerElo';
