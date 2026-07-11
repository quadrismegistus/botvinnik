import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: (await import('@sveltejs/adapter-static')).default(),
			// BASE_PATH=/botvinnik for GitHub Pages project-site builds
			paths: { base: process.env.BASE_PATH ?? '' }
		})
	]
});
