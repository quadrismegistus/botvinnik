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
import { enableSemantics, tap } from './semantics';

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
	// Held the wasm back 70s: past what one turn will wait for (30s), well
	// short of the three minutes before the engine gives up for good. The
	// margin is deliberately wide rather than 40s — the 30s starts at the
	// bot's first turn, not at page load, so on a slow CI runner a tighter
	// delay would let the boot land BEFORE the first turn ran out of patience
	// and the test would go green having exercised nothing.
	//
	// Both bots are the same retro, so turns keep arriving without touching
	// the board — the canvas is not driveable.
	const proxy = await slowProxy(/retro\.wasm$/, 70_000);
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

// The two cases that drive the SHIPPED Dart client rather than hand-rolled
// UCI. Everything above talks to the worker directly, which is why the whole
// suite stayed green through a bug that handed entire games to a Stockfish
// stand-in: deleting the fix from retro_engine_web.dart changes nothing any
// of it can see.

const SEARCHES = (logs: string[]) => logs.filter((l) => /\[retro\].*Search /.test(l)).length;
const BOOTS = (logs: string[]) =>
	logs.filter((l) => /\[retro\].*Initialized engine/.test(l)).length;

test('a second game does not leave the retro engine dead', async ({ page }) => {
	// The reported bug, end to end. `_syncRetro` keeps one worker across games
	// while the persona is unchanged, so the second game's opening `position
	// fen` is character-identical to the last line the engine saw — which used
	// to end morlock's driver and hand every later turn to a stand-in.
	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	await seedPersona(page, 'retro-turochamp-1');
	await page.goto('/');

	await expect.poll(() => SEARCHES(logs), { timeout: 60_000 }).toBeGreaterThan(0);
	await enableSemantics(page);
	const before = SEARCHES(logs);

	await tap(page, 'New game');
	await tap(page, 'Start');

	await expect.poll(() => SEARCHES(logs), { timeout: 60_000 }).toBeGreaterThan(before);
	expect(logs.filter((l) => l.includes('retro had no move'))).toEqual([]);
});

test('a worker that dies anyway is replaced for the next turn', async ({ page }) => {
	// FAULT INJECTION, because `ucinewgame` is meant to make that death
	// unreachable — and a net nothing can reach is a net nobody can trust.
	// Wrap the retro Worker in the page and feed the engine a line that ends
	// morlock's driver, arriving from outside the client. What has to catch it
	// is the engine reporting its own exit and `_syncRetro` building a fresh
	// worker for the next turn.
	//
	// The injected line USED to be a plain duplicate of the last `position`,
	// which is what the reported bug was. Upstream 63db3e6a — now the pinned
	// revision (vendor/retro/MORLOCK_REV) — made exactly that survivable, so
	// this test was injecting a fault the engine no longer has and failing on
	// a net that had nothing to catch. It is a real hazard of backstop tests:
	// fix the bug the injection exploits and the backstop quietly stops
	// testing anything.
	//
	// So: a continuation line carrying an INVALID move. `uci.go`'s position
	// handler still returns — and so ends main() — when `d.e.Move` rejects an
	// argument, and upstream's fix only skipped EMPTY tokens. `z9z9` is
	// malformed rather than merely illegal, so unlike a plausible-looking
	// `e2e5` it can never happen to be legal in whatever position the game has
	// reached when the injection lands.
	await page.addInitScript(() => {
		const Orig = window.Worker;
		let searches = 0;
		window.Worker = class extends Orig {
			__retro = false;
			__last: string | null = null;
			constructor(url: string | URL, opts?: WorkerOptions) {
				super(url, opts);
				this.__retro = String(url).includes('retro');
			}
			postMessage(msg: unknown, ...rest: unknown[]) {
				const r = (super.postMessage as (...a: unknown[]) => void)(msg, ...rest);
				if (this.__retro && typeof msg === 'string') {
					if (msg.startsWith('position fen')) this.__last = msg;
					if (msg.startsWith('go movetime')) {
						searches++;
						if (searches === 2 && this.__last) {
							// prefix-matches lastPosition, so the driver takes its
							// continuation branch and parses the remainder as moves
							(super.postMessage as (...a: unknown[]) => void)(
								`${this.__last} moves z9z9`
							);
						}
					}
				}
				return r;
			}
		};
	});

	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	// both seats retro, so turns keep arriving without touching the canvas
	await seedPersonas(page, { white: 'retro-turochamp-1', black: 'retro-turochamp-1' });
	await page.goto('/');

	// it dies, and the client SAYS so rather than waiting out the timeout
	await expect
		.poll(() => logs.some((l) => l.includes('the engine process ended')), { timeout: 60_000 })
		.toBe(true);

	// and a fresh worker is built for the next turn, which is the whole claim
	// of the `exited` check in _syncRetro
	await expect.poll(() => BOOTS(logs), { timeout: 90_000 }).toBeGreaterThan(1);
});
