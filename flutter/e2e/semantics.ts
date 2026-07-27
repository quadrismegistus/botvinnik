// Driving the Flutter web UI from Playwright, through the accessibility tree.
//
// The app renders to a canvas, so there is nothing to click: `page.getByText`
// finds nothing, and this repo's own notes said Playwright "cannot assert
// behaviour" on it. That is only half true. Flutter web ships an off-screen
// `<flt-semantics-placeholder>` whose job is to let a screen reader turn the
// semantics tree on — and once it is on, the whole widget tree materialises as
// real DOM. Measured on this app: 37 `<flt-semantics>` nodes, of which 18 are
// leaves with `role="button"` — Undo, Redo, New game, "Blind mode off", the
// four bottom tabs, and every panel tab.
//
// So the UI IS reachable. Three things to know, each learned the hard way:
//
//   * The text is in `textContent`, NOT in `aria-label`. Flutter leaves
//     aria-label null and lets the accessible name come from the content. A
//     first attempt matched on the attribute and found nothing at all.
//
//   * Match LEAVES. Semantics nest, and an ancestor's textContent is the
//     concatenation of everything beneath it — the root node here reads as the
//     entire screen's text in one string. Anything less specific selects that
//     ancestor and the click lands nowhere useful.
//
//   * Never build a CSS attribute selector out of these. Several labels
//     contain a newline (a tab is "Settings\nTab 4 of 4"), and a raw newline
//     inside `[aria-label="…"]` is a CSS parse error — "Unsupported token
//     BADSTRING" — which reads like a missing element rather than a bad query.
//     Matching in-page is just a string comparison.
//
// Two honest limits. The BOARD is not reachable: it is painted pixels with no
// semantics, so dragging a piece is still out of scope and
// test/support/game_harness.dart remains the right tool for anything about
// move legality or game state. And turning semantics on is a real mode change
// — the tree is an accessibility view, so this is a way to REACH controls, not
// evidence about how the app lays out normally.

import { expect, type Page } from '@playwright/test';

/**
 * Turn on Flutter's semantics tree and wait for it to be populated.
 *
 * The placeholder is positioned outside the viewport (it exists for assistive
 * tech, not for sighted users), so Playwright's own `click()` refuses it as
 * unactionable even with `force`. Dispatching in-page is the way in.
 */
export async function enableSemantics(page: Page) {
	await page.evaluate(() => {
		const ph = document.querySelector(
			'flt-semantics-placeholder'
		) as HTMLElement | null;
		ph?.click();
		ph?.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
		ph?.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
	});
	await expect
		.poll(() => page.locator('flt-semantics').count(), { timeout: 20_000 })
		.toBeGreaterThan(5);
}

/**
 * How many leaf controls read as [text].
 *
 * A tab's content is "Settings\nTab 4 of 4", so the first LINE is matched as
 * well as the whole string — callers should be able to say 'Settings' and mean
 * the Settings tab without restating Flutter's positional suffix, which moves
 * whenever a tab is added.
 */
export function count(page: Page, text: string): Promise<number> {
	return page.evaluate(
		(wanted) =>
			[...document.querySelectorAll('flt-semantics')].filter((n) => {
				if (n.children.length) return false;
				const t = (n.textContent || '').trim();
				return t === wanted || t.split('\n')[0] === wanted;
			}).length,
		text
	);
}

/** Wait until a control reading [text] exists. */
export async function waitForControl(page: Page, text: string) {
	await expect
		.poll(() => count(page, text), { timeout: 20_000 })
		.toBeGreaterThan(0);
}

/** Click the control reading [text]. */
export async function tap(page: Page, text: string) {
	await waitForControl(page, text);
	await page.evaluate((wanted) => {
		const hit = [...document.querySelectorAll('flt-semantics')].find((n) => {
			if (n.children.length) return false;
			const t = (n.textContent || '').trim();
			return t === wanted || t.split('\n')[0] === wanted;
		});
		(hit as HTMLElement).click();
	}, text);
}

/**
 * Every leaf control on screen — for writing a test, and for putting in a
 * failure message. These selectors are widget TEXT, so a copy change renames
 * them, and the first thing anyone debugging a miss needs is the real list.
 */
export async function controls(page: Page): Promise<string[]> {
	return page.evaluate(() =>
		[...document.querySelectorAll('flt-semantics')]
			.filter((n) => n.children.length === 0)
			.map((n) => (n.textContent || '').trim())
			.filter(Boolean)
	);
}
