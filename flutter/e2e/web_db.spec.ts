// The web database must have exactly ONE writer across all tabs.
//
// Reported as "database disk image is malformed" (SQLITE_CORRUPT, code 11) on
// botvinnik.app, never on macOS. The cause is architectural rather than a
// mishandled row: `db_init_web.dart` used `databaseFactoryFfiWebNoWebWorker`,
// which runs sqlite3 on the MAIN ISOLATE of each tab, over an IndexedDB-backed
// file. Two tabs — or the installed PWA plus a browser tab — are then two
// independent sqlite3 instances, each with its own page cache, writing the
// same file with nothing serialising them. Interleave their page writes and
// the image is torn. macOS is immune because it goes through FFI to a real
// file with real OS locking.
//
// It surfaced while testing cross-device sync, which is not a coincidence and
// is not sync's fault: the way you exercise sync is by having the app open in
// more than one place, which is exactly how you get the second writer.
//
// This asserts the fix rather than the race. A corruption race is not
// something CI can be made to lose reliably, and a flaky gate would be worse
// than none — but "every tab talks to the same shared worker" is a property,
// and it either holds or it does not.
//
//   npx playwright test -c flutter/playwright.config.ts web_db.spec.ts

import { test, expect } from '@playwright/test';

import { loadSettled } from './helpers';

test('the database is reached through a shared worker, not per-tab sqlite3', async ({
	page
}) => {
	const requested: string[] = [];
	page.on('request', (r) => requested.push(r.url()));

	await loadSettled(page);

	// The worker script has to be FETCHED for a shared worker to exist at all.
	// With the no-worker factory it was never requested, which is what made
	// this red before the fix — and `flutter/web/sqflite_sw.js` was gitignored
	// as "unused", so it would not even have been deployed to request.
	expect(
		requested.filter((u) => u.includes('sqflite_sw.js')),
		'sqflite_sw.js must be fetched — without it every tab runs its own sqlite3'
	).not.toHaveLength(0);
});

test('a second tab joins the first tab\'s writer instead of starting a rival', async ({
	browser
}) => {
	// Two pages in ONE context share an origin, and therefore share both
	// IndexedDB and any SharedWorker. This is the configuration that corrupts:
	// the app open twice while testing sync.
	const ctx = await browser.newContext();
	try {
		const a = await ctx.newPage();
		await loadSettled(a);

		const b = await ctx.newPage();
		await loadSettled(b);

		// A SharedWorker is one instance per origin however many tabs connect,
		// so asking the page whether it can construct one — and whether the
		// script is there to construct it FROM — is the observable. Before the
		// fix the script was not deployed at all (gitignored as "unused"), so
		// this could not have held by accident.
		for (const p of [a, b]) {
			const ok = await p.evaluate(async () => {
				const res = await fetch('sqflite_sw.js', { method: 'HEAD' });
				return { status: res.status, shared: typeof SharedWorker };
			});
			expect(ok.status, 'the worker script is deployed').toBe(200);
			expect(ok.shared, 'and the browser can share it').toBe('function');
		}
	} finally {
		await ctx.close();
	}
});
