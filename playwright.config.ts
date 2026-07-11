import { defineConfig } from '@playwright/test';

// E2e for the web app, run against the BUILT bundle (vite preview) so tests
// cover what actually deploys. Engine searches make these slow-ish; they run
// serially because every page boots its own Stockfish WASM worker.
export default defineConfig({
	testDir: 'e2e',
	timeout: 150_000,
	expect: { timeout: 20_000 },
	fullyParallel: false,
	workers: 1,
	retries: process.env.CI ? 1 : 0,
	reporter: process.env.CI ? 'list' : [['list'], ['html', { open: 'never' }]],
	use: {
		baseURL: 'http://localhost:4399',
		// locally use the installed Chrome (no browser download); CI installs chromium
		...(process.env.CI ? {} : { channel: 'chrome' as const }),
		trace: 'retain-on-failure'
	},
	webServer: {
		command: 'npm run build && npm run preview -- --port 4399 --strictPort',
		url: 'http://localhost:4399',
		reuseExistingServer: !process.env.CI,
		timeout: 180_000
	}
});
