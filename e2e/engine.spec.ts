import { expect, test } from '@playwright/test';
import { clickSquare, waitForApp } from './helpers';

test('analysis completes with full numbered PVs and a persistent depth chip', async ({ page }) => {
	await waitForApp(page);

	// the Lines card is open by default; let the slice finish
	await page.waitForSelector('.analysis-panel .line');
	await page.waitForFunction(
		() => /^d\d+$/.test(document.querySelector('.analysis-panel .status')?.textContent ?? ''),
		{ timeout: 60_000 }
	);

	const status = (await page.locator('.analysis-panel .status').textContent()) ?? '';
	expect(Number(status.slice(1))).toBeGreaterThanOrEqual(15);

	const lines = await page.locator('.analysis-panel .line').allTextContents();
	expect(lines.length).toBe(3);
	// the top line always carries a long numbered continuation; lower lines may
	// legitimately end short when the final iteration switches their root move
	expect(lines[0]).toMatch(/\d\.(\.\.)?[a-hKQRBNO]/);
	expect(lines[0].trim().split(/\s+/).length).toBeGreaterThan(6);
	for (const line of lines) {
		// and nothing ever regresses to raw UCI ("e7e5")
		expect(line).not.toMatch(/\b[a-h][1-8][a-h][1-8]\b/);
	}
});

test('hovering an engine line pops an animating preview board', async ({ page }) => {
	await waitForApp(page);
	await page.waitForSelector('.analysis-panel .line .line-hover');

	await page.locator('.analysis-panel .line .line-hover').first().hover();
	await page.waitForSelector('.line-hover .popup cg-board');

	const snapshot = () =>
		page.evaluate(() =>
			[...document.querySelectorAll('.line-hover .popup cg-board piece')]
				.map((p) => p.getAttribute('style'))
				.join('|')
		);
	const before = await snapshot();
	await page.waitForTimeout(2200);
	expect(await snapshot()).not.toBe(before);

	await page.mouse.move(5, 5);
	await expect(page.locator('.line-hover .popup')).toHaveCount(0);
});

test('playing a move produces a graded insight card', async ({ page }) => {
	await waitForApp(page);
	await clickSquare(page, 4, 2); // e2
	await clickSquare(page, 4, 4); // e4

	await page.waitForFunction(
		() => document.querySelector('.insights-panel')?.textContent?.includes('e4'),
		{ timeout: 60_000 }
	);
	const card = (await page.locator('.insights-panel .card').first().textContent()) ?? '';
	expect(card).toContain('You played e4');
	expect(card).toContain('Win chance');
	await expect(page.locator('.insights-panel .chip').first()).toBeVisible();
});
