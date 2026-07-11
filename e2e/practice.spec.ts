import { expect, test } from '@playwright/test';
import { clickSquare, openSidePanel, seedPracticeItem, waitForApp } from './helpers';

test('practice loop: fail, retry, pass with insight card, continue the line', async ({ page }) => {
	await seedPracticeItem(page);
	await waitForApp(page);

	await openSidePanel(page, 'Practice');
	await page.locator('.practice-panel button', { hasText: 'Start practice' }).click();
	await page.waitForSelector('.practice-panel .toolbar');

	// fail: Ra2+ hangs around instead of taking the queen
	await clickSquare(page, 3, 2); // d2
	await clickSquare(page, 0, 2); // a2
	await page.waitForFunction(
		() => document.querySelector('.practice-panel .result')?.textContent?.includes('✗'),
		{ timeout: 90_000 }
	);
	const fail = (await page.locator('.practice-panel .result').textContent()) ?? '';
	expect(fail).toContain('drops');
	await expect(page.locator('.practice-panel .result .chip')).toBeVisible();
	// the insight card must NOT appear before reveal (it shows the answer)
	expect(await page.locator('.insights-panel .card').count()).toBe(0);

	// retry, then pass with the engine's move
	await page.locator('.practice-panel button', { hasText: 'Retry' }).click();
	await page.waitForTimeout(400);
	await clickSquare(page, 3, 2); // d2
	await clickSquare(page, 3, 8); // d8 -> Rxd8+
	await page.waitForFunction(
		() => document.querySelector('.practice-panel .result')?.textContent?.includes('✓'),
		{ timeout: 30_000 }
	);
	const pass = (await page.locator('.practice-panel .result').textContent()) ?? '';
	expect(pass).toContain('Rxd8+');
	expect(pass).toContain("the engine's move");
	// pass reveals the insight card with the free-capture explanation
	const card = (await page.locator('.insights-panel .card').textContent()) ?? '';
	expect(card).toContain("simply wins the queen");

	// continue: the engine replies, one move later is a fresh temporary puzzle
	await page.locator('.practice-panel button', { hasText: 'Continue' }).click();
	await page.waitForFunction(
		() =>
			document
				.querySelector('.practice-panel .toolbar .summary')
				?.textContent?.includes('Continuing the line'),
		{ timeout: 60_000 }
	);
	await clickSquare(page, 0, 1); // a1
	await clickSquare(page, 1, 2); // b2 — king move keeps the full-rook win
	await page.waitForFunction(
		() => /[✓✗]/.test(document.querySelector('.practice-panel .result')?.textContent ?? ''),
		{ timeout: 90_000 }
	);
	expect(await page.locator('.practice-panel .result').textContent()).toContain('✓');

	// spaced repetition counted only the stored puzzle, not the continuation
	const attempts = await page.evaluate(
		() => JSON.parse(localStorage.getItem('botvinnik-practice-v1') ?? '[]')[0].attempts
	);
	expect(attempts).toBe(2); // the fail and the pass, nothing from the line
});
