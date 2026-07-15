<script module lang="ts">
	// The app's three modes as first-class navigation: a segmented control
	// instead of Practice/Games hiding inside collapsible panels.
	export type SideView = 'play' | 'practice' | 'review';
</script>

<script lang="ts">
	interface Props {
		view: SideView;
		onchange: (v: SideView) => void;
	}

	let { view, onchange }: Props = $props();

	const SEGMENTS: { id: SideView; label: string }[] = [
		{ id: 'play', label: 'Play' },
		{ id: 'practice', label: 'Practice' },
		{ id: 'review', label: 'Review' }
	];
</script>

<div class="modebar" role="tablist">
	{#each SEGMENTS as s (s.id)}
		<button
			role="tab"
			aria-selected={view === s.id}
			class:on={view === s.id}
			onclick={() => onchange(s.id)}
		>
			{s.label}
		</button>
	{/each}
</div>

<style>
	.modebar {
		display: grid;
		grid-template-columns: 1fr 1fr 1fr;
		gap: 3px;
		background: var(--bg-panel);
		border: 1px solid var(--border);
		border-radius: 8px;
		padding: 3px;
		font-family: system-ui, sans-serif;
	}
	button {
		position: relative;
		border: none;
		border-radius: 6px;
		background: transparent;
		color: var(--text-secondary);
		font-size: 13px;
		font-weight: 600;
		padding: 6px 0;
		cursor: pointer;
	}
	button.on {
		background: var(--text-primary);
		color: var(--bg-panel);
	}
</style>
