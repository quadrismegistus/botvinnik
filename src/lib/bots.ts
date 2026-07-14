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

/** WASM-numeric scale ≈ lichess-rapid + 240 (maia1 bridge, club-range anchors). */
export const SCALE_OFFSET = 240;

export type BotFamily = 'square' | 'maia' | 'fish';

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

// 12 Squares (600-1700) + 3 Maias (real @maia lichess ratings) + 8 Fish
// (1800-2500; internal 2040-2740, inside the WASM honest ceiling 2800) = 23.
export const PERSONAS: BotPersona[] = [
	...[600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700].map(square),
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
