// Garbochess-JS on Flutter web: Gary Linscott's 2011 hand-written engine,
// vendored verbatim and run in a Web Worker.
//
// Same reason as retro for testing it here rather than reasoning about it:
// every failure path returns null and the bot falls back to Stockfish, so a
// broken Garbo still plays — as somebody else, silently.

import { expect, test } from '@playwright/test';

import { OPENING_MOVES, START, loadSettled, seedPersona } from './helpers';

test('the worker answers with a legal move', async ({ page }) => {
	await loadSettled(page);
	const result = await page.evaluate(async ([fen]) => {
		const w = new Worker('garbo/garbochess.js');
		const chatter: string[] = [];
		const move = new Promise<string>((resolve) => {
			w.onmessage = (e) => {
				if (typeof e.data !== 'string') return;
				// 'pv …' is progress, 'message …' is a FEN parse error; anything
				// else is the move. There is no handshake and no uciok here —
				// the protocol is built into the engine file.
				if (e.data.startsWith('pv ') || e.data.startsWith('message ')) {
					chatter.push(e.data);
					return;
				}
				resolve(e.data);
			};
			setTimeout(() => resolve('TIMEOUT'), 60_000);
		});
		w.postMessage(`position ${fen}`);
		w.postMessage('search 1000');
		const m = await move;
		w.terminate();
		return { m, sawProgress: chatter.some((c) => c.startsWith('pv ')) };
	}, [START]);

	expect(result.m).not.toBe('TIMEOUT');
	expect(OPENING_MOVES).toContain(result.m);
	// it actually searched rather than returning the first legal move it saw
	expect(result.sawProgress).toBe(true);
});

test('a FEN it cannot parse throws, and never answers', async ({ page }) => {
	// Measured, not assumed — the first version of this test asserted a
	// 'message …' reply, which is what the `message` branch in garbochess
	// suggests. That is not what happens. A bad FEN leaves the board in a
	// broken state that InitializeFromFen does NOT report, the search then
	// emits a stream of "stalemate" progress lines, and finally the worker
	// throws a TypeError. No move is ever posted.
	//
	// Both halves of the Dart client exist because of this:
	//   * the onerror handler is not dead code — it is the ONLY thing that
	//     ends this search, so without it the caller waits out the timeout
	//   * the 'pv ' filter is load-bearing: ~99 chatter lines arrive before
	//     the throw, and an unfiltered client would take the first one as a
	//     move (the regex guard would reject it, but only by luck of format)
	await loadSettled(page);
	const out = await page.evaluate(async () => {
		const w = new Worker('garbo/garbochess.js');
		const seen: string[] = [];
		let err: string | null = null;
		w.onmessage = (e) => {
			if (typeof e.data === 'string') seen.push(e.data);
		};
		w.onerror = (e) => {
			err ??= e.message || 'error event';
			e.preventDefault?.();
		};
		w.postMessage('position not-a-fen');
		await new Promise((r) => setTimeout(r, 300));
		w.postMessage('search 300');
		await new Promise((r) => setTimeout(r, 6000));
		w.terminate();
		return { err, seen, nonProgress: seen.filter((s) => !s.startsWith('pv ')) };
	});

	expect(out.err).toBeTruthy();
	// everything it said was progress chatter; it never named a move
	expect(out.seen.length).toBeGreaterThan(0);
	expect(out.nonProgress).toEqual([]);
});

test('the app itself plays with it', async ({ page }) => {
	// GarboEngine is built lazily INSIDE the garbo branch of _pickBotMove, so
	// unlike retro (which preloads when the persona changes) this request can
	// only happen if the bot's turn actually reached that branch. It is the
	// strongest single signal available without a DOM to inspect.
	const garboRequests: string[] = [];
	page.on('request', (r) => {
		const path = new URL(r.url()).pathname;
		if (path.includes('/garbo/')) garboRequests.push(path);
	});
	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	await seedPersona(page, 'garbo-2000');
	await page.goto('/');

	await expect
		.poll(() => garboRequests.some((p) => p.endsWith('garbochess.js')), { timeout: 60_000 })
		.toBe(true);

	// Garbo logs nothing of its own on success, so the absence of the fallback
	// IS the assertion that it answered. Give it well past its 1s movetime
	// before believing that absence.
	await page.waitForTimeout(15_000);
	expect(logs.filter((l) => l.includes('garbo had no move'))).toEqual([]);
});
