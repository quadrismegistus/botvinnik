// Maia's pure halves, bundled for the embedded JS runtime on macOS/iOS.
//
// On the web these live in web_src/maia-worker.ts alongside ort, the network
// and IndexedDB. Native splits that worker down the middle: the impure half
// (download, cache, inference) is Dart in engine/maia_engine_io.dart, and the
// two pure functions it needs are here, running the SAME brain/maia/ sources
// the web does. Nothing about Maia's chess is written twice.
//
// Why a second bundle rather than two more exports on brain.js: brain.js is a
// <script> tag on the web, loaded by every visitor before the first paint.
// The lc0 policy index is 1858 move strings that only a Maia ever needs, and
// keeping Maia out of the eager path is the whole point of the web's lazy
// worker. This bundle is an ASSET, read only when someone picks a Maia.
//
// Loaded as an IIFE under the global `maiaBrain`, exactly as brain.js is
// loaded under `brain` — same expression builder, same JSON marshalling.

import { Chess } from 'chess.js';

import { decodePolicyOutput } from '../../brain/maia/decoding';
import { encodeFenHistory } from '../../brain/maia/encoding';

/** Bump in lockstep with kExpectedMaiaBrainVersion in maia_engine_io.dart. */
export const MAIA_BRAIN_VERSION = 1;

const legalUcis = (fen: string): string[] =>
	new Chess(fen).moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ''));

/**
 * The [1, 112, 8, 8] input tensor for the position at the end of [fenHistory],
 * flattened, or null when that position has no legal moves.
 *
 * Returned as a plain array: JSON.stringify of a Float32Array is an OBJECT
 * ({"0":1,…}), which crosses the bridge as a map and decodes to nothing
 * useful. Array.from is the whole fix and is easy to lose in a refactor.
 */
export function maiaPlanes(fenHistory: string[]): number[] | null {
	const fen = fenHistory[fenHistory.length - 1];
	if (!fen) return null;
	if (legalUcis(fen).length === 0) return null;
	return Array.from(encodeFenHistory(fenHistory));
}

/**
 * The move Maia picks, given the policy head's 1858 logits for [fen].
 *
 * [temperature] 0 is argmax — the band's consensus move. Above 0 samples,
 * which is what the maia-s-* personas are (see brain/bots.ts).
 */
export function maiaPick(policy: number[], fen: string, temperature: number): string | null {
	const legal = legalUcis(fen);
	if (legal.length === 0) return null;
	const isBlack = fen.split(' ')[1] === 'b';
	return decodePolicyOutput(new Float32Array(policy), legal, isBlack, temperature).best.move;
}
