import { expect, test } from '@playwright/test';
import { waitForApp } from './helpers';

// The PWA promise: after one online visit, the app — engine included — works
// with no network at all. This exercises the service worker's precache (build
// + /wasm/) end to end: offline reload, board renders, engine produces lines.
test('offline: the app and engine work with no network', async ({ page, context }) => {
	await waitForApp(page);
	// the service worker finishes precaching before `ready` resolves
	await page.evaluate(() => navigator.serviceWorker.ready);

	await context.setOffline(true);
	await page.reload();
	// the reload must actually be served BY the service worker — otherwise a
	// quirk in offline emulation could let the live server answer and the test
	// would prove nothing
	expect(await page.evaluate(() => navigator.serviceWorker.controller !== null)).toBe(true);
	await page.waitForSelector('.board-wrap .board piece', { timeout: 30_000 });
	await page.waitForSelector('.lines-tree svg g.node.playable', { timeout: 60_000 });
	await context.setOffline(false);
});
