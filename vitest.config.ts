import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// unit tests only — e2e/*.spec.ts belongs to @playwright/test
export default defineConfig({
	resolve: {
		alias: {
			$brain: fileURLToPath(new URL('./brain', import.meta.url)),
			$lib: fileURLToPath(new URL('./svelte/src/lib', import.meta.url))
		}
	},
	test: { include: ['svelte/src/**/*.test.ts', 'brain/**/*.test.ts'] }
});
