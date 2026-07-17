import { expect, test } from '@playwright/test';
import { playMove } from './helpers';

// The narrow layout's grade strip is the whole feedback loop at peek height —
// it must say WHY a move was bad, not just flash a glyph.
test('mobile: the grade strip explains the mistake', async ({ page }) => {
	await page.setViewportSize({ width: 420, height: 800 });
	await page.goto('/');
	await page.waitForSelector('.board-wrap .board piece', { timeout: 90_000 });
	// engine-ready signal on mobile: the Lines tab's tree gets playable nodes
	// only after the first engine lines arrive
	await page.locator('.tab-strip button', { hasText: 'Lines' }).click();
	await page.waitForSelector('.lines-tree svg g.node.playable', { timeout: 90_000 });

	// walk into fool's mate far enough for a graded blunder: 1.f3 e5 2.g4??
	await playMove(page, [5, 2], [5, 3], 4000); // f3
	await playMove(page, [4, 7], [4, 5], 4000); // e5
	await playMove(page, [6, 2], [6, 4]); // g4 — allows Qh4#

	// the strip's second line carries the detector prose for the last move
	// (the full phrase, not /mate/ — "loses material" contains "mate")
	await expect(page.locator('.gs-note')).toContainText('allows immediate mate', {
		timeout: 20_000
	});
});
