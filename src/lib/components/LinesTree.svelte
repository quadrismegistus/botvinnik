<script lang="ts">
	import { untrack } from 'svelte';
	import type { EngineMove } from '$lib/engine/stockfish';
	import { getSanLine } from '$lib/engine/chess';
	import { winChance } from '$lib/engine/insights';

	interface Props {
		lines: EngineMove[];
		fen: string;
		playedSans: string[];
		height?: number;
		onplay?: (uci: string) => void;
	}

	let { lines, fen, playedSans, height = 340, onplay }: Props = $props();

	type Metric = 'cp' | 'winChance' | 'pctBest' | 'confidence';
	let yMode: Metric = $state('pctBest');
	let colorMode: Metric = $state('pctBest');
	let labelMode: Metric = $state('cp');
	let topN = $state(5);
	let depthLimit = $state(12);

	const ROOT = '(root)';
	const PLY_W = 104;
	const NODE_W = 62;
	const NODE_H = 24;
	const PAD_TOP = 14;
	const PAD_BOTTOM = 20;
	const PAD_LEFT = 30;

	interface GNode {
		id: string;
		depth: number;
		san: string;
		color: 'w' | 'b';
		piece: string;
		x: number;
		y: number;
	}
	// metrics: cp in pawns from White's perspective; confidence/pctBest 0..100
	interface GLink {
		source: string;
		target: string;
		cp: number;
		confidence: number;
		pctBest: number;
		uci?: string;
		// which position (anchor node) this link was suggested from — lets us
		// replace a position's analysis wholesale instead of accumulating PV churn
		anchor: string;
	}

	// Persistent across moves — the graph accumulates everything explored this game.
	// Plain Maps (non-reactive); `version` bumps trigger redraw.
	const nodes = new Map<string, GNode>();
	const links = new Map<string, GLink>();
	let liveKeys = new Set<string>();
	let pathKeys = new Set<string>();
	let bestNodeId: string | null = null;
	let anchorId: string = ROOT;
	let lastPathLen = 0;
	let version = $state(0);

	let scroller: HTMLDivElement | null = $state(null);

	function clearGraph() {
		nodes.clear();
		links.clear();
		liveKeys = new Set();
		pathKeys = new Set();
		bestNodeId = null;
		anchorId = ROOT;
		version++;
	}

	// centipawns from the side to move's perspective (mate mapped to a huge cp)
	function stmCp(line: EngineMove): number {
		if (line.mate !== null) return line.mate > 0 ? 9999 : -9999;
		return line.score * 100;
	}

	function metricValue(l: GLink, metric: Metric): number {
		// normalized to 0..100 for positioning/coloring
		if (metric === 'cp') {
			const cp = Math.max(-10, Math.min(10, l.cp));
			return ((cp + 10) / 20) * 100;
		}
		// White's winning chance via the lichess sigmoid (l.cp is White-perspective pawns)
		if (metric === 'winChance') return winChance(l.cp, null);
		return metric === 'pctBest' ? l.pctBest : l.confidence;
	}

	function metricLabel(l: GLink, metric: Metric): string {
		if (metric === 'cp') return (l.cp >= 0 ? '+' : '') + l.cp.toFixed(1);
		return metricValue(l, metric).toFixed(0) + '%';
	}

	function metricColor(l: GLink, metric: Metric): string {
		// continuous red (0) -> yellow (50) -> green (100)
		const v = Math.max(0, Math.min(100, metricValue(l, metric)));
		return `hsl(${Math.round(1.2 * v)}, 65%, 45%)`;
	}

	const GLYPHS: Record<'w' | 'b', Record<string, string>> = {
		w: { k: '♔', q: '♕', r: '♖', b: '♗', n: '♘' },
		b: { k: '♚', q: '♛', r: '♜', b: '♝', n: '♞' }
	};

	function figurine(san: string, color: 'w' | 'b', piece: string): string {
		if (san.startsWith('O-O')) return san;
		const glyph = GLYPHS[color][piece];
		if (!glyph) return san; // pawn moves keep plain SAN
		return glyph + san.replace(/^[KQRBN]/, '');
	}

	// Nudge overlapping nodes in a column apart, keeping them inside the band.
	// If the column holds more nodes than fit, compress the gap evenly rather
	// than clamp-stacking everything at the edge.
	function separateColumn(desired: Map<string, number>, minGap: number, lo: number, hi: number) {
		const entries = [...desired.entries()].sort((a, b) => a[1] - b[1]);
		if (entries.length === 0) return;
		const gap = Math.min(minGap, entries.length > 1 ? (hi - lo) / (entries.length - 1) : minGap);
		for (let i = 1; i < entries.length; i++) {
			if (entries[i][1] - entries[i - 1][1] < gap) entries[i][1] = entries[i - 1][1] + gap;
		}
		const overflow = entries[entries.length - 1][1] - hi;
		if (overflow > 0) {
			for (const e of entries) e[1] -= overflow;
			for (let i = entries.length - 2; i >= 0; i--) {
				if (entries[i + 1][1] - entries[i][1] < gap) entries[i][1] = entries[i + 1][1] - gap;
			}
		}
		for (const [id, y] of entries) desired.set(id, Math.max(lo, Math.min(hi, y)));
	}

	function xForDepth(d: number): number {
		return PAD_LEFT + NODE_W / 2 + d * PLY_W;
	}

	function mergeAndLayout() {
		const innerLo = PAD_TOP + NODE_H / 2;
		const innerHi = height - PAD_BOTTOM - NODE_H / 2;
		const midY = (innerLo + innerHi) / 2;

		// new game -> wipe the exploration map
		if (playedSans.length === 0 && lastPathLen > 0) {
			nodes.clear();
			links.clear();
			bestNodeId = null;
		}
		lastPathLen = playedSans.length;

		if (!nodes.has(ROOT)) {
			nodes.set(ROOT, { id: ROOT, depth: 0, san: '·', color: 'w', piece: '', x: xForDepth(0), y: midY });
		}

		// played path
		pathKeys = new Set();
		let parent = ROOT;
		playedSans.forEach((san, i) => {
			const id = `${i + 1}:${san}`;
			if (!nodes.has(id)) {
				nodes.set(id, {
					id, depth: i + 1, san,
					color: i % 2 === 0 ? 'w' : 'b',
					piece: /^[KQRBN]/.test(san) ? san[0].toLowerCase() : san.startsWith('O-O') ? 'k' : 'p',
					x: xForDepth(i + 1), y: midY
				});
			}
			const key = `${parent}->${id}`;
			if (!links.has(key))
				links.set(key, { source: parent, target: id, cp: 0, confidence: 0, pctBest: 0, anchor: '(path)' });
			pathKeys.add(key);
			parent = id;
		});
		anchorId = parent;
		liveKeys = new Set(pathKeys);

		// Replace this position's previous analysis instead of accumulating PV churn,
		// and truncate past positions' lines to their first move — the alternatives
		// branching off the path stay visible, their deep continuations don't.
		for (const [key, l] of links) {
			if (pathKeys.has(key)) continue;
			if (l.anchor === anchorId || l.source !== l.anchor) links.delete(key);
		}

		// current engine lines -> confidence via softmax over side-to-move cp (τ = 100cp)
		const shown = [...lines].sort((a, b) => a.multipv - b.multipv).slice(0, topN);
		const cps = shown.map(stmCp);
		const maxCp = cps.length ? Math.max(...cps) : 0;
		const exps = cps.map((c) => Math.exp((c - maxCp) / 100));
		const denom = exps.reduce((a, b) => a + b, 0) || 1;
		const confs = exps.map((e) => (e / denom) * 100);
		const bestConf = confs.length ? Math.max(...confs) : 0;
		const whiteTurn = fen.split(' ')[1] !== 'b';
		const baseDepth = playedSans.length;

		bestNodeId = null;
		shown.forEach((line, li) => {
			const confidence = confs[li];
			const pctBest = bestConf > 0 ? (confs[li] / bestConf) * 100 : 0;
			const cpPawns = Math.max(-99, Math.min(99, (whiteTurn ? cps[li] : -cps[li]) / 100));
			const steps = getSanLine(fen, line.pv.slice(0, depthLimit));
			let par = anchorId;
			steps.forEach((st, i) => {
				const d = baseDepth + 1 + i;
				const id = `${d}:${st.san}`;
				if (!nodes.has(id)) {
					nodes.set(id, { id, depth: d, san: st.san, color: st.color, piece: st.piece, x: xForDepth(d), y: midY });
				}
				links.set(`${par}->${id}`, {
					source: par, target: id,
					cp: cpPawns, confidence, pctBest,
					uci: i === 0 ? st.uci : undefined,
					anchor: anchorId
				});
				liveKeys.add(`${par}->${id}`);
				if (i === 0 && line.multipv === 1) bestNodeId = id;
				par = id;
			});
		});

		// drop nodes no link touches anymore
		const referenced = new Set([ROOT]);
		for (const l of links.values()) {
			referenced.add(l.source);
			referenced.add(l.target);
		}
		for (const id of [...nodes.keys()]) {
			if (!referenced.has(id)) nodes.delete(id);
		}

		// vertical layout: live nodes by Y metric (max over live incoming links), others keep their spot
		const byDepth = new Map<number, Map<string, number>>();
		for (const n of nodes.values()) {
			if (n.id === ROOT) continue;
			let desired = n.y;
			let bestVal = -1;
			for (const key of liveKeys) {
				const l = links.get(key);
				if (!l || l.target !== n.id) continue;
				const v = metricValue(l, yMode);
				if (v > bestVal) bestVal = v;
			}
			if (bestVal >= 0) desired = innerLo + (innerHi - innerLo) * (1 - bestVal / 100);
			if (!byDepth.has(n.depth)) byDepth.set(n.depth, new Map());
			byDepth.get(n.depth)!.set(n.id, desired);
		}
		for (const col of byDepth.values()) separateColumn(col, NODE_H + 8, innerLo, innerHi);
		for (const n of nodes.values()) {
			if (n.id === ROOT) continue;
			n.x = xForDepth(n.depth);
			n.y = byDepth.get(n.depth)?.get(n.id) ?? n.y;
		}

		version++;
	}

	$effect(() => {
		// deps: everything that changes the graph or the layout;
		// untrack so the version++ inside doesn't retrigger this effect
		lines; fen; playedSans; topN; depthLimit; yMode; height;
		untrack(() => mergeAndLayout());
	});

	const view = $derived.by(() => {
		version;
		const ns = [...nodes.values()];
		const maxDepth = ns.reduce((m, n) => Math.max(m, n.depth), 1);
		const playableUci = new Map<string, string>();
		for (const key of liveKeys) {
			const l = links.get(key);
			// only first moves out of the current position — an already-played path
			// edge can carry a stale uci from when the engine suggested it
			if (l?.uci && l.source === anchorId) playableUci.set(l.target, l.uci);
		}
		return {
			nodes: ns,
			links: [...links.entries()].map(([key, l]) => ({
				...l,
				key,
				live: liveKeys.has(key),
				onPath: pathKeys.has(key),
				from: nodes.get(l.source),
				to: nodes.get(l.target)
			})),
			width: xForDepth(maxDepth) + NODE_W / 2 + PAD_LEFT,
			anchorId,
			bestNodeId,
			playableUci
		};
	});

	// keep the current position's column in view
	$effect(() => {
		version;
		if (!scroller) return;
		const anchor = nodes.get(anchorId);
		if (!anchor) return;
		const target = anchor.x - scroller.clientWidth * 0.25;
		if (Math.abs(scroller.scrollLeft - target) > PLY_W) {
			scroller.scrollTo({ left: Math.max(0, target), behavior: 'smooth' });
		}
	});

	function edgePath(l: { from?: GNode; to?: GNode }): string {
		if (!l.from || !l.to) return '';
		const x1 = l.from.x + NODE_W / 2;
		const y1 = l.from.y;
		const x2 = l.to.x - NODE_W / 2;
		const y2 = l.to.y;
		const mx = (x1 + x2) / 2;
		return `M ${x1} ${y1} C ${mx} ${y1}, ${mx} ${y2}, ${x2} ${y2}`;
	}

	function handleNodeClick(id: string) {
		const uci = view.playableUci.get(id);
		if (uci && onplay) onplay(uci);
	}
</script>

<div class="lines-tree">
	<div class="controls">
		<label>
			Y-axis
			<select bind:value={yMode}>
				<option value="cp">Eval (−10..+10)</option>
				<option value="winChance">Win %</option>
				<option value="pctBest">%Best</option>
				<option value="confidence">Confidence</option>
			</select>
		</label>
		<label>
			Color
			<select bind:value={colorMode}>
				<option value="cp">Eval</option>
				<option value="winChance">Win %</option>
				<option value="pctBest">%Best</option>
				<option value="confidence">Confidence</option>
			</select>
		</label>
		<label>
			Label
			<select bind:value={labelMode}>
				<option value="cp">Eval</option>
				<option value="winChance">Win %</option>
				<option value="pctBest">%Best</option>
				<option value="confidence">Confidence</option>
			</select>
		</label>
		<label>
			Lines
			<input type="range" min="1" max="5" bind:value={topN} />
			<span class="val">{topN}</span>
		</label>
		<label>
			Depth
			<input type="range" min="1" max="20" bind:value={depthLimit} />
			<span class="val">{depthLimit}</span>
		</label>
		<button class="clear" onclick={clearGraph}>Clear</button>
	</div>

	<div class="scroller" bind:this={scroller} style:height="{height}px">
		<svg width={view.width} height={height}>
			{#each view.links as l (l.key)}
				<path
					d={edgePath(l)}
					fill="none"
					stroke={l.onPath ? 'var(--text-primary)' : l.live ? metricColor(l, colorMode) : 'var(--border)'}
					stroke-width={l.onPath ? 3 : l.live ? 2 : 1}
					opacity={l.onPath ? 0.9 : l.live ? 0.85 : 0.4}
				/>
			{/each}

			{#each view.links as l (l.key + ':label')}
				{#if l.live && !l.onPath && l.uci && l.from && l.to}
					<text
						class="edge-label"
						x={(l.from.x + l.to.x) / 2}
						y={(l.from.y + l.to.y) / 2 - 5}
						text-anchor="middle"
					>
						{metricLabel(l, labelMode)}
					</text>
				{/if}
			{/each}

			{#each view.nodes as n (n.id)}
				{#if n.id === ROOT}
					<circle
						cx={n.x} cy={n.y} r="7"
						class="root-node"
						class:anchor={view.anchorId === ROOT}
					/>
				{:else}
					<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
					<g
						class="node"
						class:playable={view.playableUci.has(n.id)}
						onclick={() => handleNodeClick(n.id)}
					>
						<rect
							x={n.x - NODE_W / 2}
							y={n.y - NODE_H / 2}
							width={NODE_W}
							height={NODE_H}
							rx="6"
							class="chip"
							class:best={n.id === view.bestNodeId}
							class:anchor={n.id === view.anchorId}
						/>
						<text x={n.x} y={n.y} text-anchor="middle" dominant-baseline="central" class="san {n.color === 'w' ? 'white-move' : 'black-move'}">
							{figurine(n.san, n.color, n.piece)}
						</text>
					</g>
				{/if}
			{/each}
		</svg>
	</div>
</div>

<style>
	.controls {
		display: flex;
		align-items: center;
		gap: 16px;
		flex-wrap: wrap;
		margin-bottom: 8px;
		font-size: 12px;
		color: var(--text-secondary);
	}
	.controls label {
		display: flex;
		align-items: center;
		gap: 6px;
	}
	.controls select {
		background: var(--bg-button);
		color: var(--text-primary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 2px 4px;
	}
	.controls input[type='range'] {
		width: 90px;
	}
	.val {
		min-width: 16px;
		font-variant-numeric: tabular-nums;
		color: var(--text-primary);
	}
	.clear {
		margin-left: auto;
		background: var(--bg-button);
		color: var(--text-secondary);
		border: 1px solid var(--border);
		border-radius: 4px;
		font-size: 12px;
		padding: 2px 10px;
		cursor: pointer;
	}
	.clear:hover {
		color: var(--text-primary);
	}
	.scroller {
		overflow-x: auto;
		overflow-y: hidden;
	}
	.root-node {
		fill: var(--text-secondary);
	}
	.root-node.anchor {
		fill: var(--color-win);
	}
	.chip {
		fill: var(--bg-highlight);
		stroke: var(--border);
		stroke-width: 1;
	}
	.chip.best {
		stroke: #4a9eff;
		stroke-width: 2;
	}
	.chip.anchor {
		stroke: var(--color-win);
		stroke-width: 2;
	}
	.node.playable {
		cursor: pointer;
	}
	.node.playable:hover .chip {
		fill: var(--bg-button);
	}
	.san {
		font-size: 13px;
		font-weight: 600;
		fill: var(--text-primary);
	}
	.edge-label {
		font-size: 10px;
		fill: var(--text-secondary);
	}
</style>
