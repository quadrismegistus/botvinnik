<script lang="ts">
	import { availablePersonas, personaById } from '$lib/bots';
	import type { PlayerEloEstimate } from '$lib/playerElo';
	import BotAvatar from './BotAvatar.svelte';

	// dala personas need the native lc0 sidecar; the layout flips the shell
	// state before any page mounts, so a plain check is stable here
	const ROSTER = availablePersonas(
		typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
	);

	interface Props {
		enabled: boolean;
		color: 'w' | 'b'; // side the bot plays
		elo: number; // custom-mode slider (app-internal WASM scale)
		minElo?: number; // honest floor for the active engine (wasm sampler bottoms out)
		maxElo?: number; // honest ceiling for the active engine (wasm vs native)
		human?: boolean; // custom mode: human-like (Maia) in the 1100–1900 band
		personaId: string | null; // selected roster bot; null = custom slider
		playerElo?: PlayerEloEstimate | null; // fit from stored persona games
		fellBack?: boolean; // this game used the Stockfish stand-in at least once
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
		personaId = $bindable(),
		playerElo = null,
		fellBack = false,
		thinking,
		startOpen = true
	}: Props = $props();
	const humanApplies = $derived(elo >= 1100 && elo <= 1900);
	const persona = $derived(personaById(personaId));
	// index of the first roster chip stronger than the player ("you are here")
	const youAt = $derived(
		playerElo === null ? -1 : ROSTER.findIndex((p) => p.elo > playerElo.elo)
	);
	// svelte-ignore state_referenced_locally — startOpen is deliberately initial-only
	let open = $state(startOpen);

	// scroll the selected chip into view when the panel opens
	function revealSelected(node: HTMLElement) {
		node.querySelector('.chip.active')?.scrollIntoView({ inline: 'center', block: 'nearest' });
	}
</script>

<div class="bot-panel">
	<div class="header">
		<button class="title-btn" onclick={() => (open = !open)}>
			<span class="chevron">{open ? '▾' : '▸'}</span>
			<span class="title">Bot</span>
		</button>
		{#if enabled}
			<span class="status">
				{#if fellBack}
					<span
						class="fallback"
						title="The persona's engine failed at least once this game — a Stockfish stand-in moved instead. This game won't count toward your rating.">⚠ stand-in</span
					>
				{/if}
				{thinking ? 'thinking…' : persona ? `${persona.name} · ${persona.elo}` : `${elo} ELO`}
			</span>
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

			<!-- the roster: one bot per 100 ELO per engine family, ordered by
			     strength (display scale ≈ lichess rapid). "Custom" restores the
			     raw slider. -->
			<div class="strip" use:revealSelected>
				{#each ROSTER as p, i (p.id)}
					{#if i === youAt}
						<div class="you" title="Estimated from your {playerElo?.games} rated games">
							<span class="you-line"></span>
							<span class="chip-elo">you</span>
						</div>
					{/if}
					<button
						class="chip"
						class:active={personaId === p.id}
						onclick={() => (personaId = p.id)}
						title="{p.name} · {p.elo}"
					>
						<BotAvatar persona={p} size={30} />
						<span class="chip-elo">{p.elo}</span>
					</button>
				{/each}
				<button class="chip custom" class:active={persona === null} onclick={() => (personaId = null)}>
					<span class="custom-mark">⚙</span>
					<span class="chip-elo">custom</span>
				</button>
			</div>

			{#if playerElo !== null}
				<div class="rating">
					You ≈ <b>{playerElo.elo}</b> ± {playerElo.se}
					<span class="rating-n">· {playerElo.games} rated {playerElo.games === 1 ? 'game' : 'games'}</span>
				</div>
			{/if}

			{#if persona}
				<div class="card">
					<BotAvatar {persona} size={40} />
					<div class="card-text">
						<div class="card-name">
							{persona.name}
							<span class="card-elo">{persona.elo}</span>
						</div>
						<div class="card-blurb">{persona.blurb}</div>
					</div>
				</div>
			{:else}
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
			{/if}
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
	.fallback {
		color: var(--color-loss, #d66);
		margin-right: 6px;
		cursor: help;
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
	.strip {
		display: flex;
		gap: 4px;
		overflow-x: auto;
		padding: 2px 0 6px;
		scrollbar-width: thin;
	}
	.chip {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		background: none;
		border: 1px solid transparent;
		border-radius: 6px;
		padding: 3px 4px;
		cursor: pointer;
		flex: none;
	}
	.chip.active {
		border-color: var(--color-win);
		background: var(--bg-button);
	}
	.chip-elo {
		font-size: 10px;
		font-variant-numeric: tabular-nums;
		color: var(--text-secondary);
	}
	.chip.active .chip-elo {
		color: var(--text-primary);
	}
	.you {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		padding: 3px 1px;
		flex: none;
	}
	.you-line {
		width: 2px;
		height: 30px;
		border-radius: 1px;
		background: var(--color-win);
	}
	.you .chip-elo {
		color: var(--color-win);
		font-weight: 600;
	}
	.rating {
		font-size: 12px;
		color: var(--text-primary);
	}
	.rating-n {
		color: var(--text-secondary);
	}
	.custom-mark {
		width: 30px;
		height: 30px;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 15px;
		color: var(--text-secondary);
		background: var(--bg-button);
		border-radius: 5px;
	}
	.card {
		display: flex;
		gap: 10px;
		align-items: flex-start;
		background: var(--bg-button);
		border-radius: 6px;
		padding: 8px 10px;
	}
	.card-text {
		min-width: 0;
	}
	.card-name {
		font-size: 13px;
		font-weight: 600;
		color: var(--text-primary);
	}
	.card-elo {
		font-weight: 400;
		font-size: 12px;
		color: var(--text-secondary);
		margin-left: 4px;
	}
	.card-blurb {
		margin-top: 2px;
		font-size: 12px;
		line-height: 1.35;
		color: var(--text-secondary);
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
