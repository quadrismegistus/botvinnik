import { expect, test } from '@playwright/test';
import { openMode, playMove, waitForApp, waitForEngineReady } from './helpers';

test('a finished game auto-saves and is reviewable with labels and explanations', async ({
	page
}) => {
	await waitForApp(page);

	// fool's mate: 1.f3 e5 2.g4 Qh4# — pauses let each ply get graded/backfilled
	await playMove(page, [5, 2], [5, 3], 4000); // f3
	await playMove(page, [4, 7], [4, 5], 4000); // e5
	await playMove(page, [6, 2], [6, 4], 5000); // g4 (the blunder needs its backfill)
	await playMove(page, [3, 8], [7, 4], 2000); // Qh4#

	await expect(page.locator('.library button', { hasText: 'Games (1)' })).toBeVisible();

	// the game-over recap names the lapse (g4 allowed the mate)
	await expect(page.locator('.game-over .recap')).toContainText('allowed mate', {
		timeout: 15_000
	});

	await openMode(page, 'Review');
	const row = (await page.locator('.games-panel .row').first().textContent()) ?? '';
	expect(row).toContain('0-1');
	expect(row).toContain('2 moves');

	// review: the g4 blunder carries its label and the mate explanation
	await page.locator('.games-panel .row .primary', { hasText: 'Review' }).click();
	await page.waitForSelector('.rv-table .rv-mv');
	// classification counts summary lists a blunder
	await expect(page.locator('.rv-counts .rv-cname', { hasText: 'blunder' })).toBeVisible();
	await page.locator('.rv-table .rv-mv', { hasText: 'g4' }).click();
	await page.waitForTimeout(600);
	const card = (await page.locator('.rv-card').textContent()) ?? '';
	expect(card).toContain('blunder');
	expect(card).toContain('Qh4#');
	await page.locator('.games-panel button', { hasText: 'Exit' }).click();

	// the archive survives a reload
	await page.reload();
	await waitForEngineReady(page);
	await expect(page.locator('.library button', { hasText: 'Games (1)' })).toBeVisible();

	// and the stored PGN is a real game
	const pgn = await page.evaluate(
		() =>
			new Promise<string>((resolve) => {
				const req = indexedDB.open('botvinnik');
				req.onsuccess = () => {
					const r = req.result.transaction('games', 'readonly').objectStore('games').getAll();
					r.onsuccess = () => resolve((r.result[0] as { pgn: string })?.pgn ?? 'NONE');
				};
			})
	);
	expect(pgn).toContain('1. f3 e5 2. g4 Qh4# 0-1');
});
