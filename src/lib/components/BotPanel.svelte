<script lang="ts">
	interface Props {
		enabled: boolean;
		color: 'w' | 'b'; // side the bot plays
		elo: number;
		minElo?: number; // honest floor for the active engine (wasm sampler bottoms out)
		maxElo?: number; // honest ceiling for the active engine (wasm vs native)
		human?: boolean; // human-like (Maia) opponent in the 1100–1900 band
		thinking: boolean;
		startOpen?: boolean;
	}

	let {
		enabled = $bindable(),
		color = $bindable(),
		elo = $bindable(),
		minElo = 100,
		maxElo = 2800,
		human = $bindable(false),
		thinking,
		startOpen = true
	}: Props = $props();
	const humanApplies = $derived(elo >= 1100 && elo <= 1900);
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
				<!-- min/max are the active engine's honest floor & ceiling
				     (botEloMin/botEloMax): the web WASM sampler bottoms out
				     near 250, native reaches 100 — see botRecipe.ts -->
				<input type="range" min={minElo} max={maxElo} step="50" bind:value={elo} />
				<span class="elo">{elo}</span>
			</label>

			<label class="row human" class:muted={!humanApplies}>
				<input type="checkbox" bind:checked={human} />
				Human-like (Maia)
				<span class="hint">{humanApplies ? 'plays like a real ~' + elo : 'only 1100–1900'}</span>
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
	.human {
		cursor: pointer;
	}
	.human.muted {
		opacity: 0.55;
	}
	.human .hint {
		margin-left: auto;
		font-size: 11px;
		color: var(--text-secondary);
	}
</style>
