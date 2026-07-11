<script lang="ts">
	import { Chessground } from 'chessground';
	import type { Config } from 'chessground/config';
	import type { Key } from 'chessground/types';
	import { winChance, type MoveGrade } from '$lib/engine/insights';
	import LineHover from './LineHover.svelte';

	interface Props {
		white: MoveGrade | null;
		black: MoveGrade | null;
		collectedPlies?: Set<number>;
		startOpen?: boolean;
	}

	let { white, black, collectedPlies = new Set(), startOpen = true }: Props = $props();
	// svelte-ignore state_referenced_locally — startOpen is deliberately initial-only
	let open = $state(startOpen);

	function fmtEval(pawns: number | null, mate: number | null): string {
		if (mate !== null) return `M${mate}`;
		if (pawns === null) return '?';
		return (pawns >= 0 ? '+' : '') + pawns.toFixed(2);
	}

	// continuous red (0) -> yellow (50) -> green (100) by %Best; translucent so
	// it works over both themes
	function cardStyle(g: MoveGrade): string {
		const pct = Math.max(0, Math.min(100, g.pctBest ?? 0));
		const hue = Math.round(1.2 * pct);
		return `background: hsla(${hue}, 70%, 50%, 0.13); border: 1px solid hsl(${hue}, 55%, 45%);`;
	}

	function boardConfig(g: MoveGrade): Config {
		const shapes = [
			{ orig: g.bestUci.slice(0, 2) as Key, dest: g.bestUci.slice(2, 4) as Key, brush: 'green' }
		];
		if (!g.isBest) {
			shapes.push({ orig: g.uci.slice(0, 2) as Key, dest: g.uci.slice(2, 4) as Key, brush: 'red' });
		}
		return {
			fen: g.fenBefore,
			orientation: g.color === 'w' ? 'white' : 'black',
			viewOnly: true,
			coordinates: false,
			animation: { enabled: false },
			drawable: { visible: true, autoShapes: shapes }
		};
	}

	function miniBoard(el: HTMLElement, grade: MoveGrade) {
		let api = Chessground(el, boardConfig(grade));
		return {
			update(g: MoveGrade) {
				api.set(boardConfig(g));
			},
			destroy() {
				api.destroy();
			}
		};
	}
</script>

{#snippet card(g: MoveGrade, label: string)}
	{@const wcBest = winChance(g.bestEval, g.bestMate)}
	{@const wcPlayed = winChance(g.evalPawns, g.mate)}
	{@const wcDrop = wcBest - wcPlayed}
	{@const hasEval = g.evalPawns !== null || g.mate !== null}
	<div class="card" style={cardStyle(g)}>
		<div class="mini" use:miniBoard={g}></div>
		<div class="text">
			<div class="who">
				{label}
				{#if g.label}
					<span class="chip {g.label}">{g.label}</span>
				{/if}
			</div>
			{#if g.isBest}
				<p>
					You played
					<LineHover fen={g.fenBefore} ucis={g.bestPv}><strong>{g.san}</strong></LineHover>
					— the best move ({fmtEval(g.evalPawns, g.mate)}, d{g.depth}).
				</p>
			{:else if g.pctBest !== null}
				<p>
					You played <strong>{g.san}</strong> ({fmtEval(g.evalPawns, g.mate)}),
					<u>{g.pctBest.toFixed(0)}%</u> as good as the best move,
					<LineHover fen={g.fenBefore} ucis={g.bestPv}><strong>{g.bestSan}</strong></LineHover>
					({fmtEval(g.bestEval, g.bestMate)}, d{g.depth}).
					{#if g.offList}Not in the engine's top {g.totalLines}.{/if}
				</p>
			{:else}
				<p>
					You played <strong>{g.san}</strong> — outside the engine's top
					{g.totalLines} moves, evaluating… Best was
					<LineHover fen={g.fenBefore} ucis={g.bestPv}><strong>{g.bestSan}</strong></LineHover>
					({fmtEval(g.bestEval, g.bestMate)}, d{g.depth}).
				</p>
			{/if}
			{#if g.explanation?.playedPoint}
				<p class="why">
					{#if g.explanation.evidence}
						<LineHover fen={g.explanation.evidence.fen} ucis={g.explanation.evidence.ucis}>
							{g.explanation.playedPoint}
						</LineHover>
					{:else}
						{g.explanation.playedPoint}
					{/if}
				</p>
			{/if}
			{#if g.explanation?.playedIssue}
				<p class="why">
					{#if g.explanation.evidence}
						<LineHover fen={g.explanation.evidence.fen} ucis={g.explanation.evidence.ucis}>
							{g.explanation.playedIssue}
						</LineHover>
					{:else}
						{g.explanation.playedIssue}
					{/if}
				</p>
			{/if}
			{#if g.explanation?.bestPoint}
				<p class="why">
					<LineHover fen={g.fenBefore} ucis={g.bestPv}>{g.explanation.bestPoint}</LineHover>
				</p>
			{/if}
			{#if g.explanation?.lineStory}
				<p class="why">
					{#if g.explanation.evidence}
						<LineHover fen={g.explanation.evidence.fen} ucis={g.explanation.evidence.ucis}>
							{g.explanation.lineStory}
						</LineHover>
					{:else}
						{g.explanation.lineStory}
					{/if}
				</p>
			{/if}
			{#if hasEval}
				<div class="wc">
					{#if g.isBest}
						Win chance {wcPlayed.toFixed(0)}%
					{:else}
						Win chance {wcBest.toFixed(0)}% → {wcPlayed.toFixed(0)}%
						<span class:bad={wcDrop >= 10}>
							({wcDrop >= 0 ? '−' : '+'}{Math.abs(wcDrop).toFixed(0)}%)
						</span>
					{/if}
				</div>
			{/if}
			{#if collectedPlies.has(g.ply)}
				<div class="collected">📌 Saved to practice</div>
			{/if}
		</div>
	</div>
{/snippet}

<div class="insights-panel">
	<button class="header" onclick={() => (open = !open)}>
		<span class="chevron">{open ? '▾' : '▸'}</span>
		<span class="title">Insights</span>
	</button>

	{#if open}
		{#if !white && !black}
			<div class="empty">Play a move to see how it compares to the engine's best.</div>
		{:else}
			{#if white}{@render card(white, 'White')}{/if}
			{#if black}{@render card(black, 'Black')}{/if}
		{/if}
	{/if}
</div>

<style>
	.insights-panel {
		width: 100%;
		background: var(--bg-panel);
		border-radius: 6px;
		padding: 12px;
		font-family: system-ui, sans-serif;
	}
	.header {
		display: flex;
		align-items: center;
		gap: 6px;
		width: 100%;
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
		color: var(--text-primary);
	}
	.chevron {
		font-size: 11px;
		color: var(--text-secondary);
	}
	.title {
		font-weight: 600;
		font-size: 14px;
	}
	.empty {
		font-size: 13px;
		color: var(--text-secondary);
		padding: 8px 0 0;
	}
	.card {
		display: flex;
		gap: 10px;
		border-radius: 6px;
		padding: 8px;
		margin-top: 10px;
	}
	.mini {
		width: 112px;
		height: 112px;
		flex-shrink: 0;
	}
	.text {
		flex: 1;
		min-width: 0;
	}
	.who {
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.5px;
		color: var(--text-secondary);
		margin-bottom: 2px;
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.chip {
		padding: 1px 7px;
		border-radius: 9px;
		font-size: 10px;
		letter-spacing: 0.3px;
		color: #fff;
	}
	.chip.brilliant { background: #1baca6; }
	.chip.great { background: #5b8bb0; }
	.chip.best { background: #81b64c; }
	.chip.excellent { background: #81b64c; opacity: 0.75; }
	.chip.good { background: #95b776; opacity: 0.7; }
	.chip.inaccuracy { background: #f0c15c; color: #333; }
	.chip.mistake { background: #e6912c; }
	.chip.blunder { background: #ca3431; }
	p {
		margin: 0;
		font-size: 12px;
		line-height: 1.45;
		color: var(--text-primary);
	}
	p.why {
		margin-top: 4px;
		font-weight: 500;
	}
	.collected {
		margin-top: 4px;
		font-size: 11px;
		font-weight: 600;
		color: var(--text-secondary);
	}
	.wc {
		margin-top: 4px;
		font-size: 11px;
		font-weight: 600;
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.wc .bad {
		color: var(--color-lose);
	}
</style>
