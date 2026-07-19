<script lang="ts">
	import type { CommentaryEntry } from '$lib/commentary';

	interface Props {
		entries: CommentaryEntry[];
		/** The dataset is fetched on first open, so "empty" and "not here yet"
		 *  are different states and must not read the same. */
		loading?: boolean;
	}

	let { entries, loading = false }: Props = $props();

	function fmtTime(s: number): string {
		const m = Math.floor(s / 60);
		return `${m}:${String(s % 60).padStart(2, '0')}`;
	}

	function link(e: CommentaryEntry): string {
		return `${e.videoUrl}&t=${e.t}s`;
	}
</script>

<div class="commentary-panel">
	{#if loading && entries.length === 0}
		<div class="empty">Loading commentary…</div>
	{:else if entries.length === 0}
		<div class="empty">
			No YouTube commentary for this position — hits are most common in the opening.
		</div>
	{:else}
		<div class="list">
			{#each entries as e, i (i)}
				<div class="row">
					<p class="text">{e.text}</p>
					<a class="watch" href={link(e)} target="_blank" rel="noreferrer" title="Watch this moment">
						▶ {fmtTime(e.t)}
					</a>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.commentary-panel {
		font-family: system-ui, sans-serif;
	}
	.empty {
		font-size: 12px;
		color: var(--text-secondary);
	}
	.list {
		max-height: 260px;
		overflow-y: auto;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.row {
		display: flex;
		align-items: baseline;
		gap: 10px;
		padding: 5px 8px;
		border-radius: 4px;
		background: var(--bg-highlight);
	}
	.text {
		margin: 0;
		flex: 1;
		font-size: 12.5px;
		line-height: 1.45;
		color: var(--text-primary);
	}
	.watch {
		font-size: 11px;
		color: var(--text-secondary);
		text-decoration: none;
		white-space: nowrap;
	}
	.watch:hover {
		color: var(--text-primary);
	}
</style>
