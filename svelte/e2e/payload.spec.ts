import { test, expect } from '@playwright/test';

import { waitForEngineReady } from './helpers';

// What the payload work claims: nothing fetches commentary.json or the ONNX
// runtime until something actually needs them, and the commentary panel still
// works when opened.
test('commentary and ort stay off the critical path', async ({ page }) => {
	const got: string[] = [];
	page.on('request', (r) => got.push(r.url()));

	// waitForEngineReady, not `waitForSelector('cg-board') + a fixed sleep`:
	// cg-board is in the DOM before Svelte hydrates, so on a loaded runner the
	// click below could land on a button whose handler wasn't wired yet.
	await page.goto('/');
	await waitForEngineReady(page);

	const commentaryEarly = got.filter((u) => u.includes('commentary.json'));
	const ortEarly = got.filter((u) => u.includes('ort-wasm') || u.includes('onnxruntime'));
	expect(commentaryEarly, 'commentary.json must not load on first paint').toHaveLength(0);
	expect(ortEarly, 'onnxruntime must not load on first paint').toHaveLength(0);

	// Opening the panel is what pays for it. The waiter is armed BEFORE the
	// click, not after: the fetch fires the instant the panel mounts, and a
	// `click(); waitForResponse()` ordering loses the race whenever the
	// response beats the listener's registration — which is exactly the
	// intermittent web-e2e flake (it timed out at 20s, then at 60s: the
	// response was never late, it was already gone). 30s is ample for the
	// 4.1MB body once the event is actually captured.
	const commentaryLoaded = page.waitForResponse(
		(r) => r.url().includes('commentary.json'),
		{ timeout: 30_000 }
	);
	await page.getByRole('button', { name: /^Commentary/ }).click();
	await commentaryLoaded;
	await expect(page.locator('.commentary-panel')).toBeVisible();
	// and it resolves to a real state, not a stuck "Loading…"
	await expect(page.locator('.commentary-panel .empty, .commentary-panel .list')).not.toHaveText(
		/Loading/,
		{ timeout: 30_000 }
	);
});
