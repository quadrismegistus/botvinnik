<script lang="ts">
	interface Props {
		points: { ply: number; wcWhite: number }[];
		currentPly?: number | null;
		onselect?: (ply: number) => void;
		height?: number;
	}

	let { points, currentPly = null, onselect, height = 80 }: Props = $props();

	const PAD_X = 4;
	const PAD_Y = 6;

	let width = $state(300);

	// x by index (evenly spaced), y by win chance (100 at top, 0 at bottom)
	function xAt(i: number, n: number): number {
		const innerW = width - PAD_X * 2;
		return PAD_X + (n <= 1 ? innerW / 2 : (i / (n - 1)) * innerW);
	}
	function yAt(wc: number): number {
		const innerH = height - PAD_Y * 2;
		return PAD_Y + (1 - Math.max(0, Math.min(100, wc)) / 100) * innerH;
	}

	const view = $derived.by(() => {
		const n = points.length;
		const midY = yAt(50);
		const pts = points.map((p, i) => ({ x: xAt(i, n), y: yAt(p.wcWhite), ply: p.ply }));
		const linePath = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
		// fill the band between the line and the 50% midline
		const areaPath =
			pts.length > 0
				? `${linePath} L ${pts[pts.length - 1].x} ${midY} L ${pts[0].x} ${midY} Z`
				: '';
		const marker = currentPly != null ? (pts.find((p) => p.ply === currentPly) ?? null) : null;
		return { pts, midY, linePath, areaPath, marker };
	});

	function handleClick(e: MouseEvent) {
		if (!onselect || points.length === 0) return;
		const rect = (e.currentTarget as SVGElement).getBoundingClientRect();
		const innerW = width - PAD_X * 2;
		const rel = e.clientX - rect.left - PAD_X;
		const frac = innerW > 0 ? rel / innerW : 0;
		const i = Math.max(0, Math.min(points.length - 1, Math.round(frac * (points.length - 1))));
		onselect(points[i].ply);
	}
</script>

<div class="win-chance-chart" bind:clientWidth={width}>
	{#if points.length < 2}
		<div class="empty">Play a few moves to see the chart.</div>
	{:else}
		<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions, a11y_no_noninteractive_element_interactions -->
		<svg
			{width}
			{height}
			role="img"
			aria-label="White win chance over the game"
			class:clickable={!!onselect}
			onclick={handleClick}
		>
			<path d={view.areaPath} class="area" />
			<line x1={PAD_X} y1={view.midY} x2={width - PAD_X} y2={view.midY} class="midline" />
			<path d={view.linePath} class="line" fill="none" />
			{#if view.marker}
				<circle cx={view.marker.x} cy={view.marker.y} r="3.5" class="marker" />
			{/if}
		</svg>
	{/if}
</div>

<style>
	.win-chance-chart {
		width: 100%;
	}
	.empty {
		font-size: 13px;
		color: var(--text-secondary);
		padding: 8px 0;
	}
	svg.clickable {
		cursor: pointer;
	}
	.area {
		fill: var(--color-win);
		opacity: 0.12;
	}
	.midline {
		stroke: var(--border);
		stroke-width: 1;
		stroke-dasharray: 3 3;
	}
	.line {
		stroke: var(--text-primary);
		stroke-width: 1.5;
	}
	.marker {
		fill: var(--color-win);
		stroke: var(--bg-panel);
		stroke-width: 1;
	}
</style>
