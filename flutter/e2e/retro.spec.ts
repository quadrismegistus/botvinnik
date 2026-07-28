// The retro bots on Flutter web: TUROCHAMP (1948), BERNSTEIN (1957) and
// SARGON (1978), as wasm in their own Web Worker.
//
// A browser is the only place this can be checked. The Dart client is
// compiled out of the native build entirely (retro_engine_io.dart is a stub),
// the worker needs a real Worker and a real WebAssembly, and the failure mode
// is silent by design: every error path returns null and the bot falls back to
// Stockfish, so a broken retro persona still plays — as somebody else.

import { createServer, request as httpRequest } from 'node:http';

import { expect, test } from '@playwright/test';

import { OPENING_MOVES, START, loadSettled, seedPersona, seedPersonas } from './helpers';

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

test('the wasm starts arriving while YOU are still on move', async ({ page }) => {
	// The preload, against the seating a player actually uses. `_syncRetro`
	// says it builds the worker "when the persona changes as well as at move
	// time, so the wasm is compiling while the player is still setting up" —
	// and it keyed on the persona TO MOVE, which is null on your turn by
	// definition. So with the bot on Black (the default, and every game Ryan
	// plays) nothing was preloaded at all: the 4.4MB fetch began at the bot's
	// first turn, under a 30s cap, and on a phone that is a coin toss for
	// whether TUROCHAMP or a Stockfish stand-in answers 1...e5.
	//
	// The test the app already had seats the bot on WHITE, where the bot is on
	// move at load — so the lazy path and the preloaded one are indistinguishable
	// and it passed throughout.
	const wasm: number[] = [];
	const t0 = Date.now();
	page.on('request', (r) => {
		if (new URL(r.url()).pathname.endsWith('retro.wasm')) wasm.push(Date.now() - t0);
	});

	await seedPersonas(page, { black: 'retro-turochamp-1' });
	await page.goto('/');

	// No move is ever played here: the human has White and this test never
	// touches the board, so a retro turn cannot be what triggers the fetch.
	await expect
		.poll(() => wasm.length, { timeout: 60_000 })
		.toBeGreaterThan(0);
});

/**
 * Serve the app through a proxy that holds ONE path back.
 *
 * Playwright's own `page.route` cannot do this: the fetch is made by the retro
 * Web Worker, and worker requests are not intercepted — verified, the delayed
 * route never fired and the wasm arrived in 2 seconds. Slowing the network from
 * the outside is the only lever that reaches inside a worker, so the test
 * points the browser at its own origin on 4401 and pipes everything to the
 * suite's real server on 4400.
 */
async function slowProxy(match: RegExp, delayMs: number) {
	const server = createServer((req, res) => {
		const send = () => {
			const up = httpRequest(
				{
					host: 'localhost',
					port: 4400,
					path: req.url,
					method: req.method,
					headers: { ...req.headers, host: 'localhost:4400' }
				},
				(r) => {
					res.writeHead(r.statusCode ?? 502, r.headers);
					r.pipe(res);
				}
			);
			up.on('error', () => {
				res.writeHead(502);
				res.end();
			});
			req.pipe(up);
		};
		if (match.test(req.url ?? '')) setTimeout(send, delayMs);
		else send();
	});
	await new Promise<void>((r) => server.listen(4401, r));
	return {
		url: 'http://localhost:4401',
		close: () => new Promise<void>((r) => server.close(() => r()))
	};
}

test('a boot slower than one turn does not condemn the whole game', async ({ page }) => {
	// What Ryan hit on the phone: retro played as a Stockfish stand-in for an
	// entire game. `move()` waited 30s for the boot and then called `_die` —
	// which latches `_alive = false`, so every later turn returned null
	// instantly and the badge (sticky per game) never cleared. One slow first
	// download cost the whole game, and the download it gave up on had almost
	// certainly finished seconds later.
	//
	// Held the wasm back 40s: past what one turn will wait for, well short of
	// the engine being unreachable. Both bots are the same retro, so turns keep
	// arriving without touching the board — the canvas is not driveable.
	const proxy = await slowProxy(/retro\.wasm$/, 40_000);
	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	await seedPersonas(page, {
		white: 'retro-turochamp-1',
		black: 'retro-turochamp-1'
	});
	await page.goto(proxy.url);

	// It stands in while the wasm is still on the wire — that much is correct,
	// and the board has to move.
	await expect
		.poll(() => logs.some((l) => l.includes('retro had no move')), { timeout: 90_000 })
		.toBe(true);

	// And then it recovers, which is the whole claim.
	await expect
		.poll(() => logs.some((l) => /\[retro\].*Search /.test(l)), { timeout: 120_000 })
		.toBe(true);

	await proxy.close();
});
