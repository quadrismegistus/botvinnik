<script lang="ts">
	import type { MoveLabel } from '$lib/engine/insights';
	import { CLASS } from '$lib/classifications';

	interface Point {
		ply: number;
		wcWhite: number;
		label?: MoveLabel;
		san?: string;
	}

	interface Props {
		points: Point[];
		currentPly?: number | null;
		onselect?: (ply: number) => void;
		height?: number;
	}

	let { points, currentPly = null, onselect, height = 96 }: Props = $props();

	const PAD_X = 0;
	let width = $state(300);
	let hoverPly: number | null = $state(null);

	// x by index (evenly spaced); y by win chance (100 = top, 0 = bottom)
	function xAt(i: number, n: number): number {
		const innerW = width - PAD_X * 2;
		return PAD_X + (n <= 1 ? innerW / 2 : (i / (n - 1)) * innerW);
	}
	function yAt(wc: number): number {
		return (1 - Math.max(0, Math.min(100, wc)) / 100) * height;
	}

	const view = $derived.by(() => {
		const n = points.length;
		const midY = yAt(50);
		const pts = points.map((p, i) => ({
			x: xAt(i, n),
			y: yAt(p.wcWhite),
			ply: p.ply,
			wc: p.wcWhite,
			label: p.label,
			san: p.san,
			moveNo: Math.ceil(p.ply / 2)
		}));
		const linePath = pts.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
		// white-advantage fill: everything below the line down to the baseline —
		// when White is winning the light area is tall, exactly like chess.com
		const areaPath =
			pts.length > 0
				? `${linePath} L ${pts[pts.length - 1].x} ${height} L ${pts[0].x} ${height} Z`
				: '';
		// dots only for moves that carry signal (blunders, brilliancies, …)
		const dots = pts.filter((p) => p.label && CLASS[p.label].graphed);
		const marker = currentPly != null ? (pts.find((p) => p.ply === currentPly) ?? null) : null;
		const hover = hoverPly != null ? (pts.find((p) => p.ply === hoverPly) ?? null) : null;
		return { pts, midY, linePath, areaPath, dots, marker, hover };
	});

	function plyAtX(clientX: number, el: SVGElement): number {
		const rect = el.getBoundingClientRect();
		const innerW = width - PAD_X * 2;
		const rel = clientX - rect.left - PAD_X;
		const frac = innerW > 0 ? rel / innerW : 0;
		const i = Math.max(0, Math.min(points.length - 1, Math.round(frac * (points.length - 1))));
		return points[i].ply;
	}

	function handleClick(e: MouseEvent) {
		if (!onselect || points.length === 0) return;
		onselect(plyAtX(e.clientX, e.currentTarget as SVGElement));
	}
	function handleMove(e: MouseEvent) {
		if (points.length === 0) return;
		hoverPly = plyAtX(e.clientX, e.currentTarget as SVGElement);
	}

	// tooltip x, clamped so it stays inside the chart
	const tipX = $derived(
		view.hover ? Math.max(4, Math.min(width - 116, view.hover.x - 58)) : 0
	);
</script>

<div class="win-chance-chart" bind:clientWidth={width}>
	{#if points.length < 2}
		<div class="empty">Play a few moves to see the chart.</div>
	{:else}
		<div class="frame" style:height="{height}px">
			<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions, a11y_no_noninteractive_element_interactions -->
			<svg
				{width}
				{height}
				role="img"
				aria-label="White win chance over the game"
				class:clickable={!!onselect}
				onclick={handleClick}
				onmousemove={handleMove}
				onmouseleave={() => (hoverPly = null)}
			>
				<rect x="0" y="0" {width} {height} class="bg" />
				<path d={view.areaPath} class="area" />
				<line x1="0" y1={view.midY} x2={width} y2={view.midY} class="midline" />
				<path d={view.linePath} class="line" fill="none" />

				{#if view.marker}
					<line x1={view.marker.x} y1="0" x2={view.marker.x} y2={height} class="cursor" />
				{/if}
				{#if view.hover && view.hover.ply !== view.marker?.ply}
					<line x1={view.hover.x} y1="0" x2={view.hover.x} y2={height} class="hoverline" />
				{/if}

				{#each view.dots as d (d.ply)}
					<circle cx={d.x} cy={d.y} r="4" class="dot" style:fill={CLASS[d.label!].color} />
				{/each}
				{#if view.marker}
					<circle cx={view.marker.x} cy={view.marker.y} r="3.5" class="marker" />
				{/if}
			</svg>

			{#if view.hover}
				<div class="tip" style:left="{tipX}px">
					<strong>{view.hover.moveNo}.{view.hover.san ? ` ${view.hover.san}` : ''}</strong>
					<span>{Math.round(view.hover.wc)}% White</span>
					{#if view.hover.label && CLASS[view.hover.label].graphed}
						<span class="tip-label" style:color={CLASS[view.hover.label].color}>
							{CLASS[view.hover.label].glyph} {view.hover.label}
						</span>
					{/if}
				</div>
			{/if}
		</div>
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
	.frame {
		position: relative;
		border-radius: 6px;
		overflow: hidden;
	}
	svg {
		display: block;
	}
	svg.clickable {
		cursor: pointer;
	}
	.bg {
		fill: #4a4844;
	}
	/* the white-advantage region */
	.area {
		fill: #f5f4f0;
	}
	.midline {
		stroke: rgba(255, 255, 255, 0.18);
		stroke-width: 1;
	}
	.line {
		stroke: rgba(0, 0, 0, 0.35);
		stroke-width: 1.5;
	}
	.cursor {
		stroke: #f7c631;
		stroke-width: 2;
	}
	.hoverline {
		stroke: rgba(255, 255, 255, 0.3);
		stroke-width: 1;
	}
	.dot {
		stroke: #fff;
		stroke-width: 1.5;
	}
	.marker {
		fill: #f7c631;
		stroke: #4a4844;
		stroke-width: 1.5;
	}
	.tip {
		position: absolute;
		top: 4px;
		width: 116px;
		background: var(--bg-panel);
		border: 1px solid var(--border);
		border-radius: 4px;
		padding: 3px 6px;
		font-size: 11px;
		color: var(--text-primary);
		display: flex;
		flex-direction: column;
		gap: 1px;
		pointer-events: none;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
	}
	.tip span {
		color: var(--text-secondary);
	}
	.tip-label {
		font-weight: 600;
	}
</style>
