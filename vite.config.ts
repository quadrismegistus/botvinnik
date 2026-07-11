import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

// BASE_PATH=/botvinnik for GitHub Pages project-site builds
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
