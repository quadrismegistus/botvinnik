import { expect, test } from '@playwright/test';
import { openSidePanel, playMove, waitForApp } from './helpers';

test('a finished game auto-saves and is reviewable with labels and explanations', async ({
	page
}) => {
	await waitForApp(page);

	// fool's mate: 1.f3 e5 2.g4 Qh4# — pauses let each ply get graded/backfilled
	await playMove(page, [5, 2], [5, 3], 4000); // f3
	await playMove(page, [4, 7], [4, 5], 4000); // e5
	await playMove(page, [6, 2], [6, 4], 5000); // g4 (the blunder needs its backfill)
	await playMove(page, [3, 8], [7, 4], 2000); // Qh4#

	await expect(page.locator('.side-panel .badge', { hasText: '1' }).first()).toBeVisible();

	await openSidePanel(page, 'Games');
	const row = (await page.locator('.games-panel .row').first().textContent()) ?? '';
	expect(row).toContain('0-1');
	expect(row).toContain('2 moves');

	// review: the g4 blunder carries its label and the mate explanation
	await page.locator('.games-panel .row .primary', { hasText: 'Review' }).click();
	await page.waitForSelector('.games-panel .mv');
	await page.locator('.games-panel .mv', { hasText: 'g4' }).click();
	await page.waitForTimeout(600);
	const detail = (await page.locator('.games-panel .detail').textContent()) ?? '';
	expect(detail).toContain('blunder');
	expect(detail).toContain('Qh4#');
	await page.locator('.games-panel button', { hasText: 'Exit review' }).click();

	// the archive survives a reload
	await page.reload();
	await page.waitForSelector('.lines-tree svg g.node', { timeout: 90_000 });
	await expect(page.locator('.side-panel .badge', { hasText: '1' }).first()).toBeVisible();

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
