import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// BASE_PATH is unset in production (botvinnik.app apex); kept for any future
// subpath deploy
const basePath = process.env.BASE_PATH;

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: (await import('@sveltejs/adapter-static')).default(),
			// the shared brain lives outside the app: both this app and the
			// Flutter build consume it, so neither owns it
			alias: { $brain: 'brain' },
			// the app lives in svelte/; static/ stays at the root because the
			// Flutter web build serves the same engine out of it
			files: {
				assets: 'static',
				lib: 'svelte/src/lib',
				routes: 'svelte/src/routes',
				appTemplate: 'svelte/src/app.html',
				serviceWorker: 'svelte/src/service-worker.ts'
			},
			paths: { base: basePath?.startsWith('/') ? (basePath as `/${string}`) : '' }
		})
	]
});
