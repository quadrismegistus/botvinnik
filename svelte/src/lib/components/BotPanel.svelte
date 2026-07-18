<script lang="ts">
	// The pinned bot card: who you're playing, your record against them, and
	// the way into the roster picker. Replaces the old accordion-with-chip-strip
	// — browsing the roster now lives in RosterPicker.
	import { personaById } from '$brain/bots';
	import type { PlayerEloEstimate } from '$brain/playerElo';
	import BotAvatar from './BotAvatar.svelte';
	import type { PersonaRecord } from './RosterPicker.svelte';

	interface Props {
		enabled: boolean;
		color: 'w' | 'b'; // side the bot plays
		elo: number; // custom-mode slider (app-internal WASM scale)
		minElo?: number; // honest floor for the active engine (wasm sampler bottoms out)
		maxElo?: number; // honest ceiling for the active engine (wasm vs native)
		human?: boolean; // custom mode: human-like (Maia) in the 1100–1900 band
		personaId: string | null; // selected roster bot; null = custom slider
		playerElo?: PlayerEloEstimate | null; // fit from stored persona games
		record?: PersonaRecord | null; // your W–L–D vs the selected persona
		fellBack?: boolean; // this game used the Stockfish stand-in at least once
		downloading?: boolean; // a dala net is being fetched (59-330MB, first use)
		thinking: boolean;
		onchangebot: () => void; // open the roster picker
		onnewgame: () => void; // reset the board (lives here, not in Moves)
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
		record = null,
		fellBack = false,
		downloading = false,
		thinking,
		onchangebot,
		onnewgame
	}: Props = $props();

	const humanApplies = $derived(elo >= 1100 && elo <= 1900);
	const persona = $derived(personaById(personaId));
	const recordText = $derived(
		record && record.w + record.l + record.d > 0
			? `${record.w}–${record.l}${record.d ? `–${record.d}` : ''}`
			: null
	);
</script>

<div class="bot-card">
	<div class="top">
		{#if persona}
			<BotAvatar {persona} size={44} />
		{:else}
			<span class="gear-mark">⚙</span>
		{/if}
		<div class="meta">
			<div class="name">
				{persona ? persona.name : 'Custom'}
				<span class="elo">{persona ? persona.elo : elo}</span>
				{#if fellBack}
					<span
						class="fallback"
						title="The persona's engine failed at least once this game — a Stockfish stand-in moved instead. This game won't count toward your rating.">⚠ stand-in</span
					>
				{/if}
			</div>
			<div class="sub">
				{#if downloading}
					downloading…
				{:else if thinking}
					thinking…
				{:else if recordText}
					your record <b>{recordText}</b>
				{:else if persona}
					unplayed
				{:else}
					strength slider
				{/if}
				{#if playerElo !== null}
					<span class="you" title="± {playerElo.se}, from {playerElo.games} rated games">
						· you ≈ <b>{playerElo.elo}</b></span
					>
				{/if}
			</div>
		</div>
		<div class="actions">
			<button class="change" onclick={onchangebot}>Change</button>
			<button class="newgame" onclick={onnewgame}>New game</button>
		</div>
	</div>

	{#if persona}
		<div class="blurb">{persona.blurb}</div>
	{:else}
		<label class="row">
			<span class="label">Strength</span>
			<!-- min/max are the active engine's honest floor & ceiling
			     (botEloMin/botEloMax): the web WASM sampler bottoms out
			     near 250, native reaches 100 — see botRecipe.ts -->
			<input type="range" min={minElo} max={maxElo} step="50" bind:value={elo} />
			<span class="elo-num">{elo}</span>
		</label>
		<label class="row human" class:muted={!humanApplies}>
			<input type="checkbox" bind:checked={human} />
			Human-like (Maia)
			<span class="hint">{humanApplies ? 'plays like a real ~' + elo : 'only 1100–1900'}</span>
		</label>
	{/if}

	<div class="controls">
		<label class="row enable">
			<input type="checkbox" bind:checked={enabled} />
			Play against the bot
		</label>
		<div class="seg">
			<span class="label">You play</span>
			<button class:active={color === 'b'} onclick={() => (color = 'b')}>White</button>
			<button class:active={color === 'w'} onclick={() => (color = 'w')}>Black</button>
		</div>
	</div>
</div>

<style>
	.bot-card {
		width: 100%;
		background: var(--bg-panel);
		border-radius: 6px;
		padding: 12px;
		box-sizing: border-box;
		font-family: system-ui, sans-serif;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.top {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.meta {
		min-width: 0;
		flex: 1;
	}
	.name {
		font-size: 14px;
		font-weight: 600;
		color: var(--text-primary);
	}
	.name .elo {
		font-weight: 400;
		font-size: 12px;
		color: var(--text-secondary);
		margin-left: 4px;
		font-variant-numeric: tabular-nums;
	}
	.fallback {
		color: var(--color-lose, #d66);
		font-size: 11px;
		font-weight: 400;
		margin-left: 6px;
		cursor: help;
	}
	.sub {
		font-size: 12px;
		color: var(--text-secondary);
		margin-top: 1px;
	}
	.sub b {
		color: var(--text-primary);
	}
	.actions {
		display: flex;
		flex-direction: column;
		gap: 5px;
		flex-shrink: 0;
	}
	.change,
	.newgame {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 3px 12px;
		font-size: 12px;
		cursor: pointer;
	}
	.newgame {
		background: var(--color-win);
		border-color: var(--color-win);
		color: var(--bg-panel);
		font-weight: 600;
	}
	.blurb {
		font-size: 12px;
		line-height: 1.35;
		color: var(--text-secondary);
	}
	.controls {
		display: flex;
		align-items: center;
		gap: 10px;
		flex-wrap: wrap;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 13px;
		color: var(--text-primary);
	}
	.enable {
		cursor: pointer;
	}
	.label {
		color: var(--text-secondary);
		font-size: 12px;
	}
	.seg {
		display: flex;
		align-items: center;
		gap: 4px;
		margin-left: auto;
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
	.gear-mark {
		width: 44px;
		height: 44px;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 20px;
		color: var(--text-secondary);
		background: var(--bg-button);
		border-radius: 10px;
		flex-shrink: 0;
	}
	input[type='range'] {
		flex: 1;
	}
	.elo-num {
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
