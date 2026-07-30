// The web database must have exactly ONE writer across all tabs.
//
// Reported as "database disk image is malformed" (SQLITE_CORRUPT, 11) on
// botvinnik.app, never on macOS. `db_init_web.dart` used
// `databaseFactoryFfiWebNoWebWorker`, which runs sqlite3 on the MAIN ISOLATE of
// each tab over an IndexedDB-backed file — so two tabs, or the installed PWA
// plus a browser tab, are two independent sqlite3 instances with two page
// caches writing one file, with nothing serialising them. macOS is immune: FFI
// to a real file, with real OS locking.
//
// It surfaced while testing cross-device sync, which is not sync's fault. The
// way you exercise sync is by having the app open in more than one place, and
// that is how you get the second writer.
//
// WHAT THIS ASSERTS, and why the first version of it was worthless: a review
// reverted the factory to the broken one and this file still passed. Both of
// its tests keyed on `sqflite_sw.js` being FETCHED — and the package's silent
// fallback (`new SharedWorker` throws → `new Worker`, one per tab) fetches the
// very same script. Asserting the script's presence tests the deploy, not the
// architecture. So it now proxies the constructors and asserts what the app
// actually built.
//
// The corruption race itself is deliberately not asserted: CI cannot be made to
// lose a race reliably, and a flaky gate is worse than none.
//
//   npx playwright test -c flutter/playwright.config.ts web_db.spec.ts

import { test, expect } from '@playwright/test';

import { loadSettled } from './helpers';

/** Record every Worker/SharedWorker the page constructs, before app code runs. */
const spyOnWorkers = `
  window.__built = [];
  for (const kind of ['Worker', 'SharedWorker']) {
    const Orig = window[kind];
    if (!Orig) continue;
    window[kind] = class extends Orig {
      constructor(url, opts) { super(url, opts); window.__built.push([kind, String(url)]); }
    };
  }
`;

type Built = [string, string][];
const builtFor = (page: import('@playwright/test').Page) =>
	page.evaluate(() => (window as unknown as { __built: Built }).__built);

test('the app constructs a SharedWorker for the database', async ({ page }) => {
	await page.addInitScript(spyOnWorkers);
	await loadSettled(page);

	const built = await builtFor(page);
	const db = built.filter(([, url]) => url.includes('sqflite_sw.js'));

	expect(db.length, `no database worker was built: ${JSON.stringify(built)}`)
		.toBeGreaterThan(0);
	// The discriminating assertion. The dedicated-worker fallback loads the SAME
	// url, so only the CONSTRUCTOR tells the two architectures apart.
	expect(
		db.map(([kind]) => kind),
		'a dedicated Worker here means one sqlite3 per tab — the original bug'
	).toContain('SharedWorker');
});

test('two tabs load sqlite3 once between them, not once each', async ({ browser }) => {
	// The property that actually prevents corruption, measured rather than
	// inferred: a SharedWorker is one instance per origin, so the second tab
	// must not pull down its own copy of the engine. With the fallback this
	// count rises with the number of tabs.
	const ctx = await browser.newContext();
	try {
		const wasmLoads: string[] = [];
		ctx.on('request', (r) => {
			if (r.url().includes('sqlite3.wasm')) wasmLoads.push(r.url());
		});

		const a = await ctx.newPage();
		await a.addInitScript(spyOnWorkers);
		await loadSettled(a);
		const afterFirst = wasmLoads.length;

		const b = await ctx.newPage();
		await b.addInitScript(spyOnWorkers);
		await loadSettled(b);

		expect(afterFirst, 'the first tab loads sqlite3').toBeGreaterThan(0);
		expect(
			wasmLoads.length,
			`the second tab loaded its own sqlite3 (${wasmLoads.length} total) — two writers`
		).toBe(afterFirst);

		// and it joined rather than built its own
		expect((await builtFor(b)).filter(([k, u]) => u.includes('sqflite_sw.js') && k === 'SharedWorker'))
			.not.toHaveLength(0);
	} finally {
		await ctx.close();
	}
});
