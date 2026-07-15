<script module lang="ts">
	// your W–L–D against one persona, computed from the game archive
	export interface PersonaRecord {
		w: number;
		l: number;
		d: number;
	}
</script>

<script lang="ts">
	// Full-roster opponent browser: a vertical list grouped by engine family,
	// replacing the 33-chip horizontal strip. Names, ratings and your record
	// against each bot are visible while browsing, not only after selecting.
	import { availablePersonas, type BotFamily, type BotPersona } from '$lib/bots';
	import type { PlayerEloEstimate } from '$lib/playerElo';
	import BotAvatar from './BotAvatar.svelte';

	interface Props {
		open: boolean;
		personaId: string | null;
		records?: Record<string, PersonaRecord>;
		playerElo?: PlayerEloEstimate | null;
		onpick: (id: string | null) => void;
		onclose: () => void;
	}

	let { open, personaId, records = {}, playerElo = null, onpick, onclose }: Props = $props();

	const ROSTER = availablePersonas(
		typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window
	);

	// family order runs roughly weakest to strongest member
	const FAMILY_META: { fam: BotFamily; label: string; desc: string }[] = [
		{ fam: 'horizon', label: 'Horizon', desc: 'Tiny JavaScript engines that can’t see past their own exchanges.' },
		{ fam: 'square', label: 'Squares', desc: 'Stockfish shaped to miss tactics like a club player does.' },
		{ fam: 'retro', label: 'Retro', desc: 'The first chess programs, 1948–1978, running as written.' },
		{ fam: 'dala', label: 'Dala', desc: 'Nets trained only on games by humans of one rating bracket.' },
		{ fam: 'maia', label: 'Maia', desc: 'Neural nets trained to move like real human players.' },
		{ fam: 'garbo', label: 'Garbo', desc: 'A sharp hand-written JavaScript engine from 2011.' },
		{ fam: 'fish', label: 'Fish', desc: 'Stockfish with the strength limiter on — no act, just chess.' }
	];

	const groups = $derived(
		FAMILY_META.map((m) => ({
			...m,
			bots: ROSTER.filter((p) => p.family === m.fam)
		})).filter((g) => g.bots.length > 0)
	);

	function recordFor(p: BotPersona): string {
		const r = records[p.id];
		if (!r || r.w + r.l + r.d === 0) return '';
		return `${r.w}–${r.l}${r.d ? `–${r.d}` : ''}`;
	}

	// a bot is "your level" when it sits within ±75 of the fitted rating
	function nearYou(p: BotPersona): boolean {
		return playerElo !== null && Math.abs(p.elo - playerElo.elo) <= 75;
	}

	function pick(id: string | null) {
		onpick(id);
		onclose();
	}

	function onkeydown(e: KeyboardEvent) {
		if (e.key === 'Escape' && open) onclose();
	}
</script>

<svelte:window {onkeydown} />

{#if open}
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions — backdrop dismiss; Esc handled on window -->
	<div class="backdrop" onclick={(e) => e.target === e.currentTarget && onclose()}>
		<div class="picker" role="dialog" aria-label="Choose your opponent">
			<div class="picker-head">
				<span class="picker-title">Choose your opponent</span>
				{#if playerElo !== null}
					<span class="you">you ≈ <b>{playerElo.elo}</b></span>
				{/if}
				<button class="close" onclick={onclose}>Close</button>
			</div>
			{#each groups as g (g.fam)}
				<div class="fam">
					<div class="fam-label">{g.label}</div>
					<div class="fam-desc">{g.desc}</div>
					{#each g.bots as p (p.id)}
						<button class="row" class:sel={personaId === p.id} onclick={() => pick(p.id)}>
							<BotAvatar persona={p} size={28} />
							<span class="nm">{p.name}</span>
							<span class="elo">{p.elo}</span>
							{#if nearYou(p)}
								<span class="near" title="Within 75 points of your fitted rating">≈ you</span>
							{/if}
							<span class="wl">{recordFor(p) || ''}</span>
						</button>
					{/each}
				</div>
			{/each}
			<div class="fam">
				<div class="fam-label">Custom</div>
				<div class="fam-desc">The raw strength slider — pick any number, no persona.</div>
				<button class="row" class:sel={personaId === null} onclick={() => pick(null)}>
					<span class="gear-mark">⚙</span>
					<span class="nm">Custom slider</span>
				</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		z-index: 90;
		background: rgba(0, 0, 0, 0.35);
		display: flex;
		align-items: center;
		justify-content: center;
		font-family: system-ui, sans-serif;
	}
	.picker {
		background: var(--bg-panel);
		border: 1px solid var(--border);
		border-radius: 12px;
		box-shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
		width: min(540px, calc(100vw - 24px));
		max-height: min(86vh, 86dvh);
		overflow-y: auto;
		padding: 14px 16px;
	}
	.picker-head {
		display: flex;
		align-items: center;
		gap: 10px;
		margin-bottom: 10px;
		position: sticky;
		top: -14px;
		background: var(--bg-panel);
		padding: 6px 0;
		z-index: 1;
	}
	.picker-title {
		font-weight: 600;
		font-size: 14px;
		color: var(--text-primary);
	}
	.you {
		font-size: 12px;
		color: var(--text-secondary);
	}
	.you b {
		color: var(--text-primary);
	}
	.close {
		margin-left: auto;
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 2px 10px;
		font-size: 12px;
		cursor: pointer;
	}
	.fam {
		margin-bottom: 12px;
	}
	.fam-label {
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-secondary);
	}
	.fam-desc {
		font-size: 12px;
		color: var(--text-secondary);
		font-style: italic;
		margin: 1px 0 4px;
	}
	.row {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		text-align: left;
		background: none;
		border: 1px solid transparent;
		border-radius: 8px;
		padding: 5px 8px;
		font-size: 13px;
		color: var(--text-primary);
		cursor: pointer;
	}
	.row:hover {
		background: var(--bg-button);
	}
	.row.sel {
		border-color: var(--color-win);
		background: var(--bg-button);
	}
	.nm {
		font-weight: 600;
	}
	.elo {
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.near {
		font-size: 10px;
		font-weight: 700;
		color: var(--color-win);
		border: 1px solid var(--color-win);
		border-radius: 999px;
		padding: 0 6px;
	}
	.wl {
		margin-left: auto;
		font-size: 12px;
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.gear-mark {
		width: 28px;
		height: 28px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: var(--bg-button);
		border-radius: 6px;
		color: var(--text-secondary);
	}
</style>
