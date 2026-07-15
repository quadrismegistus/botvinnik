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
	{:else if persona.family === 'dala'}
		<!-- woven net: trained threads of human games -->
		<path d="M5 9 Q12 5 19 9 M5 12 Q12 8 19 12 M5 15 Q12 11 19 15" fill="none" stroke={fg} stroke-width="1.3" opacity="0.8" />
		<path d="M8 6 Q12 12 8 18 M12 5.5 Q16 12 12 18.5 M16 6 Q20 12 16 18" fill="none" stroke={fg} stroke-width="1.1" opacity="0.55" />
		<circle cx={9 + ((h >> 2) % 7)} cy={9 + ((h >> 6) % 6)} r="1.7" fill={fg} />
	{:else if persona.family === 'horizon'}
		<!-- a sun sinking below the horizon: it cannot see past the line -->
		<line x1="4" y1="14" x2="20" y2="14" stroke={fg} stroke-width="1.5" />
		<path d="M 7.5 14 A 4.5 4.5 0 0 1 16.5 14 Z" fill={fg} opacity="0.9" />
		<line x1="12" y1="6" x2="12" y2="8" stroke={fg} stroke-width="1.2" opacity="0.6" />
		<line x1="6.5" y1="8.5" x2="8" y2="10" stroke={fg} stroke-width="1.2" opacity="0.6" />
		<line x1="17.5" y1="8.5" x2="16" y2="10" stroke={fg} stroke-width="1.2" opacity="0.6" />
	{:else if persona.family === 'garbo'}
		<!-- a 2011 browser window: the engine that lived in one -->
		<rect x="4" y="5" width="16" height="14" rx="1.5" fill="none" stroke={fg} stroke-width="1.4" />
		<line x1="4" y1="9" x2="20" y2="9" stroke={fg} stroke-width="1.2" opacity="0.7" />
		<circle cx="6.5" cy="7" r="0.9" fill={fg} />
		<circle cx="9.3" cy="7" r="0.9" fill={fg} opacity="0.7" />
		<path d="M8 12 l3 2.5 -3 2.5 M13 17 h4" fill="none" stroke={fg} stroke-width="1.3" />
	{:else if persona.family === 'retro'}
		<!-- punch card: the medium these minds originally lived on -->
		<rect x="4" y="5" width="16" height="14" rx="1.2" fill="none" stroke={fg} stroke-width="1.4" />
		<path d="M4 5 h4 l2 2.5 h10" fill="none" stroke={fg} stroke-width="1.1" opacity="0.7" />
		{#each [0, 1, 2, 3, 4, 5, 6, 7] as i (i)}
			{#if (h >> i) & 1}
				<rect x={6.2 + (i % 4) * 3.4} y={10.5 + Math.floor(i / 4) * 3.6} width="1.8" height="2.4" rx="0.4" fill={fg} />
			{/if}
		{/each}
	{:else}
		<polygon points="12,3 20,12 12,21 4,12" fill="none" stroke={fg} stroke-width="1.6" />
		<polygon points="12,7.5 16.2,12 12,16.5 7.8,12" fill={fg} opacity="0.85" />
	{/if}
</svg>
