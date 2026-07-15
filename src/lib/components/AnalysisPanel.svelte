<script lang="ts">
	import type { EngineMove } from '$lib/engine/stockfish';
	import { getFenAfter, getNumberedSanLine, getSan } from '$lib/engine/chess';
	import LineHover from './LineHover.svelte';

	import type { Snippet } from 'svelte';

	interface Props {
		moves: EngineMove[];
		fen: string;
		analyzing: boolean;
		orientation?: 'white' | 'black'; // main-board orientation, for line previews
		startOpen?: boolean;
		footer?: Snippet; // rendered under the lines (e.g. the expand-tree toggle)
	}

	let { moves, fen, analyzing, orientation = 'white', startOpen = true, footer }: Props = $props();
	// svelte-ignore state_referenced_locally — startOpen is deliberately initial-only
	let open = $state(startOpen);

	function formatScore(m: EngineMove): string {
		if (m.mate !== null) return `M${m.mate}`;
		return m.score >= 0 ? `+${m.score.toFixed(2)}` : m.score.toFixed(2);
	}

	function scoreClass(m: EngineMove): string {
		if (m.mate !== null) return m.mate > 0 ? 'winning' : 'losing';
		if (m.score > 0.5) return 'winning';
		if (m.score < -0.5) return 'losing';
		return 'equal';
	}
</script>

<div class="analysis-panel">
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">Lines</span>
		</button>
		{#if analyzing}
			<span class="status">depth {moves[0]?.depth ?? '…'}…</span>
		{:else if moves.length > 0}
			<span class="status">d{moves[0]?.depth}</span>
		{/if}
	</div>

	{#if open}
		{#if moves.length === 0}
			{#if analyzing}
				<div class="empty">Thinking…</div>
			{/if}
		{:else}
			{#each moves as move, i}
				<div class="line" class:best={i === 0}>
					<span class="rank">{i + 1}.</span>
					<span class="score {scoreClass(move)}">{formatScore(move)}</span>
					<LineHover {fen} ucis={move.pv} {orientation}>
						<span class="san">{getSan(fen, move.pv[0])}</span>
						<span class="pv">
							{getNumberedSanLine(getFenAfter(fen, move.pv[0]) ?? fen, move.pv.slice(1), 11)}
						</span>
					</LineHover>
				</div>
			{/each}
		{/if}
		{#if footer}
			{@render footer()}
		{/if}
	{/if}
</div>

<style>
	.analysis-panel {
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
	.line:first-of-type,
	.empty {
		margin-top: 8px;
	}
	.status {
		font-size: 12px;
		color: var(--text-secondary);
	}
	.empty {
		font-size: 13px;
		color: var(--text-secondary);
		padding: 8px 0;
	}
	.line {
		display: flex;
		align-items: baseline;
		gap: 8px;
		padding: 4px 6px;
		border-radius: 4px;
		font-size: 13px;
	}
	.line.best {
		background: var(--bg-highlight);
	}
	.rank {
		color: var(--text-secondary);
		min-width: 18px;
	}
	.score {
		font-weight: 600;
		min-width: 52px;
		font-variant-numeric: tabular-nums;
	}
	.score.winning { color: var(--color-win); }
	.score.losing { color: var(--color-lose); }
	.score.equal { color: var(--text-secondary); }
	.san {
		font-weight: 600;
		color: var(--text-primary);
	}
	.pv {
		color: var(--text-secondary);
		font-size: 12px;
	}
</style>
