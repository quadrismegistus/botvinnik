<script lang="ts">
	import {
		formatGames,
		getExplorer,
		setLichessToken,
		unifyMoves,
		type ExplorerPosition,
		type BookStats,
		type UnifiedMove
	} from '$lib/explorer';
	import type { EngineMove } from '$lib/engine/stockfish';

	interface Props {
		fen: string;
		lines: EngineMove[]; // already blind-mode filtered by the caller
		blind?: boolean;
		onplay?: (uci: string) => void;
	}

	let { fen, lines, blind = false, onplay }: Props = $props();

	let lichess = $state<ExplorerPosition | null>(null);
	let masters = $state<ExplorerPosition | null>(null);
	let status = $state<'loading' | 'ok' | 'auth' | 'error'>('loading');
	let tokenDraft = $state('');
	let tokenVersion = $state(0); // bumped on save to re-run the fetch effect

	// small debounce so stepping quickly through moves doesn't hammer the API;
	// the module-level cache makes revisited positions instant
	$effect(() => {
		const f = fen;
		tokenVersion;
		if (blind) return;
		status = 'loading';
		const t = setTimeout(() => {
			void Promise.all([getExplorer('lichess', f), getExplorer('masters', f)])
				.then(([l, m]) => {
					if (f !== fen) return;
					lichess = l;
					masters = m;
					status = 'ok';
				})
				.catch((e) => {
					if (f === fen) status = e instanceof Error && e.message === 'auth' ? 'auth' : 'error';
				});
		}, 350);
		return () => clearTimeout(t);
	});

	function saveToken() {
		if (!tokenDraft.trim()) return;
		setLichessToken(tokenDraft);
		tokenDraft = '';
		tokenVersion++;
	}

	const rows: UnifiedMove[] = $derived(
		unifyMoves(fen, lines, status === 'ok' ? lichess : null, status === 'ok' ? masters : null)
	);
	const opening = $derived(status === 'ok' ? (lichess?.opening ?? masters?.opening ?? null) : null);

	function fmtScore(e: { score: number; mate: number | null }): string {
		if (e.mate !== null) return `M${e.mate}`;
		return e.score >= 0 ? `+${e.score.toFixed(2)}` : e.score.toFixed(2);
	}
</script>

<div class="unified">
	{#if blind}
		<div class="note">Hidden in blind mode.</div>
	{:else}
		{#if opening}
			<div class="opening"><span class="eco">{opening.eco}</span> {opening.name}</div>
		{/if}
		{#if status === 'auth'}
			<div class="note">
				Lichess now requires a (free) API token for book stats.
				<a
					href="https://lichess.org/account/oauth/token/create?description=botvinnik+opening+explorer"
					target="_blank"
					rel="noreferrer">Create one</a
				>
				(no scopes needed, just Submit) and paste it here — stored only in this browser:
			</div>
			<form
				class="token-form"
				onsubmit={(e) => {
					e.preventDefault();
					saveToken();
				}}
			>
				<input type="password" placeholder="lip_…" autocomplete="off" bind:value={tokenDraft} />
				<button type="submit" disabled={!tokenDraft.trim()}>Save</button>
			</form>
		{:else if rows.length === 0}
			<div class="note">
				{status === 'loading'
					? 'Loading book…'
					: status === 'error'
						? 'Opening explorer unavailable.'
						: 'Out of book — no games from here.'}
			</div>
		{:else}
			<table>
				<thead>
					<tr><th class="left">Move</th><th class="left">Eval</th><th>Lichess</th><th>Masters</th></tr>
				</thead>
				<tbody>
					{#each rows as r (r.uci)}
						<tr
							class:playable={!!onplay}
							onclick={() => onplay?.(r.uci)}
							title={onplay ? `Play ${r.san}` : undefined}
						>
							<td class="san">{r.san}</td>
							<td class="eval">
								{#if r.engine}
									<span class="score">{fmtScore(r.engine)}</span>
									<span class="conf">{Math.round(r.engine.confidence)}%</span>
								{:else}
									<span class="dash">—</span>
								{/if}
							</td>
							{#each [r.lichess, r.masters] as book, bi (bi)}
								<td class="book">
									{#if book}
										{@render bookCell(book)}
									{:else}
										<span class="dash">—</span>
									{/if}
								</td>
							{/each}
						</tr>
					{/each}
				</tbody>
			</table>
			{#if status === 'loading'}
				<div class="note">Loading book…</div>
			{:else if status === 'error'}
				<div class="note">Opening explorer unavailable — engine lines only.</div>
			{/if}
		{/if}
	{/if}
</div>

{#snippet bookCell(book: BookStats)}
	<div class="cell">
		<span class="pct">{book.pct >= 1 ? Math.round(book.pct) : '<1'}%</span>
		<span class="games">{formatGames(book.games)}</span>
	</div>
	<div class="wdl" title="white / draw / black">
		<span class="w" style:width="{book.white}%"></span>
		<span class="d" style:width="{book.draws}%"></span>
		<span class="b" style:width="{book.black}%"></span>
	</div>
{/snippet}

<style>
	.unified {
		font-size: 13px;
	}
	.opening {
		font-size: 12px;
		color: var(--text-secondary);
		margin-bottom: 6px;
	}
	.eco {
		font-weight: 600;
	}
	.note {
		font-size: 12px;
		color: var(--text-secondary);
		padding: 4px 0;
	}
	.note a {
		color: var(--text-primary);
	}
	.token-form {
		display: flex;
		gap: 6px;
		margin-top: 6px;
	}
	.token-form input {
		flex: 1;
		min-width: 0;
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 4px 8px;
	}
	.token-form button {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 4px 12px;
		cursor: pointer;
	}
	.token-form button:disabled {
		opacity: 0.5;
		cursor: default;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-variant-numeric: tabular-nums;
	}
	th {
		font-size: 11px;
		font-weight: 600;
		color: var(--text-secondary);
		text-align: right;
		padding: 2px 6px;
	}
	th.left {
		text-align: left;
	}
	td {
		padding: 4px 6px;
		border-top: 1px solid var(--border);
	}
	tr.playable {
		cursor: pointer;
	}
	tr.playable:hover {
		background: var(--bg-highlight);
	}
	.san {
		font-weight: 600;
		color: var(--text-primary);
		white-space: nowrap;
	}
	.eval {
		white-space: nowrap;
	}
	.score {
		font-weight: 600;
	}
	.conf {
		font-size: 11px;
		color: var(--text-secondary);
		margin-left: 4px;
	}
	.book {
		text-align: right;
		min-width: 76px;
	}
	.cell {
		display: flex;
		justify-content: flex-end;
		gap: 6px;
		white-space: nowrap;
	}
	.pct {
		font-weight: 600;
	}
	.games {
		color: var(--text-secondary);
		font-size: 11px;
	}
	.dash {
		color: var(--text-secondary);
	}
	.wdl {
		display: flex;
		height: 5px;
		margin-top: 3px;
		border-radius: 3px;
		overflow: hidden;
		border: 1px solid var(--border);
	}
	.wdl .w {
		background: #e8e6e3;
	}
	.wdl .d {
		background: #999;
	}
	.wdl .b {
		background: #3a3a3a;
	}
</style>
