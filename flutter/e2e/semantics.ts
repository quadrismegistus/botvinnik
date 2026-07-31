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
//   * The name is USUALLY in `textContent` and sometimes only in
//     `aria-label` — so both are matched. Flutter picks per widget: a button
//     gets its name from the content and leaves the attribute null (a first
//     attempt matched the attribute alone and found nothing), while the
//     `NavigationBar` at phone width emits `role="tab"` nodes that are
//     textually EMPTY and carry `aria-label="Practice"`. Matching content
//     alone therefore worked on the desktop rail and made the entire phone
//     layout unreachable, which is how this was found.
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
 * Every name a leaf node answers to — its aria-label and each line of its text.
 *
 * Defined as SOURCE rather than a function because it runs inside the page,
 * where nothing from this module is in scope; `count`, `tap` and `controls`
 * all inline it so a match can never mean three different things.
 *
 * Lines rather than the whole string, and both sources split the same way: a
 * tab's content is "Settings\nTab 4 of 4", and callers should be able to say
 * 'Settings' without restating Flutter's positional suffix, which moves
 * whenever a tab is added. ANY line rather than the first, because a `Badge`
 * renders BEFORE its child — the moment a puzzle is due, the Practice tab
 * reads "1\nPractice\nTab 2 of 4" on the desktop rail and carries the
 * aria-label "1\nPractice" on the phone bar.
 */
const NAMES = `((n) => {
	if (n.children.length) return [];
	const out = [];
	for (const s of [n.getAttribute('aria-label'), n.textContent]) {
		const v = (s || '').trim();
		if (v) out.push(v, ...v.split('\\n').map((line) => line.trim()));
	}
	return out.filter(Boolean);
})`;

/** How many leaf controls answer to [text]. */
export function count(page: Page, text: string): Promise<number> {
	return page.evaluate(
		([wanted, src]) => {
			const names = eval(src) as (n: Element) => string[];
			return [...document.querySelectorAll('flt-semantics')].filter((n) =>
				names(n).includes(wanted)
			).length;
		},
		[text, NAMES] as const
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
	await page.evaluate(
		([wanted, src]) => {
			const names = eval(src) as (n: Element) => string[];
			const hit = [...document.querySelectorAll('flt-semantics')].find((n) =>
				names(n).includes(wanted)
			);
			(hit as HTMLElement).click();
		},
		[text, NAMES] as const
	);
}

/**
 * Every leaf control on screen — for writing a test, and for putting in a
 * failure message. These selectors are widget TEXT, so a copy change renames
 * them, and the first thing anyone debugging a miss needs is the real list.
 *
 * The first name of each node, so the list reads as the labels a caller would
 * pass rather than every alias of every one.
 */
export async function controls(page: Page): Promise<string[]> {
	return page.evaluate(
		(src) => {
			const names = eval(src) as (n: Element) => string[];
			return [...document.querySelectorAll('flt-semantics')]
				.map((n) => names(n)[0])
				.filter(Boolean);
		},
		NAMES
	);
}
