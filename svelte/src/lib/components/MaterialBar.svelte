<script lang="ts">
	// A lichess-style material strip for one player: the pieces this side has
	// captured (the opponent's missing pieces) plus a +N point advantage when
	// this side is ahead. Reads straight off the FEN so it needs no move history.

	interface Props {
		fen: string;
		color: 'w' | 'b'; // the player this bar belongs to
	}
	let { fen, color }: Props = $props();

	const VALUE: Record<string, number> = { p: 1, n: 3, b: 3, r: 3, q: 9 };
	// bishops are worth 3 for the advantage sum too; keep it simple (no bishop pair)
	VALUE.b = 3;
	const START: Record<string, number> = { p: 8, n: 2, b: 2, r: 2, q: 1 };
	const ORDER = ['q', 'r', 'b', 'n', 'p'] as const;
	// glyphs are drawn in the OPPONENT's colour (they're the opponent's captured
	// pieces): white bar shows black glyphs, black bar shows white glyphs
	const GLYPH: Record<'w' | 'b', Record<string, string>> = {
		w: { q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' }, // white captured → black pieces
		b: { q: '♕', r: '♖', b: '♗', n: '♘', p: '♙' }
	};

	const info = $derived.by(() => {
		const board = fen.split(' ')[0] ?? '';
		// count each colour's living pieces
		const live: Record<'w' | 'b', Record<string, number>> = {
			w: { p: 0, n: 0, b: 0, r: 0, q: 0 },
			b: { p: 0, n: 0, b: 0, r: 0, q: 0 }
		};
		for (const ch of board) {
			const lower = ch.toLowerCase();
			if (lower in START) live[ch === lower ? 'b' : 'w'][lower]++;
		}
		const opp: 'w' | 'b' = color === 'w' ? 'b' : 'w';
		// pieces this side captured = opponent's missing pieces
		const captured: { type: string; n: number }[] = [];
		let advantage = 0;
		for (const t of ORDER) {
			const taken = START[t] - live[opp][t];
			if (taken > 0) captured.push({ type: t, n: taken });
		}
		for (const t of ORDER) advantage += (live[color][t] - live[opp][t]) * VALUE[t];
		return { captured, advantage, glyphs: GLYPH[color] };
	});
</script>

<div class="material" aria-label="captured material">
	<span class="pieces">
		{#each info.captured as c (c.type)}
			{#each Array.from({ length: c.n }) as _, i (i)}<span class="pc">{info.glyphs[c.type]}</span
				>{/each}
		{/each}
	</span>
	{#if info.advantage > 0}
		<span class="adv">+{info.advantage}</span>
	{/if}
</div>

<style>
	.material {
		display: flex;
		align-items: center;
		gap: 2px;
		height: 20px; /* fixed: content changes must not shift the board (stale click bounds) */
		overflow: hidden;
		font-size: 15px;
		line-height: 1;
		color: var(--text-secondary);
		padding: 0 2px;
	}
	.pieces {
		display: flex;
		flex-wrap: nowrap;
	}
	.pc {
		margin-right: -3px; /* overlap slightly, lichess-style */
	}
	.adv {
		margin-left: 6px;
		font-size: 12px;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
		color: var(--text-primary);
	}
</style>
