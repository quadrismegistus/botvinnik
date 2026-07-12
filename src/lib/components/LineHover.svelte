<script lang="ts">
	import { Chess, type Square } from 'chess.js';
	import { Chessground } from 'chessground';
	import type { Api } from 'chessground/api';
	import type { Key } from 'chessground/types';
	import { untrack } from 'svelte';
	import type { Snippet } from 'svelte';

	interface Props {
		fen: string; // position before the line
		ucis: string[]; // the line to play through
		children: Snippet;
	}

	let { fen, ucis, children }: Props = $props();

	const SIZE = 180;
	let show = $state(false);
	let pos = $state({ x: 0, y: 0 });
	let boardEl: HTMLElement | null = $state(null);
	let api: Api | null = null;

	// position after each ply; frame 0 is the starting position
	const frames = $derived.by(() => {
		const c = new Chess(fen);
		const out: { fen: string; lastMove?: [Key, Key] }[] = [{ fen }];
		for (const uci of ucis.slice(0, 12)) {
			try {
				const m = c.move({
					from: uci.slice(0, 2) as Square,
					to: uci.slice(2, 4) as Square,
					promotion: uci.length > 4 ? uci[4] : undefined
				});
				out.push({ fen: c.fen(), lastMove: [m.from as Key, m.to as Key] });
			} catch {
				break;
			}
		}
		return out;
	});

	function enter(e: MouseEvent) {
		const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
		const x = Math.max(8, Math.min(r.left, window.innerWidth - SIZE - 16));
		// above the text when there's room, below otherwise
		const y = r.top > SIZE + 24 ? r.top - SIZE - 12 : r.bottom + 8;
		pos = { x, y };
		show = true;
	}

	// touch devices have no hover: tap toggles the preview, tapping anywhere
	// else dismisses it
	const touchOnly =
		typeof window !== 'undefined' && window.matchMedia('(hover: none)').matches;

	function tap(e: MouseEvent) {
		if (!touchOnly) return;
		e.stopPropagation();
		if (show) show = false;
		else enter(e);
	}

	$effect(() => {
		if (!show || !touchOnly) return;
		const close = () => (show = false);
		window.addEventListener('click', close);
		return () => window.removeEventListener('click', close);
	});

	$effect(() => {
		if (!show || !boardEl) return;
		// the animation must NOT restart every time the engine refines `frames`
		// (lines stream during analysis) — read frames untracked; the interval
		// callback always sees the latest version anyway
		const first = untrack(() => frames[0]);
		if (!first) return;
		api = Chessground(boardEl, {
			fen: first.fen,
			orientation: fen.split(' ')[1] === 'b' ? 'black' : 'white',
			viewOnly: true,
			coordinates: false,
			animation: { enabled: true, duration: 260 }
		});
		let i = 0;
		const timer = setInterval(() => {
			i = (i + 1) % Math.max(1, frames.length); // wraps back and replays
			const f = frames[i] ?? frames[0];
			api?.set({ fen: f.fen, lastMove: f.lastMove });
		}, 1000);
		return () => {
			clearInterval(timer);
			api?.destroy();
			api = null;
		};
	});
</script>

<!-- svelte-ignore a11y_no_static_element_interactions, a11y_click_events_have_key_events -->
<span
	class="line-hover"
	onmouseenter={(e) => {
		// touch browsers synthesize mouseenter right before click — letting it
		// open the popup makes the click instantly toggle it shut again
		if (!touchOnly) enter(e);
	}}
	onmouseleave={() => {
		if (!touchOnly) show = false;
	}}
	onclick={tap}
>
	{@render children()}
	{#if show && frames.length > 1}
		<div class="popup" style:left="{pos.x}px" style:top="{pos.y}px">
			<div class="mini" style:width="{SIZE}px" style:height="{SIZE}px" bind:this={boardEl}></div>
		</div>
	{/if}
</span>

<style>
	.line-hover {
		cursor: default;
		border-bottom: 1px dotted var(--border);
	}
	.popup {
		position: fixed;
		z-index: 60;
		padding: 4px;
		background: var(--bg-panel);
		border: 1px solid var(--border);
		border-radius: 6px;
		box-shadow: 0 4px 16px rgba(0, 0, 0, 0.35);
		pointer-events: none;
	}
</style>
