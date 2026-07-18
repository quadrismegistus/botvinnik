<script lang="ts">
	import type { CcImportProgress } from '$lib/chesscomImport';
	import { winChance } from '$brain/engine/insights';
	import type { StoredGame, StoredMove } from '$brain/gameStore';
	import { personaById } from '$brain/bots';
	import { CLASS, LABEL_ORDER } from '$brain/classifications';
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
		onpractice?: (move: StoredMove) => void;
		onexport?: (game: StoredGame) => void;
		orientation?: 'white' | 'black'; // main-board orientation, for line previews
	}

	let {
		games, reviewing, reviewPly, importing = false, importStatus = '', ccImport = null,
		orientation = 'white',
		onreview, onclose, ongoto, ondelete, onimport, onccimport, onccancel, onpractice, onexport
	}: Props = $props();

	let importName = $state('');
	let ccName = $state('');
	let ccMax = $state('');
	// thousands of imported games would otherwise become thousands of DOM rows
	const PAGE = 100;
	let visibleCount = $state(PAGE);
	const ccRunning = $derived(
		ccImport !== null && (ccImport.phase === 'fetching' || ccImport.phase === 'analyzing')
	);
	const ccPct = $derived(
		ccImport && ccImport.gamesPlanned > 0
			? Math.min(100, (ccImport.gamesDone / ccImport.gamesPlanned) * 100)
			: 0
	);

	function fmtAcc(a: number | null): string {
		return a === null ? '—' : a.toFixed(1) + '%';
	}

	function fmtEval(m: StoredMove): string {
		if (m.mate !== null) return `M${m.mate}`;
		if (m.evalPawns === null) return '—';
		return (m.evalPawns >= 0 ? '+' : '') + m.evalPawns.toFixed(2);
	}

	// user-facing bot label: roster personas by name + DISPLAY elo; slider/
	// legacy games fall back to the stored internal-scale number
	function botLabel(g: StoredGame): string {
		const p = personaById(g.botPersona);
		return p ? `${p.name}` : `bot (${g.botElo})`;
	}

	function opponent(g: StoredGame): string {
		if (g.white || g.black) return `${g.white ?? '?'} vs ${g.black ?? '?'}`;
		if (g.botElo === null) return 'solo analysis';
		const undos = g.botUndos ? ` · ↩${g.botUndos}` : '';
		return `vs ${botLabel(g)} as ${g.botColor === 'w' ? 'Black' : 'White'}${undos}`;
	}

	// the crowns distinction: did the human WIN, and how clean was it?
	// clean = no takebacks, no engine stand-in, hint overlays off (blind) —
	// only games saved after hint-tracking began (botHintsUsed present) can
	// earn the solid crown; older wins show the outline with 'hints unknown'.
	function crown(g: StoredGame): { glyph: string; cls: string; title: string } | null {
		if (g.botElo === null || g.botColor === null || g.white) return null; // not a bot game
		const humanWon =
			(g.result === '1-0' && g.botColor === 'b') || (g.result === '0-1' && g.botColor === 'w');
		if (!humanWon) return null;
		const help: string[] = [];
		if (g.botUndos) help.push(`${g.botUndos} takeback${g.botUndos === 1 ? '' : 's'}`);
		if (g.botFallback) help.push('engine stand-in');
		if (g.botHintsUsed === true) help.push('hint overlays');
		if (g.botHintsUsed === undefined) help.push('hints unknown (pre-tracking)');
		if (help.length === 0)
			return { glyph: '♛', cls: 'clean', title: 'Won clean — blind, no takebacks' };
		return { glyph: '♛', cls: 'helped', title: `Won with help: ${help.join(', ')}` };
	}

	function mistakes(g: StoredGame, color: 'w' | 'b'): string {
		const c = g.labelCounts[color];
		const parts: string[] = [];
		if (c.mistake) parts.push(`${c.mistake}M`);
		if (c.blunder) parts.push(`${c.blunder}B`);
		return parts.length ? parts.join(' ') : '·';
	}

	// spelled-out tooltip for the cryptic "2B / 1M 2B" column, naming the sides
	function mistakesTitle(g: StoredGame): string {
		const side = (color: 'w' | 'b') => {
			const c = g.labelCounts[color];
			const parts: string[] = [];
			if (c.mistake) parts.push(`${c.mistake} mistake${c.mistake > 1 ? 's' : ''}`);
			if (c.blunder) parts.push(`${c.blunder} blunder${c.blunder > 1 ? 's' : ''}`);
			const who = `${sideName(g, color)} (${color === 'w' ? 'White' : 'Black'})`;
			return `${who}: ${parts.length ? parts.join(', ') : 'no mistakes'}`;
		};
		return `${side('w')} · ${side('b')}`;
	}

	function accTitle(g: StoredGame): string {
		return `accuracy — ${sideName(g, 'w')} (White): ${fmtAcc(g.whiteAccuracy)} · ${sideName(g, 'b')} (Black): ${fmtAcc(g.blackAccuracy)}`;
	}

	const selected: StoredMove | null = $derived(
		reviewing && reviewPly > 0 ? reviewing.moves[reviewPly - 1] : null
	);

	const itemable = $derived(
		!!selected?.bestUci &&
			!!selected.label &&
			['inaccuracy', 'mistake', 'blunder'].includes(selected.label)
	);
	// reset the "Added ✓" confirmation whenever the selected move changes
	let addedPly = $state(-1);
	const added = $derived(addedPly === reviewPly);

	// player names for the summary cards
	function sideName(g: StoredGame, color: 'w' | 'b'): string {
		const explicit = color === 'w' ? g.white : g.black;
		if (explicit) return explicit;
		if (g.botElo === null) return color === 'w' ? 'White' : 'Black';
		if (g.botColor !== color) return 'You';
		const p = personaById(g.botPersona);
		return p ? p.name : `Bot ${g.botElo}`;
	}

	// two-column move table rows: [moveNo, whiteMove?, blackMove?]
	const moveRows = $derived.by(() => {
		const g = reviewing;
		if (!g) return [];
		const rows: { no: number; white?: StoredMove; black?: StoredMove }[] = [];
		for (const m of g.moves) {
			const no = Math.ceil(m.ply / 2);
			let row = rows[rows.length - 1];
			if (!row || (m.color === 'w' && row.white)) {
				row = { no };
				rows.push(row);
			}
			if (m.color === 'w') row.white = m;
			else row.black = m;
		}
		return rows;
	});

	// "Best" reveals the engine's preferred move + line for the selected move
	let showBest = $state(false);
	$effect(() => {
		reviewPly; // collapse the best-line reveal on navigation
		showBest = false;
	});
	const selClass = $derived(selected?.label ? CLASS[selected.label] : null);
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
				{#each games.slice(0, visibleCount) as g (g.id)}
					<div class="row">
						<span class="when">{new Date(g.endedAt).toLocaleString()}</span>
						<span class="opp">{opponent(g)}</span>
						{#if crown(g)}
							{@const c = crown(g)!}
							<span class="crown {c.cls}" title={c.title}>{c.glyph}</span>
						{/if}
						<span class="result">{g.result}</span>
						<span class="len">{Math.ceil(g.moveCount / 2)} moves</span>
						<span class="acc" title={accTitle(g)}>
							{fmtAcc(g.whiteAccuracy)} / {fmtAcc(g.blackAccuracy)}
						</span>
						<span class="errs" title={mistakesTitle(g)}>
							{mistakes(g, 'w')} / {mistakes(g, 'b')}
						</span>
						<button class="primary" onclick={() => onreview(g)}>Review</button>
						{#if onexport && g.pgn}
							<button class="export" title="Download PGN" onclick={() => onexport(g)}>⬇</button>
						{/if}
						<button class="remove" title="Delete" onclick={() => ondelete(g.id)}>×</button>
					</div>
				{/each}
				{#if games.length > visibleCount}
					<button class="show-more" onclick={() => (visibleCount += PAGE)}>
						Show more ({games.length - visibleCount} older games)
					</button>
				{/if}
				<div class="legend">
					<span class="crown clean">♛</span> won clean (blind, no takebacks) ·
					<span class="crown helped">♛</span> won with help · ↩n takebacks
				</div>
			</div>
		{/if}
	{:else}
		<div class="rv-head">
			<span class="rv-result">{opponent(reviewing)} · <strong>{reviewing.result}</strong></span>
			<span class="rv-headnav">
				{#if onexport && reviewing.pgn}
					<button title="Download PGN" onclick={() => onexport(reviewing)}>PGN</button>
				{/if}
				<button onclick={onclose}>Exit</button>
			</span>
		</div>

		<!-- accuracy + classification summary, chess.com style -->
		<div class="rv-summary">
			<div class="rv-acc">
				{#each ['w', 'b'] as const as color (color)}
					<div class="rv-player" class:active={selected?.color === color}>
						<span class="rv-name">{sideName(reviewing, color)}</span>
						<span class="rv-accval">{fmtAcc(color === 'w' ? reviewing.whiteAccuracy : reviewing.blackAccuracy)}</span>
						<span class="rv-acclbl">accuracy</span>
					</div>
				{/each}
			</div>
			<div class="rv-counts">
				{#each LABEL_ORDER as label (label)}
					{@const wc = reviewing.labelCounts.w[label]}
					{@const bc = reviewing.labelCounts.b[label]}
					{#if wc || bc}
						<div class="rv-crow">
							<span class="rv-cnum">{wc || ''}</span>
							<span class="rv-cmid">
								<span class="rv-glyph" style:color={CLASS[label].color}>{CLASS[label].glyph}</span>
								<span class="rv-cname">{label}</span>
							</span>
							<span class="rv-cnum">{bc || ''}</span>
						</div>
					{/if}
				{/each}
			</div>
		</div>

		<!-- feedback card for the selected move -->
		{#if selected}
			{@const showBestBtn =
				!!selected.bestSan &&
				!!selected.label &&
				!['brilliant', 'great', 'best'].includes(selected.label)}
			<div class="rv-card" style:border-left-color={selClass?.color ?? 'var(--border)'}>
				<div class="rv-cardhead">
					{#if selClass}
						<span class="rv-cglyph" style:background={selClass.color}>{selClass.glyph}</span>
					{/if}
					<span class="rv-cardtitle">
						<strong>{selected.san}</strong>{#if selClass} is {selClass.noun}{/if}
					</span>
					<span class="rv-cardeval" class:drop={selected.wcDrop >= 5}>{fmtEval(selected)}</span>
				</div>

				{#if selected.evalPawns !== null || selected.mate !== null}
					{@const wcAfter = winChance(selected.evalPawns, selected.mate)}
					<div class="rv-wc" class:drop={selected.wcDrop >= 5}>
						Win chance {Math.round(Math.min(100, wcAfter + selected.wcDrop))}% →
						{Math.round(wcAfter)}%{#if selected.wcDrop >= 1}&nbsp;(−{selected.wcDrop.toFixed(0)}%){/if}
					</div>
				{/if}

				{#snippet withEvidence(text: string)}
					{#if selected?.explanation?.evidence}
						<LineHover fen={selected.explanation.evidence.fen} ucis={selected.explanation.evidence.ucis} {orientation}>
							{text}
						</LineHover>
					{:else}
						{text}
					{/if}
				{/snippet}
				{#if selected.explanation?.playedPoint}
					<div class="rv-why">{@render withEvidence(selected.explanation.playedPoint)}</div>
				{/if}
				{#if selected.explanation?.playedIssue}
					<div class="rv-why">{@render withEvidence(selected.explanation.playedIssue)}</div>
				{/if}
				{#if selected.explanation?.bestPoint}
					<div class="rv-why">{selected.explanation.bestPoint}</div>
				{/if}
				{#if selected.explanation?.lineStory}
					<div class="rv-why">{@render withEvidence(selected.explanation.lineStory)}</div>
				{/if}

				{#if showBest && selected.bestSan}
					<div class="rv-bestline">
						<span class="rv-glyph" style:color={CLASS.best.color}>★</span>
						Best was
						{#if selected.explanation?.evidence}
							<LineHover
								fen={selected.explanation.evidence.fen}
								ucis={selected.explanation.evidence.ucis}
								{orientation}
							>
								<strong>{selected.bestSan}</strong>
							</LineHover>
						{:else}
							<strong>{selected.bestSan}</strong>
						{/if}
						{#if selected.pctBest !== null}<span class="rv-dim"> · {selected.pctBest.toFixed(0)}% of best</span>{/if}
					</div>
				{/if}

				<div class="rv-actions">
					{#if showBestBtn}
						<button class="rv-best" class:on={showBest} onclick={() => (showBest = !showBest)}>
							★ Best move
						</button>
					{/if}
					{#if itemable && onpractice}
						<button
							class="practice"
							disabled={added}
							onclick={() => {
								onpractice(selected);
								addedPly = reviewPly;
							}}
						>
							{added ? 'Added ✓' : '📌 Practice this'}
						</button>
					{/if}
				</div>
			</div>
		{:else}
			<div class="rv-card intro">Step through with the arrows or the move list below.</div>
		{/if}

		<!-- move controls -->
		<div class="rv-controls">
			<button onclick={() => ongoto(0)} disabled={reviewPly === 0} title="Start">«</button>
			<button onclick={() => ongoto(reviewPly - 1)} disabled={reviewPly === 0} title="Previous">‹</button>
			<button
				class="grow"
				onclick={() => ongoto(reviewPly + 1)}
				disabled={reviewPly >= reviewing.moves.length}>Next ›</button
			>
			<button
				onclick={() => ongoto(reviewing.moves.length)}
				disabled={reviewPly >= reviewing.moves.length}
				title="End">»</button
			>
		</div>

		<!-- two-column move table -->
		<div class="rv-table">
			{#each moveRows as row (row.no)}
				<div class="rv-mrow">
					<span class="rv-no">{row.no}.</span>
					{#each [row.white, row.black] as m, i (i)}
						{#if m}
							{@const cls = m.label ? CLASS[m.label] : null}
							<button class="rv-mv" class:sel={reviewPly === m.ply} onclick={() => ongoto(m.ply)}>
								<span class="rv-mvsan">{m.san}</span>
								{#if cls && m.label !== 'good' && m.label !== 'excellent'}
									<span class="rv-mvglyph" style:color={cls.color}>{cls.glyph}</span>
								{/if}
							</button>
						{:else}
							<span class="rv-mv empty"></span>
						{/if}
					{/each}
				</div>
			{/each}
		</div>
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
	.export {
		padding: 0 6px;
	}
	.show-more {
		margin-top: 6px;
		width: 100%;
	}
	/* ---- review mode (chess.com-style) ---- */
	.rv-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		font-size: 12px;
		color: var(--text-secondary);
		margin-bottom: 8px;
	}
	.rv-result strong {
		color: var(--text-primary);
	}
	.rv-headnav {
		display: flex;
		gap: 4px;
	}
	.rv-summary {
		border: 1px solid var(--border);
		border-radius: 8px;
		overflow: hidden;
		margin-bottom: 8px;
	}
	.rv-acc {
		display: flex;
	}
	.rv-player {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 8px 4px;
		gap: 1px;
	}
	.rv-player:first-child {
		border-right: 1px solid var(--border);
	}
	.rv-player.active {
		background: var(--bg-highlight);
	}
	.rv-name {
		font-size: 12px;
		color: var(--text-secondary);
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.rv-accval {
		font-size: 20px;
		font-weight: 700;
		color: var(--text-primary);
		font-variant-numeric: tabular-nums;
	}
	.rv-acclbl {
		font-size: 10px;
		text-transform: uppercase;
		letter-spacing: 0.5px;
		color: var(--text-secondary);
	}
	.rv-counts {
		border-top: 1px solid var(--border);
		padding: 4px 0;
	}
	.rv-crow {
		display: grid;
		grid-template-columns: 40px 1fr 40px;
		align-items: center;
		padding: 2px 8px;
		font-size: 12px;
	}
	.rv-cmid {
		display: flex;
		align-items: center;
		gap: 8px;
		justify-content: center;
	}
	.rv-glyph {
		font-weight: 800;
		font-size: 13px;
	}
	.rv-cname {
		color: var(--text-secondary);
		text-transform: capitalize;
	}
	.rv-cnum {
		text-align: center;
		font-weight: 600;
		color: var(--text-primary);
		font-variant-numeric: tabular-nums;
	}
	.rv-card {
		border: 1px solid var(--border);
		border-left-width: 4px;
		border-radius: 6px;
		padding: 8px 10px;
		margin-bottom: 8px;
		font-size: 13px;
		color: var(--text-primary);
	}
	.rv-card.intro {
		color: var(--text-secondary);
		border-left-color: var(--border);
	}
	.rv-cardhead {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.rv-cglyph {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		min-width: 20px;
		height: 20px;
		padding: 0 5px;
		border-radius: 10px;
		color: #fff;
		font-weight: 800;
		font-size: 12px;
	}
	.rv-cardtitle {
		flex: 1;
	}
	.rv-cardeval {
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		color: var(--text-secondary);
	}
	.rv-cardeval.drop {
		color: var(--color-lose);
	}
	.rv-wc {
		margin-top: 4px;
		font-size: 12px;
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.rv-wc.drop {
		color: var(--color-lose);
	}
	.rv-why {
		margin-top: 6px;
		font-size: 12px;
		color: var(--text-secondary);
		line-height: 1.4;
	}
	.rv-bestline {
		margin-top: 6px;
		font-size: 12px;
		color: var(--text-primary);
	}
	.rv-dim {
		color: var(--text-secondary);
	}
	.rv-actions {
		display: flex;
		gap: 6px;
		margin-top: 8px;
	}
	.rv-best.on {
		border-color: var(--color-win);
		color: var(--color-win);
	}
	button.practice {
		border-color: var(--color-win);
	}
	button.practice:disabled {
		opacity: 1;
		color: var(--text-secondary);
		border-color: var(--border);
	}
	.rv-controls {
		display: flex;
		gap: 4px;
		margin-bottom: 8px;
	}
	.rv-controls .grow {
		flex: 1;
	}
	.rv-table {
		max-height: 220px;
		overflow-y: auto;
		border: 1px solid var(--border);
		border-radius: 6px;
	}
	.rv-mrow {
		display: grid;
		grid-template-columns: 34px 1fr 1fr;
		align-items: stretch;
	}
	.rv-mrow:nth-child(odd) {
		background: var(--bg-highlight);
	}
	.rv-no {
		display: flex;
		align-items: center;
		padding-left: 8px;
		font-size: 12px;
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.rv-mv {
		display: flex;
		align-items: center;
		gap: 4px;
		background: none;
		border: none;
		border-radius: 0;
		padding: 3px 8px;
		font-size: 13px;
		text-align: left;
		color: var(--text-primary);
	}
	.rv-mv.empty {
		cursor: default;
	}
	.rv-mv.sel {
		background: var(--bg-button);
		outline: 1px solid var(--text-secondary);
		outline-offset: -1px;
	}
	.rv-mvglyph {
		font-weight: 800;
		font-size: 12px;
	}
	.crown {
		font-size: 13px;
		cursor: help;
		line-height: 1;
	}
	.crown.clean {
		color: #d4a017; /* the solid gold crown: blind, unassisted, won */
	}
	.crown.helped {
		color: var(--text-secondary);
		opacity: 0.7;
	}
	.legend {
		font-size: 11px;
		color: var(--text-secondary);
		padding: 6px 2px 0;
	}
	.legend .crown {
		cursor: default;
	}
</style>
