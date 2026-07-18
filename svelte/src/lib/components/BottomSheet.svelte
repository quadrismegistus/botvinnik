<script lang="ts">
	import type { Snippet } from 'svelte';

	type Detent = 'peek' | 'half' | 'full';

	interface Props {
		detent?: Detent;
		peek?: number; // px height of the collapsed sheet (handle + tab strip)
		header: Snippet;
		children: Snippet;
	}

	let { detent = $bindable('peek'), peek = 64, header, children }: Props = $props();

	let vh = $state(800);
	const heights = $derived({
		peek,
		half: Math.round(vh * 0.5),
		full: Math.round(vh * 0.92)
	});

	// while a drag is live the sheet tracks the finger directly (no transition);
	// on release it snaps to the nearest detent
	let dragging = $state(false);
	let dragHeight = $state(0);
	let startY = 0;
	let startH = 0;

	const height = $derived(dragging ? dragHeight : heights[detent]);

	function down(e: PointerEvent) {
		startY = e.clientY;
		startH = heights[detent];
		dragHeight = startH;
		dragging = true;
		(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
	}
	function move(e: PointerEvent) {
		if (!dragging) return;
		dragHeight = Math.max(heights.peek, Math.min(heights.full, startH + (startY - e.clientY)));
	}
	function up(e: PointerEvent) {
		if (!dragging) return;
		dragging = false;
		if (Math.abs(e.clientY - startY) < 6) {
			// a tap on the handle, not a drag: toggle between resting states
			detent = detent === 'peek' ? 'half' : 'peek';
			return;
		}
		const opts: Detent[] = ['peek', 'half', 'full'];
		detent = opts.reduce((a, b) =>
			Math.abs(heights[b] - dragHeight) < Math.abs(heights[a] - dragHeight) ? b : a
		);
	}
</script>

<svelte:window bind:innerHeight={vh} />

<div class="sheet" class:dragging style:height="{height}px">
	<!-- svelte-ignore a11y_no_static_element_interactions — drag surface; tabs remain keyboard-reachable -->
	<div
		class="grab"
		onpointerdown={down}
		onpointermove={move}
		onpointerup={up}
		onpointercancel={up}
	>
		<div class="grip"></div>
	</div>
	{@render header()}
	<div class="body">
		{@render children()}
	</div>
</div>

<style>
	.sheet {
		position: fixed;
		left: 0;
		right: 0;
		bottom: 0;
		z-index: 50;
		display: flex;
		flex-direction: column;
		background: var(--bg-panel);
		border-top: 1px solid var(--border);
		border-radius: 12px 12px 0 0;
		box-shadow: 0 -4px 16px rgba(0, 0, 0, 0.3);
		transition: height 0.22s ease;
	}
	.sheet.dragging {
		transition: none;
	}
	.grab {
		touch-action: none; /* the drag owns vertical gestures here */
		cursor: grab;
		padding: 8px 0 4px;
		flex-shrink: 0;
	}
	.grip {
		width: 40px;
		height: 4px;
		border-radius: 2px;
		background: var(--border);
		margin: 0 auto;
	}
	.body {
		flex: 1;
		min-height: 0;
		overflow-y: auto;
		-webkit-overflow-scrolling: touch;
		padding: 8px 10px calc(10px + env(safe-area-inset-bottom));
		display: flex;
		flex-direction: column;
		gap: 10px;
	}
</style>
