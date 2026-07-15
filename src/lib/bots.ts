// The bot roster: one named persona per 100 ELO per engine family, replacing
// the anonymous slider as the primary way to pick an opponent.
//
// DISPLAY SCALE: lichess-rapid-equivalent. The app's internal WASM-numeric
// scale reads ~+240 hot vs lichess rapid (bridge: the @maia1/5/9 lichess bots
// have real played-games ratings 1572/1643/1701, and we measured the same nets
// on our scale — see memory/docs bot-weakening). Display = internal − 240.
// The offset is pinned by three anchors bunched at 1570-1700; below that it's
// an extrapolation until the player's own games anchor the bottom.
//
// Families (each bound to a different move-picking mechanism):
//  - square: shapedBotMove — sound play with human-shaped tactical blindness
//    (misses critical moves stickily, mushy quiet play). Measured curve in
//    bot.ts SHAPED_KNOTS_WASM; the persona stores the label that MEASURES at
//    its display strength.
//  - maia: Maia-1 human-imitation nets. All bands play club strength; the
//    three personas carry the REAL lichess rapid ratings of @maia1/5/9.
//  - fish: the numeric slider recipe (Stockfish, strength-limited) for the
//    top of the ladder, where its play is near-best and honest.

import { shapedLabelFor, shapedParams } from './bot';
import type { RetroSpec } from './engine/retro';

/** WASM-numeric scale ≈ lichess-rapid + 240 (maia1 bridge, club-range anchors). */
export const SCALE_OFFSET = 240;

export type BotFamily = 'square' | 'maia' | 'fish' | 'retro';

export interface BotPersona {
	id: string; // stable key: persisted in settings and stored games
	name: string;
	elo: number; // display scale (lichess-rapid-equivalent)
	family: BotFamily;
	blurb: string;
	/** square: label passed to shapedBotMove/shapedSearchDepth */
	shapedLabel?: number;
	/** maia: net band (1100..1900) */
	maiaBand?: number;
	/** fish: elo on the app's internal WASM scale (drives the numeric recipe) */
	numericElo?: number;
	/** retro: historical engine + ply (morlock re-implementations, wasm worker) */
	retro?: RetroSpec;
}

function square(displayElo: number): BotPersona {
	const label = shapedLabelFor(displayElo + SCALE_OFFSET);
	const missPct = Math.round(shapedParams(label).missProb * 100);
	return {
		id: `square-${displayElo}`,
		name: `Square ${displayElo}`,
		elo: displayElo,
		family: 'square',
		blurb: `Plays sound chess but misses ~${missPct}% of tactical moments — and stays blind to what it hasn't seen.`,
		shapedLabel: label
	};
}

function maia(displayElo: number, band: number, roman: string): BotPersona {
	return {
		id: `maia-${band}`,
		name: `Maia ${roman}`,
		elo: displayElo,
		family: 'maia',
		blurb: `A neural net trained to move like real ~${displayElo}-rated players — human habits, human mistakes.`,
		maiaBand: band
	};
}

function fish(displayElo: number): BotPersona {
	return {
		id: `fish-${displayElo}`,
		name: `Fish ${displayElo}`,
		elo: displayElo,
		family: 'fish',
		blurb: 'Stockfish with the strength limiter on — cold, accurate, occasionally merciful.',
		numericElo: displayElo + SCALE_OFFSET
	};
}

// Historical engines (morlock re-implementations, wasm). Display elo = the
// morlock lichess bots' REAL human-pool rapid ratings at the same config
// (bernstein-2ply 1198 over 15k games, sargon-1ply 1228 over 48k,
// turochamp-1ply ~1300) — the best-anchored numbers on the whole roster.
function retro(
	displayElo: number,
	engine: RetroSpec['engine'],
	ply: number,
	name: string,
	blurb: string
): BotPersona {
	return { id: `retro-${engine}-${ply}`, name, elo: displayElo, family: 'retro', blurb, retro: { engine, ply } };
}

const RETROS: BotPersona[] = [
	retro(
		1200,
		'bernstein',
		2,
		'Bernstein 1957',
		'The first complete chess program (IBM 704, 8 minutes a move). Considers only 7 "plausible moves" — beat it and you beat the dawn of computing.'
	),
	retro(
		1230,
		'sargon',
		1,
		'Sargon 1978',
		"Dan and Kathe Spracklen's Z80 classic that launched home-computer chess, at its easiest setting: one ply plus exchange sense."
	),
	retro(
		1300,
		'turochamp',
		1,
		'Turochamp 1948',
		"Alan Turing and David Champernowne's paper machine — written before computers existed to run it. Turing executed it by hand, one move per half hour."
	)
];

// 12 Squares (600-1700) + 3 Maias (real @maia lichess ratings) + 3 retro
// engines (real morlock-bot lichess ratings) + 8 Fish (1800-2500; internal
// 2040-2740, inside the WASM honest ceiling 2800) = 26.
export const PERSONAS: BotPersona[] = [
	...[600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700].map(square),
	...RETROS,
	maia(1570, 1100, 'I'),
	maia(1640, 1500, 'V'),
	maia(1700, 1900, 'IX'),
	...[1800, 1900, 2000, 2100, 2200, 2300, 2400, 2500].map(fish)
].sort((a, b) => a.elo - b.elo || a.name.localeCompare(b.name));

const byId = new Map(PERSONAS.map((p) => [p.id, p]));

export function personaById(id: string | null | undefined): BotPersona | null {
	return (id && byId.get(id)) || null;
}

/** The persona's strength on the app's internal WASM scale (for stored games). */
export function personaInternalElo(p: BotPersona): number {
	return p.elo + SCALE_OFFSET;
}
