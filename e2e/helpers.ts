import type { Page } from '@playwright/test';

// Hydrated + engine booted, on the CURRENT page (after any goto/reload).
// Chessground renders its pieces only after mount → a safe "interactive"
// signal. The tree renders inline in the always-open Lines card; its playable
// nodes only exist after the engine's first lines arrive, which proves the
// engine booted.
export async function waitForEngineReady(page: Page) {
	await page.waitForSelector('.board-wrap .board piece', { timeout: 90_000 });
	await page.waitForSelector('.lines-tree svg g.node.playable', { timeout: 90_000 });
	await page.waitForTimeout(300);
}

// switch the sidebar to a mode via the ModeBar segmented control
export async function openMode(page: Page, label: 'Play' | 'Practice' | 'Review') {
	await page.locator('.modebar button', { hasText: label }).click();
	await page.waitForTimeout(300);
}

export async function waitForApp(page: Page) {
	await page.goto('/');
	await waitForEngineReady(page);
}

// click a board square by file (0 = a) and rank (1-8)
export async function clickSquare(page: Page, file: number, rank: number) {
	const box = await page.locator('.board-wrap .board').boundingBox();
	if (!box) throw new Error('board not found');
	const sq = box.width / 8;
	await page.mouse.click(box.x + (file + 0.5) * sq, box.y + (8 - rank + 0.5) * sq);
	await page.waitForTimeout(250);
}

export async function playMove(
	page: Page,
	from: [number, number],
	to: [number, number],
	settleMs = 0
) {
	await clickSquare(page, from[0], from[1]);
	await clickSquare(page, to[0], to[1]);
	if (settleMs) await page.waitForTimeout(settleMs);
}

// a practice puzzle with a known clean answer: the d2 rook takes the hanging
// queen on d8 with check
export const ROOK_TAKES_QUEEN_ITEM = {
	id: 'k2q4/8/8/8/8/8/3R4/K7 w - - 0 1',
	fen: 'k2q4/8/8/8/8/8/3R4/K7 w - - 0 1',
	playedSan: 'Rd7',
	playedUci: 'd2d7',
	bestSan: 'Rxd8+',
	bestUci: 'd2d8',
	bestPv: ['d2d8', 'a8b7'],
	evalBestPawns: 9,
	mateBest: null,
	wcBest: 97,
	drop: 25,
	depth: 16,
	createdAt: '2026-07-10T00:00:00.000Z',
	box: 0,
	dueAt: '2026-07-10T00:00:00.000Z',
	attempts: 0,
	correct: 0
};

export async function seedPracticeItem(page: Page, item: object = ROOK_TAKES_QUEEN_ITEM) {
	await page.addInitScript((it) => {
		localStorage.setItem('botvinnik-practice-v1', JSON.stringify([it]));
	}, item);
}

export async function openSidePanel(page: Page, title: string) {
	await page.locator('.side-panel .title-btn', { hasText: title }).click();
	await page.waitForTimeout(300);
}
