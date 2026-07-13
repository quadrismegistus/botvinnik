<script lang="ts">
	interface Props {
		enabled: boolean;
		color: 'w' | 'b'; // side the bot plays
		elo: number;
		thinking: boolean;
		startOpen?: boolean;
	}

	let {
		enabled = $bindable(),
		color = $bindable(),
		elo = $bindable(),
		thinking,
		startOpen = true
	}: Props = $props();
	// svelte-ignore state_referenced_locally — startOpen is deliberately initial-only
	let open = $state(startOpen);
</script>

<div class="bot-panel">
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">Bot</span>
		</button>
		{#if enabled}
			<span class="status">{thinking ? 'thinking…' : `${elo} ELO`}</span>
		{/if}
	</div>

	{#if open}
		<div class="body">
			<label class="row">
				<input type="checkbox" bind:checked={enabled} />
				Play against the bot
			</label>

			<div class="row">
				<span class="label">You play</span>
				<div class="seg">
					<button class:active={color === 'b'} onclick={() => (color = 'b')}>White</button>
					<button class:active={color === 'w'} onclick={() => (color = 'w')}>Black</button>
				</div>
			</div>

			<label class="row">
				<span class="label">Strength</span>
				<!-- 3000 is the strongest CALIBRATED setting (UCI_Elo 3190 @ 1s) -->
				<input type="range" min="100" max="3000" step="50" bind:value={elo} />
				<span class="elo">{elo}</span>
			</label>
		</div>
	{/if}
</div>

<style>
	.bot-panel {
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
	.status {
		font-size: 12px;
		color: var(--text-secondary);
	}
	.body {
		margin-top: 8px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		color: var(--text-primary);
	}
	.label {
		color: var(--text-secondary);
		font-size: 12px;
		min-width: 52px;
	}
	.seg {
		display: flex;
		gap: 4px;
	}
	.seg button {
		background: var(--bg-button);
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 2px 10px;
		font-size: 12px;
		cursor: pointer;
	}
	.seg button.active {
		color: var(--text-primary);
		border-color: var(--color-win);
	}
	input[type='range'] {
		flex: 1;
	}
	.elo {
		min-width: 36px;
		font-size: 12px;
		font-variant-numeric: tabular-nums;
		color: var(--text-primary);
	}
</style>
