import { expect, test } from '@playwright/test';
import { ROOK_TAKES_QUEEN_ITEM, waitForApp } from './helpers';

test('backup exports, imports into a fresh profile, and dedupes', async ({ browser }) => {
	// context A: seeded data, export
	const a = await browser.newContext();
	const pageA = await a.newPage();
	await pageA.addInitScript((item) => {
		localStorage.setItem('botvinnik-practice-v1', JSON.stringify([item]));
	}, ROOK_TAKES_QUEEN_ITEM);
	await pageA.goto('http://localhost:4399/');
	await pageA.waitForSelector('.lines-tree svg g.node', { timeout: 90_000 });

	const [download] = await Promise.all([
		pageA.waitForEvent('download'),
		pageA.locator('.data-row button', { hasText: 'Export data' }).click()
	]);
	// the context's artifact dir dies with the context — save a stable copy
	const file = test.info().outputPath('backup.json');
	await download.saveAs(file);
	await a.close();

	// context B: fresh profile, import and merge
	const b = await browser.newContext();
	const pageB = await b.newPage();
	await pageB.goto('http://localhost:4399/');
	await pageB.waitForSelector('.lines-tree svg g.node', { timeout: 90_000 });

	await pageB.locator('.data-row input[type=file]').setInputFiles(file);
	await expect(pageB.locator('.import-msg')).toContainText('Imported 1 practice position');
	await expect(pageB.locator('.side-panel .badge', { hasText: 'due' })).toContainText('1 due / 1');

	// re-import is a no-op
	await pageB.locator('.data-row input[type=file]').setInputFiles(file);
	await expect(pageB.locator('.import-msg')).toContainText('Imported 0 practice positions');
	await b.close();
});
