// Shared fixtures for the Flutter web e2e suite.

import type { Page } from '@playwright/test';

/** Every legal move from the initial position, in UCI. */
export const OPENING_MOVES = [
	'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4', 'd2d3', 'd2d4',
	'e2e3', 'e2e4', 'f2f3', 'f2f4', 'g2g3', 'g2g4', 'h2h3', 'h2h4',
	'b1a3', 'b1c3', 'g1f3', 'g1h3'
];

export const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/**
 * Load the app past service-worker installation. The first load installs the
 * worker and the bootstrap reloads once it takes control; evaluating through
 * that navigation destroys the execution context mid-test.
 */
export async function loadSettled(page: Page) {
	await page.goto('/');
	await page.waitForTimeout(8000);
	await page.goto('/');
	await page.waitForTimeout(3000);
}

/**
 * Make [personaId] the opponent, playing White so it moves first and the test
 * needs no board input.
 *
 * An init script rather than goto-then-evaluate: the service worker reloads
 * the page once it takes control, and an evaluate landing in that window dies
 * with "execution context was destroyed". This runs before page scripts on
 * EVERY document, including the one after that reload.
 */
export async function seedPersona(page: Page, personaId: string) {
	await page.addInitScript((id) => {
		// shared_preferences_web stores JSON-encoded values under a 'flutter.'
		// prefix, so a string setting is double-encoded. The stored colour is
		// the BOT's.
		localStorage.setItem(
			'flutter.botvinnik-bot-v1',
			JSON.stringify(JSON.stringify({ personaId: id, enabled: true, color: 'w' }))
		);
	}, personaId);
}
