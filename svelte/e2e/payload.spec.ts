import { test, expect } from '@playwright/test';

// What the payload work claims: nothing fetches commentary.json or the ONNX
// runtime until something actually needs them, and the commentary panel still
// works when opened.
test('commentary and ort stay off the critical path', async ({ page }) => {
	const got: string[] = [];
	page.on('request', (r) => got.push(r.url()));

	await page.goto('/');
	await page.waitForSelector('cg-board');
	await page.waitForTimeout(2500);

	const commentaryEarly = got.filter((u) => u.includes('commentary.json'));
	const ortEarly = got.filter((u) => u.includes('ort-wasm') || u.includes('onnxruntime'));
	expect(commentaryEarly, 'commentary.json must not load on first paint').toHaveLength(0);
	expect(ortEarly, 'onnxruntime must not load on first paint').toHaveLength(0);

	// opening the panel is what pays for it. commentary.json is 4.1MB, and
	// these specs run serially on a runner that is also compiling Stockfish
	// WASM, so the fetch + parse + render genuinely wants more than the 20s
	// this used to allow — that budget flaked the whole web-e2e job (a false
	// red on #38 that passed on re-run). 60s is still well under the 150s
	// per-test cap and only bites if the panel truly never resolves.
	const slow = 60_000;
	await page.getByRole('button', { name: /^Commentary/ }).click();
	await page.waitForResponse((r) => r.url().includes('commentary.json'), { timeout: slow });
	await expect(page.locator('.commentary-panel')).toBeVisible();
	// and it resolves to a real state, not a stuck "Loading…"
	await expect(page.locator('.commentary-panel .empty, .commentary-panel .list')).not.toHaveText(
		/Loading/,
		{ timeout: slow }
	);
});
