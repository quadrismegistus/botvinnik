// The "Horizon" personas, as a brain function so the Flutter app can play
// them too. js-chess-engine (josefjadrny, MIT) at its lowest levels: a tiny
// pure-JavaScript engine with little quiescence search, so it launches
// exchanges it cannot see the end of and walks into recaptures — the horizon
// effect, live. See svelte/src/lib/engine/jsce.ts for the calibration notes.
//
// This module is reachable ONLY from brain-entry.ts, which is the esbuild
// entry and nothing else — so it contributes nothing to the web build, and
// its static `js-chess-engine` import cannot reach the browser. The web gets
// that library through its own `await import()` INSIDE jsce.ts (jsce.ts
// itself is eagerly imported by +page.svelte; only the library is deferred),
// which lands it in a lazy chunk fetched when a Horizon persona first plays.
//
// Synchronous on purpose. The Dart bridge marshals `JSON.stringify(brain.fn())`
// in one eval, so a Promise would cross as `{}` — anything the bridge calls
// has to return a value, not a promise. Levels 1-2 answer in ~2-5ms, which is
// why this one can be.

import { ai } from 'js-chess-engine';
import { horizonUci } from './horizonUci';

/**
 * The move a Horizon persona plays, in UCI, or null if it had nothing to
 * offer. `level` is the persona's `jsceLevel` (1 or 2).
 *
 * Never throws: everything is inside the try, including the FEN parsing, so a
 * malformed position degrades to a fallback instead of crossing the bridge as
 * an error. That distinction matters — a throw here reaches Dart as a
 * StateError on the bot's turn, which is much worse than no move.
 *
 * NOT deterministic: js-chess-engine picks among equal-scoring moves at
 * random, so the same position can yield different moves. Do not pin it with
 * a golden fixture — assert legality instead.
 */
export function horizonMove(fen: string, level: number): string | null {
	try {
		// throws on a finished game ("Game is already finished") and on a level
		// outside 1-5 — both are fallback-worthy rather than fatal
		const move = ai(fen, { level }).move as Record<string, string>;
		const entry = Object.entries(move)[0] as [string, string] | undefined;
		if (!entry) return null;
		return horizonUci(fen, entry[0], entry[1]);
	} catch {
		return null;
	}
}
