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
		refutationArrow?: string | null; // opponent's punishing reply, drawn red
		hintSquare?: string | null; // practice tier-2 hint: circle the best move's origin square
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
		refutationArrow = null,
		hintSquare = null,
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
		api.set({
			fen,
			turnColor,
			orientation,
			lastMove: lastMove ? (lastMove as [Key, Key]) : undefined,
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
	}
	.board {
		width: 100%;
		height: 100%;
	}
</style>
