<script lang="ts">
	import type { CcImportProgress } from '$lib/chesscomImport';
	import type { StoredGame, StoredMove } from '$lib/gameStore';
	import LineHover from './LineHover.svelte';

	interface Props {
		games: StoredGame[];
		reviewing: StoredGame | null;
		reviewPly: number; // 0 = initial position, k = after move k
		importing?: boolean;
		importStatus?: string;
		ccImport?: CcImportProgress | null;
		onreview: (game: StoredGame) => void;
		onclose: () => void;
		ongoto: (ply: number) => void;
		ondelete: (id: string) => void;
		onimport?: (username: string) => void;
		onccimport?: (username: string, maxGames?: number) => void;
		onccancel?: () => void;
	}

	let {
		games, reviewing, reviewPly, importing = false, importStatus = '', ccImport = null,
		onreview, onclose, ongoto, ondelete, onimport, onccimport, onccancel
	}: Props = $props();

	let importName = $state('');
	let ccName = $state('');
	let ccMax = $state('');
	const ccRunning = $derived(
		ccImport !== null && (ccImport.phase === 'fetching' || ccImport.phase === 'analyzing')
	);
	const ccPct = $derived(
		ccImport && ccImport.gamesPlanned > 0
			? Math.min(100, (ccImport.gamesDone / ccImport.gamesPlanned) * 100)
			: 0
	);

	const LABEL_ORDER = [
		'brilliant', 'great', 'best', 'excellent', 'good', 'inaccuracy', 'mistake', 'blunder'
	] as const;

	function fmtAcc(a: number | null): string {
		return a === null ? '—' : a.toFixed(1) + '%';
	}

	function fmtEval(m: StoredMove): string {
		if (m.mate !== null) return `M${m.mate}`;
		if (m.evalPawns === null) return '—';
		return (m.evalPawns >= 0 ? '+' : '') + m.evalPawns.toFixed(2);
	}

	function opponent(g: StoredGame): string {
		if (g.white || g.black) return `${g.white ?? '?'} vs ${g.black ?? '?'}`;
		if (g.botElo === null) return 'solo analysis';
		return `vs bot (${g.botElo}) as ${g.botColor === 'w' ? 'Black' : 'White'}`;
	}

	function mistakes(g: StoredGame, color: 'w' | 'b'): string {
		const c = g.labelCounts[color];
		const parts: string[] = [];
		if (c.mistake) parts.push(`${c.mistake}M`);
		if (c.blunder) parts.push(`${c.blunder}B`);
		return parts.length ? parts.join(' ') : '·';
	}

	const selected: StoredMove | null = $derived(
		reviewing && reviewPly > 0 ? reviewing.moves[reviewPly - 1] : null
	);
</script>

<div class="games-panel">
	{#if !reviewing}
		{#if onimport}
			<form
				class="import-row"
				onsubmit={(e) => {
					e.preventDefault();
					if (importName.trim() && !importing) onimport(importName.trim());
				}}
			>
				<input
					type="text"
					placeholder="lichess username"
					bind:value={importName}
					disabled={importing}
				/>
				<button type="submit" disabled={importing || !importName.trim()}>
					{importing ? 'Importing…' : 'Import analysed games'}
				</button>
				{#if importStatus}<span class="import-status">{importStatus}</span>{/if}
			</form>
		{/if}
		{#if onccimport}
			<form
				class="import-row"
				onsubmit={(e) => {
					e.preventDefault();
					if (ccName.trim() && !ccRunning)
						onccimport(ccName.trim(), Number(ccMax) > 0 ? Number(ccMax) : undefined);
				}}
			>
				<input type="text" placeholder="chess.com username" bind:value={ccName} disabled={ccRunning} />
				<input class="max" type="text" placeholder="max" title="Max games (blank = all)" bind:value={ccMax} disabled={ccRunning} />
				{#if ccRunning}
					<button type="button" onclick={() => onccancel?.()}>Cancel</button>
				{:else}
					<button type="submit" disabled={!ccName.trim()}>Analyze + import</button>
				{/if}
			</form>
			{#if ccImport}
				<div class="cc-progress" title="Runs in the background on its own engine{ccImport.engines === 1 ? '' : 's'} — keep playing">
					<div class="bar"><div class="fill" style:width="{ccPct}%"></div></div>
					<span class="cc-status">
						{#if ccImport.phase === 'fetching'}
							Fetching archives…
						{:else if ccImport.phase === 'analyzing'}
							{ccImport.currentMonth} · {ccImport.gamesDone}/{ccImport.gamesPlanned} games
							· +{ccImport.gamesAdded} imported, +{ccImport.practiceAdded} puzzles
							· {ccImport.gamesPerMin.toFixed(1)}/min on {ccImport.engines} engine{ccImport.engines === 1 ? '' : 's'}
						{:else if ccImport.phase === 'done'}
							Done: {ccImport.gamesAdded} games, {ccImport.practiceAdded} practice positions.
						{:else if ccImport.phase === 'cancelled'}
							Cancelled at {ccImport.gamesAdded} games, {ccImport.practiceAdded} practice positions.
						{:else}
							{ccImport.error}
						{/if}
					</span>
				</div>
			{/if}
		{/if}
		{#if games.length === 0}
			<div class="empty">
				No games saved yet — finished games (and abandoned ones of 10+ moves) are stored here
				automatically.
			</div>
		{:else}
			<div class="list">
				{#each games as g (g.id)}
					<div class="row">
						<span class="when">{new Date(g.endedAt).toLocaleString()}</span>
						<span class="opp">{opponent(g)}</span>
						<span class="result">{g.result}</span>
						<span class="len">{Math.ceil(g.moveCount / 2)} moves</span>
						<span class="acc" title="accuracy White / Black">
							{fmtAcc(g.whiteAccuracy)} / {fmtAcc(g.blackAccuracy)}
						</span>
						<span class="errs" title="mistakes (M) and blunders (B), White / Black">
							{mistakes(g, 'w')} / {mistakes(g, 'b')}
						</span>
						<button class="primary" onclick={() => onreview(g)}>Review</button>
						<button class="remove" title="Delete" onclick={() => ondelete(g.id)}>×</button>
					</div>
				{/each}
			</div>
		{/if}
	{:else}
		<div class="toolbar">
			<span class="summary">
				{opponent(reviewing)} · <strong>{reviewing.result}</strong>
				· accuracy {fmtAcc(reviewing.whiteAccuracy)} / {fmtAcc(reviewing.blackAccuracy)}
			</span>
			<span class="chips">
				{#each ['w', 'b'] as const as color (color)}
					<span class="side">{color === 'w' ? 'W' : 'B'}:</span>
					{#each LABEL_ORDER as label (label)}
						{#if reviewing.labelCounts[color][label]}
							<span class="chip {label}">{reviewing.labelCounts[color][label]} {label}</span>
						{/if}
					{/each}
				{/each}
			</span>
			<span class="nav">
				<button onclick={() => ongoto(reviewPly - 1)} disabled={reviewPly === 0}>‹</button>
				<button onclick={() => ongoto(reviewPly + 1)} disabled={reviewPly >= reviewing.moves.length}>›</button>
				<button onclick={onclose}>Exit review</button>
			</span>
		</div>

		<div class="moves">
			<button class="mv" class:sel={reviewPly === 0} onclick={() => ongoto(0)}>start</button>
			{#each reviewing.moves as m (m.ply)}
				<button
					class="mv {m.label ?? ''}"
					class:sel={reviewPly === m.ply}
					onclick={() => ongoto(m.ply)}
				>
					{m.color === 'w' ? `${(m.ply + 1) / 2}. ` : ''}{m.san}
				</button>
			{/each}
		</div>

		{#if selected}
			<div class="detail">
				<strong>{selected.san}</strong>
				{#if selected.label}<span class="chip {selected.label}">{selected.label}</span>{/if}
				<span class="stat">{fmtEval(selected)}</span>
				{#if selected.pctBest !== null}<span class="stat">{selected.pctBest.toFixed(0)}% of best</span>{/if}
				{#if selected.wcDrop >= 1}<span class="stat drop">−{selected.wcDrop.toFixed(0)}% win chance</span>{/if}
				{#if selected.bestSan && selected.label && !['brilliant', 'great', 'best'].includes(selected.label)}
					<span class="stat">best was <strong>{selected.bestSan}</strong></span>
				{/if}
				{#snippet withEvidence(text: string)}
					{#if selected?.explanation?.evidence}
						<LineHover fen={selected.explanation.evidence.fen} ucis={selected.explanation.evidence.ucis}>
							{text}
						</LineHover>
					{:else}
						{text}
					{/if}
				{/snippet}
				{#if selected.explanation?.playedPoint}
					<div class="why">{@render withEvidence(selected.explanation.playedPoint)}</div>
				{/if}
				{#if selected.explanation?.playedIssue}
					<div class="why">{@render withEvidence(selected.explanation.playedIssue)}</div>
				{/if}
				{#if selected.explanation?.bestPoint}<div class="why">{selected.explanation.bestPoint}</div>{/if}
				{#if selected.explanation?.lineStory}
					<div class="why">{@render withEvidence(selected.explanation.lineStory)}</div>
				{/if}
			</div>
		{/if}
	{/if}
</div>

<style>
	.games-panel {
		font-family: system-ui, sans-serif;
	}
	.empty {
		font-size: 13px;
		color: var(--text-secondary);
	}
	.import-row {
		display: flex;
		align-items: center;
		gap: 8px;
		flex-wrap: wrap;
		margin-bottom: 8px;
	}
	.import-row input {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 3px 8px;
		width: 160px;
	}
	.import-status {
		font-size: 11px;
		color: var(--text-secondary);
	}
	.import-row input.max {
		width: 52px;
	}
	.cc-progress {
		display: flex;
		align-items: center;
		gap: 10px;
		margin-bottom: 8px;
	}
	.bar {
		flex: 0 0 140px;
		height: 8px;
		border-radius: 4px;
		background: var(--bg-highlight);
		border: 1px solid var(--border);
		overflow: hidden;
	}
	.fill {
		height: 100%;
		background: var(--color-win);
		transition: width 0.4s;
	}
	.cc-status {
		font-size: 11px;
		color: var(--text-secondary);
	}
	.list {
		max-height: 260px;
		overflow-y: auto;
	}
	.row {
		display: flex;
		align-items: baseline;
		gap: 12px;
		padding: 4px 6px;
		font-size: 12px;
		border-radius: 3px;
		color: var(--text-primary);
	}
	.row:nth-child(odd) {
		background: var(--bg-highlight);
	}
	.when {
		min-width: 150px;
		color: var(--text-secondary);
	}
	.opp {
		flex: 1;
	}
	.result {
		font-weight: 600;
	}
	.len,
	.acc,
	.errs {
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	button {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 2px 10px;
		font-size: 12px;
		cursor: pointer;
	}
	button:hover {
		background: var(--bg-highlight);
	}
	button:disabled {
		opacity: 0.4;
		cursor: default;
	}
	button.primary {
		border-color: var(--color-win);
	}
	.remove {
		padding: 0 6px;
	}
	.toolbar {
		display: flex;
		align-items: center;
		gap: 12px;
		flex-wrap: wrap;
		font-size: 12px;
		color: var(--text-primary);
	}
	.chips {
		display: flex;
		align-items: center;
		gap: 4px;
		flex-wrap: wrap;
	}
	.side {
		color: var(--text-secondary);
		font-weight: 700;
		margin-left: 6px;
	}
	.nav {
		margin-left: auto;
		display: flex;
		gap: 4px;
	}
	.moves {
		margin-top: 8px;
		display: flex;
		flex-wrap: wrap;
		gap: 3px;
		max-height: 110px;
		overflow-y: auto;
	}
	.mv {
		padding: 1px 7px;
		font-size: 12px;
		border-bottom-width: 3px;
	}
	.mv.sel {
		background: var(--bg-highlight);
		outline: 1px solid var(--text-secondary);
	}
	.mv.brilliant { border-bottom-color: #1baca6; }
	.mv.great { border-bottom-color: #5b8bb0; }
	.mv.best { border-bottom-color: #81b64c; }
	.mv.excellent { border-bottom-color: #a3c585; }
	.mv.good { border-bottom-color: #95b776; }
	.mv.inaccuracy { border-bottom-color: #f0c15c; }
	.mv.mistake { border-bottom-color: #e6912c; }
	.mv.blunder { border-bottom-color: #ca3431; }
	.detail {
		margin-top: 8px;
		padding: 8px 10px;
		border: 1px solid var(--border);
		border-radius: 6px;
		font-size: 13px;
		color: var(--text-primary);
		display: flex;
		align-items: baseline;
		gap: 10px;
		flex-wrap: wrap;
	}
	.stat {
		color: var(--text-secondary);
		font-size: 12px;
	}
	.stat.drop {
		color: var(--color-lose);
	}
	.why {
		flex-basis: 100%;
		font-size: 12px;
	}
	.chip {
		padding: 1px 7px;
		border-radius: 9px;
		font-size: 10px;
		color: #fff;
		white-space: nowrap;
	}
	.chip.brilliant { background: #1baca6; }
	.chip.great { background: #5b8bb0; }
	.chip.best { background: #81b64c; }
	.chip.excellent { background: #81b64c; opacity: 0.75; }
	.chip.good { background: #95b776; opacity: 0.7; }
	.chip.inaccuracy { background: #f0c15c; color: #333; }
	.chip.mistake { background: #e6912c; }
	.chip.blunder { background: #ca3431; }
</style>
