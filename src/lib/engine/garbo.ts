// Garbochess-JS (Gary Linscott, 2011, BSD — vendored in static/garbo/ with
// its LICENSE): a hand-written JavaScript engine from before compiling C to
// the browser was practical. Fruit-era eval (PSQ + mobility + bishop pair,
// pre-NNUE), and — a gift — the worker protocol is built into the engine
// file itself: `position <fen>` / `search <movetimeMs>` → the move in UCI.
//
// Strength anchor: @GarboBot on lichess runs this engine and holds ~1931
// blitz / ~2021 rapid over 90k+ human games. We run ~1s/move, in that
// neighborhood; the persona says ~2000 and the style — sharp tactics,
// 2011-era positional judgment — is the point, not the exact number.
//
// Provenance footnote: Linscott went on to create fishtest and found Leela.

import { base } from '$app/paths';

let worker: Worker | null = null;

function ensure(): Worker {
	if (!worker) worker = new Worker(`${base}/garbo/garbochess.js`);
	return worker;
}

export function preloadGarbo(): void {
	try {
		ensure();
	} catch {
		// no Worker support — callers fall back to Stockfish
	}
}

/** Garbochess's move for this position, or null on any failure. */
export function garboMove(fen: string, movetimeMs = 1000): Promise<string | null> {
	return new Promise((resolve) => {
		let w: Worker;
		try {
			w = ensure();
		} catch {
			resolve(null);
			return;
		}
		const finish = (move: string | null) => {
			clearTimeout(timer);
			w.removeEventListener('message', onMsg);
			resolve(move);
		};
		const timer = setTimeout(() => finish(null), movetimeMs + 10_000);
		const onMsg = (e: MessageEvent) => {
			if (typeof e.data !== 'string') return;
			if (e.data.startsWith('pv ') || e.data.startsWith('message ')) return;
			// anything else is the move, in UCI (FormatMove)
			finish(/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(e.data) ? e.data : null);
		};
		w.addEventListener('message', onMsg);
		w.postMessage(`position ${fen}`);
		w.postMessage(`search ${movetimeMs}`);
	});
}
