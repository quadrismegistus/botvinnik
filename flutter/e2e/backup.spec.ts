// The browser save path, exercised as a real download (#158).
//
// `lib/stores/files_web.dart` hand-rolls it: a Blob, an `<a download>`,
// append-before-click, `revokeObjectURL`. It is the path MOST users take,
// because the web is where the app mostly runs, and it had no behavioural test
// at all. What was already guarded is narrow and worth stating so this is not
// mistaken for more than it is: `flutter analyze` and the dart2js build both
// compile the file, so signature drift between `TextFileSaver` and the web
// branch cannot ship. What was unguarded is everything INSIDE — the bytes, the
// MIME type, the filename, and whether a download is produced at all.
//
// A widget test cannot reach it: `flutter test` never compiles files_web.dart,
// and `flutter test --platform chrome` cannot either, because a web-only file
// in the compile set fails the VM run (see the note on #158). Playwright can,
// because what the code produces is not a Flutter concept at all — it is a
// browser download, and `page.waitForEvent('download')` is a first-class
// observer of one.
//
// Reaching the button needs the semantics tree; see semantics.ts.
//
//   npx playwright test -c flutter/playwright.config.ts backup.spec.ts

import { test, expect } from '@playwright/test';

import { loadSettled } from './helpers';
import { controls, enableSemantics, tap, waitForControl } from './semantics';

test('backing up produces a real download of the real archive', async ({
	page
}) => {
	await loadSettled(page);
	await enableSemantics(page);

	// Fail with the tree in the message rather than a bare timeout: these
	// selectors are widget TEXT, so the first thing anyone debugging this needs
	// is what the controls actually read now.
	const found = await controls(page);
	expect(found.join(' | '), 'the Settings tab is not on screen').toContain(
		'Settings'
	);

	await tap(page, 'Settings');
	await waitForControl(page, 'Back up everything');

	const download = page.waitForEvent('download', { timeout: 30_000 });
	await tap(page, 'Back up everything');
	const file = await download;

	// The filename the app builds (backup.dart's backupFilename), not a
	// browser-invented one. A Blob URL downloads as a uuid unless the anchor's
	// `download` attribute is set, so this is the assertion that the attribute
	// is both set and carrying the right value.
	expect(file.suggestedFilename()).toMatch(
		/^botvinnik-backup-\d{4}-\d{2}-\d{2}\.json$/
	);

	// The BYTES. This is what nothing checked: the Blob is constructed from a
	// JS-interop string conversion, and an empty or mangled one produces a
	// download that looks entirely successful.
	const stream = await file.createReadStream();
	const chunks: Buffer[] = [];
	for await (const c of stream) chunks.push(c as Buffer);
	const text = Buffer.concat(chunks).toString('utf8');

	expect(text.length).toBeGreaterThan(2);
	const parsed = JSON.parse(text);
	expect(parsed.app).toBe('botvinnik');
	expect(Array.isArray(parsed.practice)).toBe(true);
	expect(Array.isArray(parsed.games)).toBe(true);
});

test('the anchor does not outlive the download it was made for', async ({
	page
}) => {
	// `anchor.remove()` and `revokeObjectURL` after the click. Neither is
	// cosmetic: an anchor left in the body accumulates one node per backup, and
	// a Blob URL that is never revoked pins the whole exported archive in
	// memory for the life of the page — and the archive is the one file here
	// that grows without bound.
	//
	// Observable from outside because the anchor is real DOM, unlike everything
	// else the app draws.
	await loadSettled(page);
	await enableSemantics(page);
	await tap(page, 'Settings');
	await waitForControl(page, 'Back up everything');

	const before = await page.evaluate(
		() => document.querySelectorAll('a[download]').length
	);

	const download = page.waitForEvent('download', { timeout: 30_000 });
	await tap(page, 'Back up everything');
	await download;

	const after = await page.evaluate(
		() => document.querySelectorAll('a[download]').length
	);
	expect(after).toBe(before);
});

// WHAT THIS FILE DOES NOT COVER, so it is not mistaken for complete.
//
// Mutation-tested against files_web.dart. These three die:
//
//   * `..download = filename` removed — the browser names the file a uuid.
//   * the Blob built from '' instead of the export — a download that succeeds
//     and contains nothing.
//   * `anchor.remove()` removed — a node accumulates per backup.
//
// This one SURVIVES: moving `body.append(anchor)` to after `anchor.click()`.
// The append-before-click ordering is real defensive code — its comment,
// inherited from the Svelte version, says a detached anchor's click is ignored
// in some browsers — but Chromium is not one of them, and Chromium is the only
// browser this config runs. So the ordering is untested here and cannot be
// tested here. Firefox and WebKit projects would cover it; that is a bigger
// change than this issue, and worth noting rather than quietly implying.
//
// `revokeObjectURL` is likewise unobservable from outside: a leaked Blob URL
// still works, which is exactly why leaking one is easy to do.
