<script lang="ts">
	import type { Snippet } from 'svelte';
	import 'chessground/assets/chessground.base.css';
	import 'chessground/assets/chessground.brown.css';
	import 'chessground/assets/chessground.cburnett.css';
	import { browser } from '$app/environment';
	import { nativeTransport } from '$lib/engine/nativeTransport';
	import { setEngineTransport } from '$lib/engine/stockfish';
	let { children }: { children: Snippet } = $props();

	// inside the Tauri shell, the engine is a native Stockfish sidecar
	if (browser && '__TAURI_INTERNALS__' in window) {
		setEngineTransport(nativeTransport);
	}
</script>

<svelte:head>
	<title>Botvinnik</title>
</svelte:head>

{@render children()}

<style>
	:global(:root) {
		--bg-page: #1a1a2e;
		--bg-panel: #16213e;
		--bg-highlight: rgba(255, 255, 255, 0.05);
		--bg-button: #0f3460;
		--text-primary: #e0e0e0;
		--text-secondary: #8888aa;
		--border: #2a2a4a;
		--color-win: #4caf50;
		--color-lose: #e53935;
	}

	@media (prefers-color-scheme: light) {
		:global(:root) {
			--bg-page: #f5f5f0;
			--bg-panel: #ffffff;
			--bg-highlight: rgba(0, 0, 0, 0.04);
			--bg-button: #e8e8e8;
			--text-primary: #1a1a1a;
			--text-secondary: #666680;
			--border: #d0d0d0;
			--color-win: #2e7d32;
			--color-lose: #c62828;
		}
	}

	:global(*, *::before, *::after) {
		box-sizing: border-box;
	}

	:global(body) {
		margin: 0;
		background: var(--bg-page);
		color: var(--text-primary);
		font-family: system-ui, -apple-system, sans-serif;
	}
</style>
