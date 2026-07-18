<script lang="ts">
	import { Chessground } from 'chessground';
	import type { Api } from 'chessground/api';
	import type { Key, Color } from 'chessground/types';
	import type { EngineMove } from '$lib/engine/stockfish';

	interface Props {
		fen: string;
		turn: 'w' | 'b';
		legalMoves: { from: string; to: string }[];
		orientation?: 'white' | 'black';
		engineMoves?: EngineMove[];
		botArrow?: string | null; // uci the bot is currently considering
		threatArrow?: string | null; // what the opponent threatens (null-move probe), drawn as a warning
		threatTargets?: string[]; // the pieces that threat wins, minus the arrow's own destination
		refutationArrow?: string | null; // opponent's punishing reply, drawn red
		hintSquare?: string | null; // practice tier-2 hint: circle the best move's origin square
		control?: Map<string, 'w' | 'b'> | null; // per-square control tint (see engine/control.ts)
		resetKey?: number; // bump to force a piece resync (e.g. cancelled promotion)
		lastMove?: [string, string] | null;
		size?: number; // board edge in px (still capped at 90vw)
		boundsKey?: unknown; // change when layout SHIFTS the board without resizing it
		onmove?: (from: string, to: string) => void;
	}

	let {
		fen,
		turn,
		legalMoves,
		orientation = 'white',
		engineMoves = [],
		botArrow = null,
		threatArrow = null,
		threatTargets = [],
		refutationArrow = null,
		hintSquare = null,
		control = null,
		resetKey = 0,
		lastMove = null,
		size = 500,
		boundsKey = 0,
		onmove
	}: Props = $props();

	let boardEl: HTMLDivElement;
	let api: Api | undefined = $state();

	function toDests(): Map<Key, Key[]> {
		const dests = new Map<Key, Key[]>();
		for (const m of legalMoves) {
			const existing = dests.get(m.from as Key) || [];
			existing.push(m.to as Key);
			dests.set(m.from as Key, existing);
		}
		return dests;
	}

	// which squares hold a piece — control renders as a RING there (a claim
	// about the piece) and as a wash on empty squares (a claim about territory)
	function occupiedSquares(f: string): Set<string> {
		const out = new Set<string>();
		const ranks = f.split(' ')[0].split('/');
		for (let r = 0; r < 8; r++) {
			let file = 0;
			for (const ch of ranks[r]) {
				if (ch >= '1' && ch <= '8') file += +ch;
				else out.add('abcdefgh'[file++] + (8 - r));
			}
		}
		return out;
	}

	function makeArrows(): [Key, Key][] {
		if (!engineMoves.length) return [];
		return engineMoves
			.slice(0, 3)
			.filter((m) => m.pv.length > 0)
			.map((m, i) => {
				const uci = m.pv[0];
				const from = uci.slice(0, 2) as Key;
				const to = uci.slice(2, 4) as Key;
				return [from, to] as [Key, Key];
			});
	}

	// the engine's moves share one hue (green); rank shows as opacity, so the
	// best move reads boldest and weaker candidates fade back
	function brushForRank(rank: number): string {
		if (rank === 0) return 'g0';
		if (rank === 1) return 'g1';
		return 'g2';
	}

	// chessground's brush registry (keyed by name). The defaults must stay
	// present; we add green opacity tiers (g0–g2) for ranked engine moves and a
	// red threat arrow. paleGrey is kept for the bot's considered move.
	const BRUSHES = {
		green: { key: 'green', color: '#15781b', opacity: 1, lineWidth: 10 },
		red: { key: 'red', color: '#882020', opacity: 1, lineWidth: 10 },
		blue: { key: 'blue', color: '#003088', opacity: 1, lineWidth: 10 },
		yellow: { key: 'yellow', color: '#e68f00', opacity: 1, lineWidth: 10 },
		paleGrey: { key: 'paleGrey', color: '#4a4a4a', opacity: 0.35, lineWidth: 15 },
		g0: { key: 'g0', color: '#15781b', opacity: 1, lineWidth: 12 },
		g1: { key: 'g1', color: '#15781b', opacity: 0.55, lineWidth: 11 },
		g2: { key: 'g2', color: '#15781b', opacity: 0.32, lineWidth: 10 },
		threat: { key: 'threat', color: '#c62828', opacity: 0.9, lineWidth: 12 }
	};

	$effect(() => {
		if (!boardEl || api) return;
		api = Chessground(boardEl, {
			fen,
			orientation,
			turnColor: turn === 'w' ? 'white' : 'black',
			movable: {
				free: false,
				color: turn === 'w' ? 'white' : 'black',
				dests: toDests()
			},
			draggable: { showGhost: true },
			drawable: { brushes: BRUSHES },
			events: {
				move: (orig, dest) => onmove?.(orig, dest)
			}
		});
	});

	// chessground positions pieces with px translates and memoizes its bounding
	// box for click mapping — recompute when the box resizes OR when the layout
	// moves it (e.g. the sidebar collapses and the board re-centers)
	$effect(() => {
		size;
		boundsKey;
		api?.redrawAll();
	});

	$effect(() => {
		if (!api) return;
		resetKey; // dep: re-sync pieces when bumped
		const turnColor: Color = turn === 'w' ? 'white' : 'black';
		const occ = occupiedSquares(fen);
		const threatSquares = new Set([
			...threatTargets,
			...(threatArrow ? [threatArrow.slice(2, 4)] : [])
		]);
		api.set({
			fen,
			turnColor,
			orientation,
			lastMove: lastMove ? (lastMove as [Key, Key]) : undefined,
			highlight: {
				lastMove: true,
				// green = the side at the bottom of the board, red = the other side
				custom: new Map<Key, string>(
					[...(control ?? [])].flatMap(([sq, side]): [Key, string][] => {
						const ours = (side === 'w') === (orientation === 'white');
						if (!occ.has(sq)) return [[sq as Key, ours ? 'ctrl-us' : 'ctrl-them']];
						// the threat overlay's rings outrank control's on the same piece
						if (threatSquares.has(sq)) return [];
						return [[sq as Key, ours ? 'ctrl-us-ring' : 'ctrl-them-ring']];
					})
				)
			},
			movable: {
				color: turnColor,
				dests: toDests()
			},
			drawable: {
				autoShapes: [
					...makeArrows().map(([from, to], i) => ({
						orig: from,
						dest: to,
						brush: brushForRank(i)
					})),
					...(botArrow
						? [
								{
									orig: botArrow.slice(0, 2) as Key,
									dest: botArrow.slice(2, 4) as Key,
									brush: 'paleGrey'
								}
							]
						: []),
					...(threatArrow
						? [
								{
									orig: threatArrow.slice(0, 2) as Key,
									dest: threatArrow.slice(2, 4) as Key,
									brush: 'threat'
								}
							]
						: []),
					// the pieces the threat wins, ringed — the arrow shows the MOVE, and
					// on a quiet setup move (fork, mate threat, chase) the victims stand elsewhere
					...threatTargets.map((t) => ({ orig: t as Key, brush: 'threat' })),
					...(refutationArrow
						? [
								{
									orig: refutationArrow.slice(0, 2) as Key,
									dest: refutationArrow.slice(2, 4) as Key,
									brush: 'red'
								}
							]
						: []),
					...(hintSquare ? [{ orig: hintSquare as Key, brush: 'yellow' }] : [])
				]
			}
		});
	});
</script>

<svelte:window onresize={() => api?.redrawAll()} />

<div class="board-wrap" style:width="{size}px">
	<div class="board" bind:this={boardEl}></div>
</div>

<style>
	.board-wrap {
		aspect-ratio: 1;
		max-width: 100%; /* never wider than .board-col's viewport cap */
	}
	.board {
		width: 100%;
		height: 100%;
	}
	/* square-control tint (chessground highlight.custom classes). The tint
	   sets `background`, which chessground's own square signals (move-dest
	   dots, selection, last-move) also use — so every combination re-stacks
	   the signal ON TOP of the tint as a multi-background. */
	.board :global(cg-board square.ctrl-us) {
		--ctrl-tint: radial-gradient(
			circle,
			rgba(129, 182, 76, 0.38) 0%,
			rgba(129, 182, 76, 0.14) 100%
		);
		background: var(--ctrl-tint);
	}
	.board :global(cg-board square.ctrl-them) {
		--ctrl-tint: radial-gradient(
			circle,
			rgba(202, 52, 49, 0.38) 0%,
			rgba(202, 52, 49, 0.14) 100%
		);
		background: var(--ctrl-tint);
	}
	/* occupied squares: a ring around the piece — the wash says "this square
	   is owned", the ring says "this PIECE is winnable / falling" */
	.board :global(cg-board square.ctrl-us-ring) {
		--ctrl-tint: radial-gradient(
			circle,
			transparent 0%,
			transparent 60%,
			rgba(129, 182, 76, 0.55) 65%,
			rgba(129, 182, 76, 0.55) 76%,
			transparent 81%
		);
		background: var(--ctrl-tint);
	}
	.board :global(cg-board square.ctrl-them-ring) {
		--ctrl-tint: radial-gradient(
			circle,
			transparent 0%,
			transparent 60%,
			rgba(202, 52, 49, 0.55) 65%,
			rgba(202, 52, 49, 0.55) 76%,
			transparent 81%
		);
		background: var(--ctrl-tint);
	}
	.board :global(cg-board square.move-dest[class*='ctrl-']) {
		background:
			radial-gradient(rgba(20, 85, 30, 0.5) 22%, #208530 0, rgba(0, 0, 0, 0.3) 0, rgba(0, 0, 0, 0) 0),
			var(--ctrl-tint);
	}
	.board :global(cg-board square.oc.move-dest[class*='ctrl-']) {
		background:
			radial-gradient(transparent 0%, transparent 80%, rgba(20, 85, 0, 0.3) 80%),
			var(--ctrl-tint);
	}
	.board :global(cg-board square.move-dest[class*='ctrl-']:hover) {
		background:
			linear-gradient(rgba(20, 85, 30, 0.3), rgba(20, 85, 30, 0.3)),
			var(--ctrl-tint);
	}
	.board :global(cg-board square.selected[class*='ctrl-']) {
		background:
			linear-gradient(rgba(20, 85, 30, 0.5), rgba(20, 85, 30, 0.5)),
			var(--ctrl-tint);
	}
	.board :global(cg-board square.last-move[class*='ctrl-']) {
		background:
			linear-gradient(rgba(155, 199, 0, 0.41), rgba(155, 199, 0, 0.41)),
			var(--ctrl-tint);
	}
</style>
