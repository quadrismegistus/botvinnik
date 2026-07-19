// The retro bots on Flutter web: TUROCHAMP (1948), BERNSTEIN (1957) and
// SARGON (1978), as wasm in their own Web Worker.
//
// A browser is the only place this can be checked. The Dart client is
// compiled out of the native build entirely (retro_engine_io.dart is a stub),
// the worker needs a real Worker and a real WebAssembly, and the failure mode
// is silent by design: every error path returns null and the bot falls back to
// Stockfish, so a broken retro persona still plays — as somebody else.

import { expect, test } from '@playwright/test';

import { OPENING_MOVES, START, loadSettled, seedPersona } from './helpers';

// The roster's three retro personas, and the name each engine reports. All
// three share one retro.wasm, selected by the boot message — so a wasm built
// without one of them fails here and nowhere else.
const ENGINES = [
	{ engine: 'turochamp', ply: 1, id: 'TUROCHAMP (1948)' },
	{ engine: 'bernstein', ply: 2, id: 'BERNSTEIN (1957)' },
	{ engine: 'sargon', ply: 1, id: 'SARGON (1978)' }
];

for (const { engine, ply, id } of ENGINES) {
test(`${engine} answers UCI with a legal move`, async ({ page }) => {
	await loadSettled(page);
	const result = await page.evaluate(
		async ([fen, engine, ply]) => {
			const w = new Worker('retro/retro-worker.js');
			const lines: string[] = [];
			const bestmove = new Promise<string>((resolve) => {
				w.onmessage = (e) => {
					if (typeof e.data !== 'string') return;
					lines.push(e.data);
					if (e.data.startsWith('bestmove')) resolve(e.data);
				};
				setTimeout(() => resolve('TIMEOUT'), 60_000);
			});
			// the boot message is an OBJECT; every later message is a UCI string.
			// retro-worker.js tells them apart by typeof alone.
			w.postMessage({ engine, ply });
			w.postMessage('uci');
			await new Promise<void>((r) => {
				const t = setInterval(() => {
					if (lines.includes('uciok')) {
						clearInterval(t);
						r();
					}
				}, 50);
				setTimeout(() => {
					clearInterval(t);
					r();
				}, 45_000);
			});
			w.postMessage(`position fen ${fen}`);
			w.postMessage('go movetime 500');
			const bm = await bestmove;
			w.terminate();
			return { bm, ids: lines.filter((l) => l.startsWith('id name')) };
		},
		[START, engine, ply] as const
	);

	// it is the engine we think it is, not Stockfish under another name
	expect(result.ids.join()).toContain(id);
	expect(result.bm).not.toBe('TIMEOUT');
	expect(OPENING_MOVES).toContain(result.bm.split(/\s+/)[1]);
});
}

test('the app itself boots a retro worker and plays with it', async ({ page }) => {
	// The half a hand-driven worker test cannot reach: that the DART client
	// drives it. In particular that the {engine, ply} boot message crosses as
	// a JS object — get that wrong and the worker treats it as an unknown
	// string, never fetches the wasm, and the persona silently falls back
	// after a 30s timeout, in someone else's browser.
	const retroRequests: string[] = [];
	page.on('request', (r) => {
		const path = new URL(r.url()).pathname;
		if (path.includes('/retro/')) retroRequests.push(path);
	});
	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	await seedPersona(page, 'retro-turochamp-1');
	await page.goto('/');

	// the wasm fetch is the proof the boot message was understood
	await expect
		.poll(() => retroRequests.some((p) => p.endsWith('retro.wasm')), { timeout: 60_000 })
		.toBe(true);

	// and the engine's own log is the proof it searched the position the app
	// sent, rather than merely starting up
	await expect
		.poll(() => logs.some((l) => /\[retro\].*Search .*turn=w/.test(l)), { timeout: 60_000 })
		.toBe(true);

	// the fallback is the silent failure this whole test exists to catch
	expect(logs.filter((l) => l.includes('retro had no move'))).toEqual([]);
});
