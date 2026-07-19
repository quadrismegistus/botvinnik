// Maia on Flutter web: a human-imitation net run through onnxruntime-web in
// a Worker.
//
// Two of these tests are tagged @network and CI skips them, because they
// download ~3.5MB of weights from HuggingFace. That is not incidental — the
// weights are GPL-3.0 and deliberately not redistributed with the app, so
// "reaches the network on first use" is a permanent property of this family
// rather than a test-environment detail. Run them locally:
//
//   npx playwright test -c flutter/playwright.config.ts flutter/e2e/maia.spec.ts
//
// The third test needs no network and DOES run in CI, because the property it
// guards is the one Maia puts at risk: that the app is otherwise third-party
// free.

import { expect, test } from '@playwright/test';

import { OPENING_MOVES, START, loadSettled, seedPersona } from './helpers';

const AFTER_E4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

test('@network the worker returns the move a human would play', async ({ page }) => {
	await loadSettled(page);
	const out = await page.evaluate(
		async ([start, afterE4]) => {
			const w = new Worker('maia/maia-worker.js');
			const events: unknown[] = [];
			const ask = (id: number, fenHistory: string[]) =>
				new Promise<Record<string, unknown>>((resolve) => {
					const onMsg = (e: MessageEvent) => {
						events.push(e.data);
						if (e.data?.id !== id) return;
						if (e.data.move !== undefined || e.data.error) {
							w.removeEventListener('message', onMsg);
							resolve(e.data);
						}
					};
					w.addEventListener('message', onMsg);
					setTimeout(() => resolve({ error: 'TIMEOUT' }), 120_000);
					w.postMessage({ id, fenHistory, band: 1100, temperature: 0 });
				});

			const first = await ask(1, [start]);
			const t = Date.now();
			const second = await ask(2, [start, afterE4]);
			const secondMs = Date.now() - t;
			w.terminate();
			return { first, second, secondMs, events };
		},
		[START, AFTER_E4] as const
	);

	expect(out.first.error).toBeUndefined();
	expect(OPENING_MOVES).toContain(out.first.move as string);
	// Maia-1100 at temperature 0 plays the training population's consensus
	// move, which from the opening is overwhelmingly 1.e4 and 1…e5.
	//
	// BOTH assertions are here because they have different sensitivity, which
	// was measured rather than assumed:
	//
	//   * Breaking the black-perspective flip in encodeFenHistory (lc0 planes
	//     are "us/them", so they must be swapped when black is to move) leaves
	//     the WHITE answer at e2e4 and changes the BLACK one to d7d5. Legal,
	//     plausible, wrong — legality alone would never have caught it, and
	//     neither would the first assertion.
	//   * Inverting plane 108 (is-black-to-move) changes NOTHING. That plane
	//     is redundant: the flipped us/them planes already carry the same
	//     fact. So this test does not pin every byte of the tensor, and it
	//     would be dishonest to claim it does.
	expect(out.first.move).toBe('e2e4');
	expect(out.second.move).toBe('e7e5');

	// the session is reused across moves rather than reloaded per position
	expect(out.secondMs).toBeLessThan(3000);

	// It reported progress throughout, then named the compile phase, then
	// answered — in that order.
	//
	// This used to be a single `status: 'fetching'` announcement, and the
	// assertion was `toBeLessThanOrEqual(1)`, which accepts ZERO: deleting the
	// announcement entirely left it green. It is now a stream, so the test can
	// ask for something much stronger than "at least one happened".
	type Ev = { id?: number; status?: string; received?: number; total?: number; move?: string };
	const events = out.events as Ev[];
	const firstAnswerAt = events.findIndex((e) => e?.move !== undefined);
	const fetching = events.filter((e) => e?.status === 'fetching');
	const starting = events.filter((e) => e?.status === 'starting');

	// a real stream, not one token message
	expect(fetching.length).toBeGreaterThan(3);
	// with real numbers in it — a bar needs a denominator, and HuggingFace
	// does send content-length. If it ever stops, fraction goes null and the
	// bar goes indeterminate rather than sitting at zero.
	const withBytes = fetching.filter((e) => (e.received ?? 0) > 0);
	expect(withBytes.length).toBeGreaterThan(0);
	expect(withBytes[0].total).toBeGreaterThan(1_000_000);
	// monotonic: a bar that goes backwards is worse than no bar
	const received = fetching.map((e) => e.received ?? 0);
	expect(received).toEqual([...received].sort((a, b) => a - b));
	// and it finishes, rather than stalling at 80% while the work continues
	expect(received[received.length - 1]).toBe(withBytes[0].total);

	// the compile phase is named, and lands between the download and the move
	expect(starting.length).toBeGreaterThan(0);
	expect(events.indexOf(starting[0])).toBeGreaterThan(events.indexOf(fetching[0]));
	expect(events.indexOf(starting[0])).toBeLessThan(firstAnswerAt);
});

test('@network the app itself plays with it', async ({ page }) => {
	const hosts: string[] = [];
	page.on('request', (r) => hosts.push(new URL(r.url()).host));
	const logs: string[] = [];
	page.on('console', (m) => logs.push(m.text()));

	await seedPersona(page, 'maia-1100');
	await page.goto('/');

	// the weights fetch is the proof the Dart client drove the worker: the
	// worker only reaches HuggingFace after a well-formed request arrives
	await expect
		.poll(() => hosts.some((h) => h.includes('huggingface.co')), { timeout: 90_000 })
		.toBe(true);

	await page.waitForTimeout(20_000);
	expect(logs.filter((l) => l.includes('maia had no move'))).toEqual([]);
});

test('a non-Maia game makes no third-party request at all', async ({ page }) => {
	// The property #35 bought, which Maia is the only thing that can take
	// away. Deliberately NOT tagged @network, so this is the whole of what CI
	// can say about this family.
	//
	// Which is exactly why it must assert something POSITIVE first. As
	// originally written it was a bare absence check, and a review proved it
	// passed against a completely dead app: replacing flutter_bootstrap.js
	// with `throw` boots nothing, renders nothing, requests nothing — and
	// "no third-party requests" is trivially true of an app that does not
	// run. It would also have stayed green if every Maia persona silently
	// vanished from the roster.
	const foreign: string[] = [];
	const local: string[] = [];
	page.on('request', (r) => {
		const host = new URL(r.url()).host;
		if (host.startsWith('localhost')) local.push(new URL(r.url()).pathname);
		else foreign.push(`${host} ${r.url().slice(0, 80)}`);
	});

	await seedPersona(page, 'square-900');
	await page.goto('/');

	// the app booted far enough to start an engine and think about a move —
	// a dead app never reaches this, which is the point
	await expect
		.poll(() => local.some((p) => p.endsWith('/wasm/stockfish.js')), { timeout: 60_000 })
		.toBe(true);
	await expect
		.poll(() => local.some((p) => p.endsWith('/brain.js')), { timeout: 60_000 })
		.toBe(true);

	// and only THEN is the absence meaningful
	await page.waitForTimeout(15_000);
	expect(foreign).toEqual([]);
});
