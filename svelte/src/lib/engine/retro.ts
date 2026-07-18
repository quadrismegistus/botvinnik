// Retro engines: morlock's Go re-implementations of TUROCHAMP (1948),
// BERNSTEIN (1957) and SARGON (1978), compiled to WebAssembly and run in a
// dedicated Web Worker (static/retro/). They are complete UCI engines, so
// this client speaks a minimal UCI over postMessage — entirely separate from
// the Stockfish analysis engine (a retro bot must never touch the analysis
// cache, and vice versa).
//
// The personas carry these engines' REAL lichess human-pool ratings (the
// morlock bots have 15-50k rated games each) — see bots.ts.

import { base } from '$app/paths';

export type { RetroEngineName } from '$brain/engine/types';
import type { RetroEngineName } from '$brain/engine/types';

export type { RetroSpec } from '$brain/engine/types';
import type { RetroSpec } from '$brain/engine/types';

interface Client {
	worker: Worker;
	key: string;
	ready: Promise<void>;
}

let client: Client | null = null;

function boot(spec: RetroSpec): Client {
	const key = `${spec.engine}:${spec.ply}`;
	if (client?.key === key) return client;
	client?.worker.terminate();

	const worker = new Worker(`${base}/retro/retro-worker.js`);
	const ready = new Promise<void>((resolve, reject) => {
		const timer = setTimeout(() => reject(new Error('retro engine boot timeout')), 20_000);
		const onMsg = (e: MessageEvent) => {
			if (e.data === 'uciok') {
				clearTimeout(timer);
				worker.removeEventListener('message', onMsg);
				resolve();
			}
		};
		worker.addEventListener('message', onMsg);
	});
	worker.postMessage({ engine: spec.engine, ply: spec.ply });
	worker.postMessage('uci'); // queued worker-side until the wasm is up
	// preloadRetro fires-and-forgets boot(); without a no-op handler a boot
	// timeout surfaces as an unhandled rejection (retroMove's own await still
	// sees the rejection and falls back to Stockfish)
	ready.catch(() => {});
	client = { worker, key, ready };
	return client;
}

/** Warm the worker + wasm ahead of the first move. */
export function preloadRetro(spec: RetroSpec): void {
	try {
		boot(spec);
	} catch {
		// no Worker support etc. — the caller falls back to Stockfish
	}
}

/** The retro engine's move for this position, or null on any failure. */
export async function retroMove(fen: string, spec: RetroSpec, movetimeMs = 500): Promise<string | null> {
	const c = boot(spec);
	await c.ready;
	return new Promise<string | null>((resolve) => {
		const timer = setTimeout(() => {
			c.worker.removeEventListener('message', onMsg);
			resolve(null); // caller falls back to Stockfish
		}, movetimeMs + 10_000);
		const onMsg = (e: MessageEvent) => {
			if (typeof e.data !== 'string' || !e.data.startsWith('bestmove')) return;
			clearTimeout(timer);
			c.worker.removeEventListener('message', onMsg);
			const uci = e.data.split(/\s+/)[1];
			resolve(uci && uci !== '(none)' && uci !== '0000' ? uci : null);
		};
		c.worker.addEventListener('message', onMsg);
		c.worker.postMessage(`position fen ${fen}`);
		c.worker.postMessage(`go movetime ${movetimeMs}`);
	});
}
