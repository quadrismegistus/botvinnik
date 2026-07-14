<script lang="ts">
	// Deterministic generative avatar: the mark encodes the bot's MECHANISM
	// rather than pretending to be a person. Squares (shaped) get a blocky
	// grid — an engine with induced blind spots; Maias get concentric rings —
	// distilled from millions of human games; Fish get a cold shard.
	import type { BotPersona } from '$lib/bots';

	interface Props {
		persona: BotPersona;
		size?: number;
	}
	let { persona, size = 32 }: Props = $props();

	// small deterministic hash of the id → stable visual identity
	function hash(s: string): number {
		let h = 2166136261;
		for (let i = 0; i < s.length; i++) {
			h ^= s.charCodeAt(i);
			h = Math.imul(h, 16777619);
		}
		return h >>> 0;
	}

	const h = $derived(hash(persona.id));
	const hue = $derived(h % 360);
	// stronger bots get darker, more saturated marks
	const t = $derived(Math.max(0, Math.min(1, (persona.elo - 500) / 2000)));
	const fg = $derived(`hsl(${hue} ${45 + t * 30}% ${62 - t * 22}%)`);
	const bg = $derived(`hsl(${hue} 25% ${20 - t * 6}%)`);

	// square family: which of the 3×3 cells are filled (always ≥3, symmetric-ish)
	const cells = $derived.by(() => {
		const on: [number, number][] = [];
		for (let i = 0; i < 9; i++) if ((h >> i) & 1) on.push([i % 3, Math.floor(i / 3)]);
		return on.length >= 3 ? on : [[0, 0], [1, 1], [2, 2]];
	});
</script>

<svg
	width={size}
	height={size}
	viewBox="0 0 24 24"
	role="img"
	aria-label={persona.name}
	style="border-radius: 5px; background: {bg}; flex: none"
>
	{#if persona.family === 'square'}
		{#each cells as [x, y] (`${x}-${y}`)}
			<rect x={4 + x * 6} y={4 + y * 6} width="4.6" height="4.6" rx="0.8" fill={fg} />
		{/each}
	{:else if persona.family === 'maia'}
		<circle cx="12" cy="12" r="8" fill="none" stroke={fg} stroke-width="1.6" />
		<circle cx="12" cy="12" r="4.5" fill="none" stroke={fg} stroke-width="1.4" opacity="0.75" />
		<circle cx={12 + ((h >> 3) % 3) - 1} cy={12 + ((h >> 5) % 3) - 1} r="1.8" fill={fg} />
	{:else}
		<polygon points="12,3 20,12 12,21 4,12" fill="none" stroke={fg} stroke-width="1.6" />
		<polygon points="12,7.5 16.2,12 12,16.5 7.8,12" fill={fg} opacity="0.85" />
	{/if}
</svg>
