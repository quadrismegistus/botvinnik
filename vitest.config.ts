import { defineConfig } from 'vitest/config';

// unit tests only — e2e/*.spec.ts belongs to @playwright/test
export default defineConfig({
	test: { include: ['src/**/*.test.ts'] }
});
