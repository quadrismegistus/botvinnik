import { defineConfig } from 'vitest/config';

// The suite drives the Worker through Miniflare (workerd + an in-memory R2),
// so no special pool is needed — a plain Node-side vitest run is enough.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    testTimeout: 20000,
    hookTimeout: 30000,
  },
});
