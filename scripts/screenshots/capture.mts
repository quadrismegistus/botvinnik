// Screenshots of the running web app, for README.md and issues (#150).
//
//   cd flutter && ./build-web.sh && (cd build/web && python3 -m http.server 4400)
//   npx tsx scripts/screenshots/capture.mts
//
// or in one step, reusing the e2e config's own server:
//
//   npm run shots
//
// Written as a TOOL rather than a Playwright spec on purpose: it asserts
// nothing, and a green suite that quietly wrote the wrong pictures would be
// worse than a red one. It does share `flutter/e2e/semantics.ts` — the app
// renders to a canvas, so turning Flutter's semantics tree on is the only way
// to reach a control, and that file is where the three ways to get that wrong
// are already written down. (`expect.poll` from @playwright/test works fine
// outside the runner; that was checked, not assumed.)
//
// THREE RULES, each from a hazard in #150:
//
//   * Output goes to `docs/screenshots/`, NEVER `flutter/assets/`. That
//     directory is staged into `flutter/web/` by stage-web-assets.sh and
//     served to every visitor — a handful of PNGs there is pure payload for
//     people who will never see them.
//
//   * A fresh `BrowserContext` per shot, so there is no localStorage,
//     IndexedDB or archive to leak. The data in these pictures is staged, and
//     staged two different ways: the board, the grades and the archived game
//     come from a BOT-VS-BOT game the script starts (Squarefish plays
//     Squarefish — no human name appears anywhere, and the app itself refuses
//     to rate such a game), and the practice queue comes from a hand-written
//     backup file restored through Settings. Nothing here can reach a real
//     chess.com or lichess username because the profile it would live in does
//     not exist in these contexts.
//
//   * WebP at deviceScaleFactor 1, via CDP's `Page.captureScreenshot` rather
//     than Playwright's (which only writes PNG/JPEG). These files live in git
//     forever; a retina PNG of this app is ~8x the bytes for no more
//     information. No image dependency is added — Chromium already encodes
//     WebP.
//
// WHAT IS NOT REPRODUCIBLE, and why that is acceptable: Squarefish re-rolls
// its seed every game, so the positions differ run to run. The FRAMING is
// deterministic (which panels are open, which screen, the viewport); the
// chess is not. The one place it matters — blind mode, which is only legible
// beside the same position sighted — is handled by shooting both from one
// context with a toggle between them.
//
// KNOWN GAPS in the semantics tree, both found here:
//   * A badged tab reads "1\nPractice\nTab 2 of 4", so semantics.ts's
//     first-line match missed it. Fixed there, in `count`.
//   * The New Game sheet's seat chips (`You` / `Pick a bot…`) are
//     `ChoiceChip`s that reach the tree as role=checkbox with NO accessible
//     name at all. There is nothing to match on, so the roster shot clicks
//     the 4th checkbox positionally — and then asserts the roster actually
//     opened, because a positional click that lands on the wrong control is
//     otherwise indistinguishable from a working one.

import { mkdirSync, writeFileSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { chromium, type BrowserContext, type Page } from 'playwright';

import { controls, enableSemantics, tap, waitForControl } from '../../flutter/e2e/semantics.ts';

const BASE = process.env.SHOTS_URL ?? 'http://localhost:4400';
const OUT = fileURLToPath(new URL('../../docs/screenshots/', import.meta.url));

/** The two layouts. The app is genuinely different at each, not just narrower. */
const VIEWPORTS = {
	phone: { width: 390, height: 844 },
	desktop: { width: 1440, height: 900 }
} as const;
type Viewport = keyof typeof VIEWPORTS;

/** Panel ids, from `_PlayTabState._tabs` in flutter/lib/main.dart. */
const PANEL = { insights: 0, lines: 1, tree: 2, chart: 3, moves: 4, book: 5, humans: 6 };

/** Both seats are bots, so the game plays itself and no human ever appears. */
const SELF_PLAY = { white: 'squarefish-1000', black: 'squarefish-1000' };

/**
 * One staged practice puzzle: a real position, invented provenance.
 *
 * The shape is `PracticeItem` (brain/practice.ts) inside the backup envelope
 * `BackupService.importJson` accepts (flutter/lib/stores/backup.dart). Motifs
 * are deliberately absent — practice.ts recomputes them on load whenever
 * `tagV` is behind MOTIF_TAGS_VERSION, so supplying them would only be a
 * second copy to rot.
 */
const PUZZLE_FEN = 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
const STAGED_BACKUP = JSON.stringify({
	app: 'botvinnik',
	version: 1,
	exportedAt: '2026-01-01T00:00:00.000Z',
	practice: [
		{
			id: PUZZLE_FEN,
			fen: PUZZLE_FEN,
			playedSan: 'Ng5', playedUci: 'f3g5',
			bestSan: 'O-O', bestUci: 'e1g1', bestPv: ['e1g1', 'f8c5', 'd2d3'],
			evalBestPawns: 0.2, mateBest: null, wcBest: 52, drop: 21, depth: 18,
			createdAt: '2026-01-01T00:00:00.000Z',
			box: 0, dueAt: '2026-01-01T00:00:00.000Z', attempts: 0, correct: 0
		}
	],
	games: []
});

interface Seed {
	/** persona ids per seat; null means the human plays it */
	bots?: { white?: string | null; black?: string | null };
	/** panel ids to open — see PANEL */
	panels?: number[];
	blind?: boolean;
	/** ms the bot waits before moving; 0 makes a whole self-play game ~20s */
	delayMs?: number;
}

/**
 * The settings a shot needs, as an init script that runs before any app code.
 *
 * `shared_preferences_web` JSON-encodes every value under a `flutter.` prefix,
 * so a String setting is double-encoded — see flutter/e2e/helpers.ts, which
 * learned this the hard way. An init script rather than goto-then-evaluate,
 * for the reason given there: the service worker reloads the page once it
 * takes control, and an evaluate landing in that window dies.
 *
 * SOURCE, not a callback, and this is the whole reason the first version of
 * this script silently did nothing. Playwright serializes the function you
 * hand it — but under `tsx` what it gets is esbuild's OUTPUT, and esbuild's
 * `keepNames` rewrites an inner named arrow as `__name((k, v) => …, "put")`.
 * `__name` is a bundler helper that does not exist in the page, so the init
 * script died with a ReferenceError nobody can see (addInitScript surfaces no
 * error), every seeded setting was missing, and the app came up on its
 * defaults looking perfectly healthy. Verified, not guessed: printing
 * `fn.toString()` under tsx shows the wrapper, and the identical file run
 * under plain `node` seeds correctly.
 *
 * The same trap is waiting in any `page.evaluate` here that declares a named
 * inner function. Keep the callbacks in this file free of them.
 */
function seedScript(s: Seed): string {
	const prefs: Record<string, string> = {};
	if (s.bots) {
		prefs['botvinnik-bot-v1'] = JSON.stringify({
			white: s.bots.white ?? null,
			black: s.bots.black ?? null
		});
	}
	if (s.panels) prefs['botvinnik-panels'] = s.panels.join(',');
	if (s.blind !== undefined) prefs['botvinnik-blind'] = s.blind ? '1' : '0';
	if (s.delayMs !== undefined) prefs['botvinnik-bot-delay'] = String(s.delayMs);
	return Object.entries(prefs)
		.map(([k, v]) =>
			`localStorage.setItem(${JSON.stringify('flutter.' + k)}, ${JSON.stringify(
				JSON.stringify(v)
			)});`
		)
		.join('\n');
}

/**
 * Load past service-worker installation, as flutter/e2e/helpers.ts does: the
 * first load installs the worker and the bootstrap reloads once it takes
 * control, which destroys any execution context in that window.
 */
async function open(ctx: BrowserContext, s: Seed = {}): Promise<Page> {
	const page = await ctx.newPage();
	const content = seedScript(s);
	if (content) await page.addInitScript({ content });
	await page.goto(BASE);
	await page.waitForTimeout(8000);
	await page.goto(BASE);
	await page.waitForTimeout(4000);
	await enableSemantics(page as never);
	return page;
}

/**
 * Tap the control reading [text], and say what WAS on screen when it is not.
 *
 * These selectors are widget text, so a copy change renames them; a bare
 * 20-second poll timeout tells whoever is debugging that nothing matched but
 * not what they should have matched instead.
 */
async function press(page: Page, text: string, settleMs = 1500) {
	try {
		await tap(page as never, text);
	} catch (e) {
		const found = await controls(page as never);
		throw new Error(`no control reading "${text}". On screen:\n  ${found.join('\n  ')}`, {
			cause: e
		});
	}
	await page.waitForTimeout(settleMs);
}

/** Everything on screen as one string — the semantics root concatenates it. */
const screenText = (page: Page) =>
	page.evaluate(() => document.querySelector('flt-semantics')?.textContent ?? '');

/** The game-over recap, whatever the result was. */
const OVER = /Rematch/;

/**
 * Poll [screenText] until [re] matches, or fail with what was there instead.
 *
 * [every] matters more than it looks for anything watching a self-playing
 * game: the Insights card only ever shows the LAST move, so a poll slower than
 * the bots is a sampler that can miss every interesting move in a game and
 * then report a timeout. The first version polled at 1.5s against bots moving
 * with no delay at all, and watched a whole game go by without seeing one.
 */
async function waitForText(
	page: Page,
	re: RegExp,
	{ timeoutMs = 180_000, every = 600, bailWhenOver = true } = {}
) {
	const until = Date.now() + timeoutMs;
	for (;;) {
		const text = await screenText(page);
		if (re.test(text)) return text;
		// Say "the game finished first" rather than "timed out": one is a
		// re-run, the other is a broken selector, and they look identical
		// from a bare timeout.
		if (bailWhenOver && OVER.test(text)) {
			throw new Error(
				`the self-play game ended before ${re} ever matched — re-run.\n` +
					`screen read:\n${text.slice(0, 800)}`
			);
		}
		if (Date.now() > until) {
			throw new Error(`timed out waiting for ${re}\nscreen read:\n${text.slice(0, 1200)}`);
		}
		await page.waitForTimeout(every);
	}
}

/**
 * Let the self-playing game run for [ms], and fail if it finishes first.
 *
 * For the one shot with nothing to trigger on: the Lines Tree draws no text,
 * so there is no ply count in the semantics tree to poll for. Waiting is the
 * honest mechanism, but waiting BLINDLY is not — a game that ended would leave
 * this photographing a game-over recap under a tree that stopped growing.
 */
async function playFor(page: Page, ms: number) {
	const until = Date.now() + ms;
	while (Date.now() < until) {
		await page.waitForTimeout(2000);
		if (OVER.test(await screenText(page))) {
			throw new Error(
				`the self-play game ended after ${Math.round((ms - (until - Date.now())) / 1000)}s ` +
					`of the ${ms / 1000}s this shot wanted — re-run.`
			);
		}
	}
}

const written: { file: string; bytes: number }[] = [];

/**
 * Shoot the viewport as WebP.
 *
 * Playwright's own `screenshot()` cannot write WebP, and adding sharp or
 * pngquant to compress afterwards would put an image toolchain in the repo's
 * dependencies for six pictures. Chromium encodes WebP natively and CDP is
 * how you ask it to.
 */
async function shoot(page: Page, name: string, viewport: Viewport) {
	const cdp = await page.context().newCDPSession(page);
	const { data } = await cdp.send('Page.captureScreenshot', {
		format: 'webp',
		quality: 82,
		captureBeyondViewport: false
	});
	await cdp.detach();
	const file = `${OUT}${name}-${viewport}.webp`;
	writeFileSync(file, Buffer.from(data, 'base64'));
	const bytes = statSync(file).size;
	written.push({ file: `docs/screenshots/${name}-${viewport}.webp`, bytes });
	console.log(`  ${name}-${viewport}.webp  ${(bytes / 1024).toFixed(1)} KB`);
}

/**
 * A move graded mistake or worse — what the Insights shot waits for.
 *
 * The card is the app's most distinctive output and it says nothing
 * interesting until something has gone wrong, so "wait a while and hope" is
 * not good enough. The nouns are `CLASS[...].noun` from
 * brain/classifications.ts; matching those rather than a glyph is deliberate,
 * since three of the glyphs are substituted with Material icons on the Dart
 * side and never reach the accessible name.
 *
 * No trailing `\b`, and that is not a style choice: the semantics tree
 * concatenates the card's spans with no separator, so a mistake reads as
 * "Bd6? a mistake20%Best line…". Between "e" and "2" there is no word
 * boundary, so the obvious `\b…\b` matched NOTHING and looked exactly like a
 * game in which no one ever erred. A negative lookahead for a letter is what
 * the boundary was actually for — keeping "a miss" from matching "a missed…".
 */
const MISTAKE = /\b(a blunder|a mistake|a miss)(?![a-z])/;

// ---------------------------------------------------------------- the shots

/**
 * The full roster, grouped by family.
 *
 * Note what this picture is honest about: it is the WEB roster, so it shows
 * six families and 32 personas. ChessGPT and Dala are `nativeOnly`
 * (brain/bots.ts) and Dala has no implementation on any platform, so neither
 * belongs in a screenshot taken from a browser.
 */
async function shotRoster(ctx: BrowserContext, viewport: Viewport) {
	const page = await open(ctx);
	await press(page, 'New game');

	// The Black seat's bot chip. See the note at the top: these chips have no
	// accessible name, so there is nothing to match on but position.
	await page.evaluate(() => {
		const chips = [...document.querySelectorAll('flt-semantics[role=checkbox]')];
		if (chips.length < 4) throw new Error(`expected 4 seat chips, saw ${chips.length}`);
		(chips[3] as HTMLElement).click();
	});
	// The assertion that makes the positional click safe.
	await waitForControl(page as never, 'Browse all…');
	await press(page, 'Browse all…', 2500);
	await shoot(page, 'roster', viewport);
}

/** The SAN of the move the Insights card is currently grading. */
async function gradedMove(page: Page): Promise<string> {
	const text = await screenText(page);
	return (text.split('Book')[1] ?? '').trim().split(/[\s?!]/)[0] ?? '';
}

/**
 * A mid-game board with the overlays on, beside the Insights card for a move
 * that has just gone wrong — and then the SAME position blind.
 *
 * Both from one context and, harder, from one POSITION. #150 asks for blind
 * mode "ideally paired with the same position sighted", and a self-playing
 * game never stands still: the board only waits when it is a human's turn, and
 * a human cannot move here because the board is painted pixels with no
 * semantics. The first version toggled blind and shot again, which landed two
 * plies later on a different position and quietly answered a different
 * question.
 *
 * So: raise the bot delay to its 3s ceiling (settings_store clamps it there),
 * wait for the grade, and take both frames inside one delay window — the two
 * screenshots and the toggle together cost well under a second. Whether that
 * held is then CHECKED rather than assumed, by comparing the graded SAN
 * either side. A warning, not a throw: both frames are honest pictures of the
 * app whether or not they pair, and only the pairing is lost.
 */
async function shotPlay(ctx: BrowserContext, viewport: Viewport) {
	const page = await open(ctx, { bots: SELF_PLAY, panels: [PANEL.insights], delayMs: 3000 });
	await waitForText(page, MISTAKE, { every: 400 });

	const before = await gradedMove(page);
	await shoot(page, 'insights', viewport);
	// `hidingHelp = blind && !review && !gameOver` (game_controller.dart), so
	// this must happen while the game is still running — which it is, since
	// the poll above stops on a grade rather than on a result.
	await press(page, 'Blind mode off', 250);
	await shoot(page, 'blind', viewport);
	const after = await gradedMove(page);

	if (before !== after) {
		console.warn(
			`  ! the game moved on between the two frames (${before} → ${after}), ` +
				`so blind-${viewport} is not the same position as insights-${viewport}`
		);
	}
}

/** The Lines Tree — DESKTOP ONLY, and the skip is the point.
 *
 * At phone width the panel selector is single-select and drives a local
 * `int _view` in `main.dart`; only the wide, multi-select row reads the
 * persisted `botvinnik-panels`. `settings_store.dart` says so — "which panels
 * are open on a WIDE window". So seeding `panels: [PANEL.tree]` is a no-op
 * here and Insights, index 0, wins by default.
 *
 * That shipped once: `lines-tree-phone.webp` was a picture of the Insights
 * panel under a filename saying otherwise, and it went unnoticed because this
 * is the one shot with no content assertion — the Tree draws no text to poll
 * for. Skipping is honest; a wrong picture is not, and it would live in git
 * for good.
 */
async function shotTree(ctx: BrowserContext, viewport: Viewport) {
	if (viewport === 'phone') {
		console.log('  skipped: the phone layout cannot be steered to the Tree panel');
		return;
	}
	// The Tree panel draws no text, so there is no ply counter to poll for —
	// this is the one shot timed rather than triggered. At 2s a move, ~70s is
	// deep enough for the tree to have a shape and short of where a Squarefish
	// 1000 game usually ends; `bailWhenOver` turns "it ended anyway" into a
	// re-run message rather than a picture of a game-over recap.
	const page = await open(ctx, { bots: SELF_PLAY, panels: [PANEL.tree], delayMs: 2000 });
	await playFor(page, 70_000);
	await shoot(page, 'lines-tree', viewport);
}

/** A finished game, opened in Review — the analysis board over the archive. */
async function shotReview(ctx: BrowserContext, viewport: Viewport) {
	const page = await open(ctx, { bots: SELF_PLAY, delayMs: 0 });
	await waitForText(page, /Review this game/, {
		timeoutMs: 300_000,
		bailWhenOver: false
	});
	await press(page, 'Review this game', 4000);
	await shoot(page, 'review', viewport);
}

/**
 * A puzzle mid-drill, from the staged backup.
 *
 * Restore rather than a direct write: the practice collection lives in
 * sqflite's `kv` table, which on the web is sqlite3-over-wasm persisted into
 * IndexedDB — not something a page script can seed. Settings → "Restore from
 * a backup" is the supported way in, and `file_selector_web` builds a real
 * `<input type=file>`, so Playwright's filechooser event is a first-class
 * observer of it.
 */
async function shotPractice(ctx: BrowserContext, viewport: Viewport) {
	const page = await open(ctx);
	await press(page, 'Settings');

	const chooser = page.waitForEvent('filechooser', { timeout: 30_000 });
	await tap(page as never, 'Restore from a backup');
	(await chooser).setFiles({
		name: 'staged-backup.json',
		mimeType: 'application/json',
		buffer: Buffer.from(STAGED_BACKUP)
	});
	// The snackbar states the counts, so this asserts the restore instead of
	// sleeping through it.
	await waitForText(page, /Restored 0 games and 1 puzzle/, {
		timeoutMs: 30_000,
		bailWhenOver: false
	});

	await press(page, 'Practice', 6000);
	const found = await controls(page as never);
	if (!found.some((c) => /Hint/.test(c))) {
		throw new Error(`the drill did not come up; controls were:\n${found.join('\n')}`);
	}
	await shoot(page, 'practice', viewport);
}

const SHOTS = {
	roster: shotRoster,
	play: shotPlay,
	tree: shotTree,
	review: shotReview,
	practice: shotPractice
};

// ------------------------------------------------------------------- driver

const only = process.argv.slice(2);
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch();
try {
	for (const [viewport, size] of Object.entries(VIEWPORTS) as [Viewport, { width: number; height: number }][]) {
		for (const [name, run] of Object.entries(SHOTS)) {
			if (only.length && !only.includes(name)) continue;
			console.log(`${name} @ ${viewport}`);
			// A FRESH context per shot: separate storage, separate service
			// worker, nothing carried over. deviceScaleFactor 1 keeps these
			// out of retina territory — see the header.
			const ctx = await browser.newContext({ viewport: size, deviceScaleFactor: 1 });
			try {
				await run(ctx, viewport);
			} finally {
				await ctx.close();
			}
		}
	}
} finally {
	await browser.close();
}

const total = written.reduce((n, w) => n + w.bytes, 0);
console.log(`\n${written.length} files, ${(total / 1024).toFixed(1)} KB total`);
