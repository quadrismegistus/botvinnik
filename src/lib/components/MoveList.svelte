<script lang="ts">
	import type { Move } from 'chess.js';

	interface Props {
		moves: Move[];
		onundo?: () => void;
		onredo?: () => void; // present only while undone moves wait on the redo stack
		onresign?: () => void;
		onreset?: () => void;
		startOpen?: boolean;
	}

	let { moves, onundo, onredo, onresign, onreset, startOpen = true }: Props = $props();
	// svelte-ignore state_referenced_locally — startOpen is deliberately initial-only
	let open = $state(startOpen);

	interface MoveRow {
		number: number;
		white: string;
		black: string | null;
	}

	let rows: MoveRow[] = $derived.by(() => {
		const result: MoveRow[] = [];
		for (let i = 0; i < moves.length; i += 2) {
			result.push({
				number: Math.floor(i / 2) + 1,
				white: moves[i].san,
				black: i + 1 < moves.length ? moves[i + 1].san : null
			});
		}
		return result;
	});

	let scrollEl: HTMLDivElement | undefined = $state();
	$effect(() => {
		if (moves.length && scrollEl) {
			scrollEl.scrollTop = scrollEl.scrollHeight;
		}
	});
</script>

<div class="move-list">
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">Moves</span>
		</button>
		<div class="buttons">
			<button onclick={onundo} disabled={moves.length === 0}>Undo</button>
			{#if onredo}
				<button onclick={onredo}>Redo</button>
			{/if}
			{#if onresign}
				<button onclick={onresign}>Resign</button>
			{/if}
			<button onclick={onreset}>New</button>
		</div>
	</div>
	{#if open}
		<div class="moves" bind:this={scrollEl}>
			{#if rows.length === 0}
				<div class="empty">Play a move to start</div>
			{:else}
				{#each rows as row}
					<div class="row">
						<span class="num">{row.number}.</span>
						<span class="move">{row.white}</span>
						<span class="move">{row.black ?? ''}</span>
					</div>
				{/each}
			{/if}
		</div>
	{/if}
</div>

<style>
	.move-list {
		width: 100%;
		background: var(--bg-panel);
		border-radius: 6px;
		padding: 12px;
		font-family: system-ui, sans-serif;
	}
	.header {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}
	.title-btn {
		display: flex;
		align-items: center;
		gap: 6px;
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
	}
	.chevron {
		font-size: 11px;
		color: var(--text-secondary);
	}
	.title {
		font-weight: 600;
		font-size: 14px;
		color: var(--text-primary);
	}
	.moves {
		margin-top: 8px;
	}
	.buttons {
		display: flex;
		gap: 6px;
	}
	.buttons button {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 3px 10px;
		font-size: 12px;
		cursor: pointer;
	}
	.buttons button:hover { background: var(--bg-highlight); }
	.buttons button:disabled { opacity: 0.4; cursor: default; }
	.moves {
		max-height: 200px;
		overflow-y: auto;
	}
	.empty {
		font-size: 13px;
		color: var(--text-secondary);
		padding: 8px 0;
	}
	.row {
		display: grid;
		grid-template-columns: 30px 1fr 1fr;
		padding: 2px 6px;
		font-size: 13px;
		border-radius: 3px;
	}
	.row:nth-child(odd) { background: var(--bg-highlight); }
	.num {
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.move {
		font-weight: 500;
		color: var(--text-primary);
	}
</style>
