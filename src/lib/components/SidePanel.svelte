<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		title: string;
		badge?: string;
		open?: boolean;
		children: Snippet;
	}

	let { title, badge = '', open = $bindable(true), children }: Props = $props();
</script>

<div class="side-panel">
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">{title}</span>
		</button>
		{#if badge}
			<span class="badge">{badge}</span>
		{/if}
	</div>

	{#if open}
		<div class="body">
			{@render children()}
		</div>
	{/if}
</div>

<style>
	.side-panel {
		width: 100%;
		background: var(--bg-panel);
		border-radius: 6px;
		padding: 12px;
		box-sizing: border-box;
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
	.badge {
		font-size: 12px;
		color: var(--text-secondary);
	}
	.body {
		margin-top: 8px;
	}
</style>
