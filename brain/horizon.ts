// The "Horizon" personas, as a brain function so the Flutter app can play
// them too. js-chess-engine (josefjadrny, MIT) at its lowest levels: a tiny
// pure-JavaScript engine with little quiescence search, so it launches
// exchanges it cannot see the end of and walks into recaptures — the horizon
// effect, live. See svelte/src/lib/engine/jsce.ts for the calibration notes.
//
// This module is reachable ONLY from brain-entry.ts, which is the esbuild
// entry and nothing else. That is deliberate: the Svelte app imports brain
// modules individually and keeps its own lazily-imported copy in jsce.ts, so
// a static import here cannot drag js-chess-engine into the web bundle.
//
// Synchronous on purpose. The Dart bridge marshals `JSON.stringify(brain.fn())`
// in one eval, so a Promise would cross as `{}` — anything the bridge calls
// has to return a value, not a promise. Levels 1-2 answer in ~2-100ms, which
// is why this one can be.

import { ai } from 'js-chess-engine';
import { Chess } from 'chess.js';

/**
 * The move a Horizon persona plays, in UCI, or null if the position gave it
 * nothing legal. `level` is the persona's `jsceLevel` (1 or 2).
 *
 * NOT deterministic: js-chess-engine picks among equal-scoring moves at
 * random, so the same position can yield different moves. Do not pin it with
 * a golden fixture — assert legality instead.
 */
export function horizonMove(fen: string, level: number): string | null {
	let move: Record<string, string>;
	try {
		move = ai(fen, { level }).move as Record<string, string>;
	} catch {
		return null; // the library throws on some positions; caller falls back
	}
	const entry = Object.entries(move)[0] as [string, string] | undefined;
	if (!entry) return null;
	const from = entry[0].toLowerCase();
	const to = entry[1].toLowerCase();
	// js-chess-engine always promotes to queen and never says so; UCI wants it
	// spelled out, and chess.js is the arbiter of whether this is a promotion
	const legal = new Chess(fen).moves({ verbose: true }).find((m) => m.from === from && m.to === to);
	if (!legal) return null;
	return `${from}${to}${legal.promotion ? 'q' : ''}`;
}
