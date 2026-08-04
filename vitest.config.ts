import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// The brain's unit tests. `flutter/e2e/*.spec.ts` belongs to @playwright/test,
// and the Flutter app's own Dart tests live under `flutter/test/`.
//
// The $lib alias and the svelte/src include went with the Svelte app
// (2026-07-20). $brain stays: brain's own modules import each other relatively,
// but the offline harness in scripts/ uses the alias.
export default defineConfig({
	resolve: {
		alias: { $brain: fileURLToPath(new URL('./brain', import.meta.url)) }
	},
	// pipeline/lichess: the peer-aggregate pipeline (#268) — plain .mjs modules,
	// its own vitest suite so `npx vitest run pipeline/lichess/pipeline.test.ts`
	// actually finds it.
	test: {
		include: ['brain/**/*.test.ts', 'flutter/tool/**/*.test.mjs', 'pipeline/lichess/**/*.test.ts']
	}
});
