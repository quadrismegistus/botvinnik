<script lang="ts">
	import type { Snippet } from 'svelte';

	interface Props {
		title: string;
		badge?: string;
		open?: boolean;
		anchor?: string; // jump-strip target id on narrow layouts
		action?: Snippet; // optional button(s) in the header, right of the badge
		children: Snippet;
	}

	let {
		title,
		badge = '',
		open = $bindable(true),
		anchor = '',
		action,
		children
	}: Props = $props();
</script>

<div class="side-panel" data-anchor={anchor || undefined}>
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">{title}</span>
		</button>
		<div class="header-right">
			{#if badge}
				<span class="badge">{badge}</span>
			{/if}
			{#if action}
				{@render action()}
			{/if}
		</div>
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
	.header-right {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.badge {
		font-size: 12px;
		color: var(--text-secondary);
	}
	/* header action buttons (e.g. Practice's "Start") — matches the Moves panel */
	.header-right :global(button) {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 2px 10px;
		font-size: 12px;
		cursor: pointer;
	}
	.header-right :global(button:disabled) {
		opacity: 0.5;
		cursor: default;
	}
	.body {
		margin-top: 8px;
	}
</style>
