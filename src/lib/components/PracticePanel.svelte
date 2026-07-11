<script lang="ts">
	import type { AttemptResult, PracticeItem } from '$lib/practice';
	import { dueCount } from '$lib/practice';

	interface Props {
		mode: 'play' | 'practice' | 'review';
		items: PracticeItem[];
		current: PracticeItem | null;
		attempt: AttemptResult | null;
		grading: boolean;
		revealBest: boolean;
		lineDepth?: number; // "Continue" steps past the stored puzzle
		lineNote?: string | null; // the continued line ended (e.g. mate)
		continuing?: boolean; // engine is playing the opponent's reply
		threshold: number;
		onstart: () => void;
		onexit: () => void;
		onnext: () => void;
		onretry: () => void;
		onreveal: () => void;
		oncontinue?: () => void;
		onremove: (id: string) => void;
		onthreshold: (n: number) => void;
	}

	let {
		mode, items, current, attempt, grading, revealBest,
		lineDepth = 0, lineNote = null, continuing = false, threshold,
		onstart, onexit, onnext, onretry, onreveal, oncontinue, onremove, onthreshold
	}: Props = $props();

	const due = $derived(dueCount(items));

	function fmtEval(pawns: number | null, mate: number | null): string {
		if (mate !== null) return `M${mate}`;
		if (pawns === null) return '?';
		return (pawns >= 0 ? '+' : '') + pawns.toFixed(2);
	}

	function sideToMove(fen: string): string {
		return fen.split(' ')[1] === 'b' ? 'Black' : 'White';
	}

	function fmtDue(iso: string): string {
		const ms = Date.parse(iso) - Date.now();
		if (ms <= 0) return 'due now';
		const h = ms / 3_600_000;
		if (h < 1) return `due in ${Math.max(1, Math.round(ms / 60_000))}m`;
		if (h < 48) return `due in ${Math.round(h)}h`;
		return `due in ${Math.round(h / 24)}d`;
	}

	const sorted = $derived(
		[...items].sort((a, b) => Date.parse(a.dueAt) - Date.parse(b.dueAt))
	);
</script>

<div class="practice-panel">
	{#if mode !== 'practice'}
		<div class="toolbar">
			<span class="summary">
				{items.length === 0
					? `No positions collected yet — moves losing ≥${threshold}% win chance are saved here automatically as you play.`
					: `${items.length} position${items.length === 1 ? '' : 's'} · ${due} due`}
			</span>
			<label class="thresh">
				Collect at ≥
				<select
					value={String(threshold)}
					onchange={(e) => onthreshold(Number(e.currentTarget.value))}
				>
					<option value="5">5</option>
					<option value="10">10</option>
					<option value="15">15</option>
					<option value="20">20</option>
					<option value="30">30</option>
				</select>
				% drop
			</label>
			<button class="primary" onclick={onstart} disabled={items.length === 0}>Start practice</button>
		</div>
		{#if sorted.length > 0}
			<div class="list">
				{#each sorted as item (item.id)}
					<div class="row">
						<span class="side">{sideToMove(item.fen)}</span>
						<span class="moves">
							played <strong>{item.playedSan}</strong>, best <strong>{item.bestSan}</strong>
						</span>
						<span class="drop">−{item.drop.toFixed(0)}%</span>
						<span class="due">{fmtDue(item.dueAt)}</span>
						<span class="stats">{item.correct}/{item.attempts}</span>
						<button class="remove" title="Remove" onclick={() => onremove(item.id)}>×</button>
					</div>
				{/each}
			</div>
		{/if}
	{:else}
		<div class="toolbar">
			{#if !current}
				<span class="summary">All caught up — nothing due. 🎉</span>
			{:else if lineDepth > 0}
				<span class="summary">
					Continuing the line (move +{lineDepth}) — find a strong move
					<span class="hint">(pass: a good move or better — under 5% win-chance loss)</span>
				</span>
			{:else}
				<span class="summary">
					<strong>{sideToMove(current.fen)}</strong> to move — find a strong move
					<span class="hint">(pass: a good move or better · you lost {current.drop.toFixed(0)}% here with {current.playedSan})</span>
				</span>
			{/if}
			<button onclick={onexit}>Exit practice</button>
		</div>

		{#if current}
			{#if lineNote}
				<div class="result">
					{lineNote}
					<span class="actions">
						<button class="primary" onclick={onnext}>Next puzzle</button>
					</span>
				</div>
			{:else if grading}
				<div class="result">Checking your move…</div>
			{:else if continuing}
				<div class="result">Opponent thinking…</div>
			{:else if attempt}
				<div class="result" class:pass={attempt.pass} class:fail={!attempt.pass}>
					{#if attempt.pass}
						✓ <strong>{attempt.san}</strong> ({fmtEval(attempt.evalPawns, attempt.mate)})
						{#if attempt.label}<span class="chip {attempt.label}">{attempt.label}</span>{/if}
						{#if attempt.label === 'best'}
							— the engine's move.
						{:else if attempt.drop <= 0}
							— as strong as the engine's best here.
						{:else}
							— costs {attempt.drop < 1 ? '<1' : attempt.drop.toFixed(0)}% win chance.
						{/if}
						{#if attempt.playedPoint}
							{attempt.playedPoint}
						{/if}
					{:else}
						✗ <strong>{attempt.san}</strong> ({fmtEval(attempt.evalPawns, attempt.mate)})
						{#if attempt.label}<span class="chip {attempt.label}">{attempt.label}</span>{/if}
						— drops {attempt.drop.toFixed(0)}% win chance.
						{#if attempt.playedIssue}
							{attempt.playedIssue}
						{:else if attempt.lineStory}
							{attempt.lineStory}
						{:else if attempt.refutationSan}
							Punished by <strong class="refutation">{attempt.refutationSan}</strong> (red arrow).
						{/if}
						Best was <strong>{revealBest ? current.bestSan : '…'}</strong>.
						{#if revealBest && attempt.bestPoint}
							{attempt.bestPoint}
						{/if}
					{/if}
					<span class="actions">
						{#if !attempt.pass}
							<button onclick={onretry}>Retry</button>
						{/if}
						{#if !revealBest}
							<button onclick={onreveal}>Show best</button>
						{/if}
						{#if oncontinue}
							<button onclick={oncontinue} title="Opponent plays its best reply — find your next move">
								Continue ▸
							</button>
						{/if}
						<button class="primary" onclick={onnext}>Next</button>
					</span>
				</div>
			{:else}
				<div class="result muted">Play your move on the board.</div>
			{/if}
		{/if}
	{/if}
</div>

<style>
	.practice-panel {
		font-family: system-ui, sans-serif;
	}
	.toolbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		flex-wrap: wrap;
	}
	.summary {
		font-size: 13px;
		color: var(--text-primary);
	}
	.hint {
		color: var(--text-secondary);
		font-size: 12px;
	}
	.thresh {
		display: flex;
		align-items: center;
		gap: 4px;
		font-size: 12px;
		color: var(--text-secondary);
		white-space: nowrap;
	}
	.thresh select {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 2px 4px;
	}
	button {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 4px 12px;
		font-size: 12px;
		cursor: pointer;
		white-space: nowrap;
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
	.list {
		margin-top: 8px;
		max-height: 200px;
		overflow-y: auto;
	}
	.row {
		display: flex;
		align-items: baseline;
		gap: 10px;
		padding: 3px 6px;
		font-size: 12px;
		border-radius: 3px;
		color: var(--text-primary);
	}
	.row:nth-child(odd) {
		background: var(--bg-highlight);
	}
	.side {
		width: 40px;
		color: var(--text-secondary);
	}
	.moves {
		flex: 1;
	}
	.drop {
		color: var(--color-lose);
		font-variant-numeric: tabular-nums;
	}
	.due,
	.stats {
		color: var(--text-secondary);
		font-variant-numeric: tabular-nums;
	}
	.remove {
		padding: 0 6px;
		line-height: 1.2;
	}
	.result {
		margin-top: 10px;
		font-size: 13px;
		padding: 8px 10px;
		border-radius: 6px;
		border: 1px solid var(--border);
		display: flex;
		align-items: center;
		gap: 10px;
		flex-wrap: wrap;
	}
	.result.pass {
		border-color: var(--color-win);
		background: color-mix(in srgb, var(--color-win) 10%, transparent);
	}
	.result.fail {
		border-color: var(--color-lose);
		background: color-mix(in srgb, var(--color-lose) 10%, transparent);
	}
	.result.muted {
		color: var(--text-secondary);
	}
	.refutation {
		color: var(--color-lose);
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
	.actions {
		margin-left: auto;
		display: flex;
		gap: 6px;
	}
</style>
