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
			paths: { base: basePath?.startsWith('/') ? (basePath as `/${string}`) : '' }
		})
	]
});
