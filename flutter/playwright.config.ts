import { fileURLToPath } from 'node:url';

import { defineConfig } from '@playwright/test';

// the package is ESM, so there is no __dirname; the webServer must run from
// flutter/ rather than the repo root where playwright was invoked
const here = fileURLToPath(new URL('.', import.meta.url));

// E2e for the FLUTTER web app, run against the built bundle — the artifact
// that deploys, service worker and all. Separate from the root config, which
// targets the (frozen) Svelte app: different build, different port, and these
// must not start sharing a browser context with it.
//
//   npx playwright test -c flutter/playwright.config.ts
//
// build-web.sh rather than `flutter build web`: a raw build ships sw.js with
// its manifest placeholder unreplaced, so the tests would be checking an
// artifact nobody deploys.
export default defineConfig({
	testDir: 'e2e',
	timeout: 180_000,
	expect: { timeout: 30_000 },
	fullyParallel: false,
	workers: 1,
	retries: process.env.CI ? 1 : 0,
	reporter: process.env.CI ? 'list' : [['list'], ['html', { open: 'never' }]],
	use: {
		baseURL: 'http://localhost:4400',
		...(process.env.CI ? {} : { channel: 'chrome' as const }),
		trace: 'retain-on-failure'
	},
	webServer: {
		command: './build-web.sh >/dev/null && cd build/web && python3 -m http.server 4400',
		url: 'http://localhost:4400',
		cwd: here,
		reuseExistingServer: !process.env.CI,
		timeout: 300_000
	}
});
