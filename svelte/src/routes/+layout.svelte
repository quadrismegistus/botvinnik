<script lang="ts">
	import type { Snippet } from 'svelte';
	import 'chessground/assets/chessground.base.css';
	import 'chessground/assets/chessground.brown.css';
	import 'chessground/assets/chessground.cburnett.css';
	import { browser } from '$app/environment';
	import { nativeTransport } from '$lib/engine/nativeTransport';
	import { setEngineTransport } from '$lib/engine/stockfish';
	import { setBotSubstrate } from '$brain/engine/botRecipe';
	let { children }: { children: Snippet } = $props();

	// inside the Tauri shell, the engine is a native Stockfish sidecar with a
	// higher depth ceiling — the time slice is what actually bounds a search.
	// The bot ELO mapping is engine-specific too (native plays much stronger
	// than the web WASM build), so switch its knot table to match. This runs
	// before the page script, so botEloMax() is correct when the slider mounts.
	if (browser && '__TAURI_INTERNALS__' in window) {
		setEngineTransport(nativeTransport, { depth: 30, movetimeMs: 4000 });
		setBotSubstrate('native');
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
