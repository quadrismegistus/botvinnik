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
import type { RetroSpec } from './engine/types';

/** WASM-numeric scale ≈ lichess-rapid + 240 (maia1 bridge, club-range anchors). */
export const SCALE_OFFSET = 240;

export type BotFamily =
	| 'squarefish'
	| 'maia'
	| 'stockfish'
	| 'retro'
	| 'dala'
	| 'horizon'
	| 'garbo';

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
	/** maia: policy-sampling temperature (default argmax = consensus move) */
	maiaTemp?: number;
	/** fish: elo on the app's internal WASM scale (drives the numeric recipe) */
	numericElo?: number;
	/** retro: historical engine + ply (morlock re-implementations, wasm worker) */
	retro?: RetroSpec;
	/** dala: imitation-net bracket (700/900/1300).
	 *
	 * NOT IMPLEMENTED ANYWHERE. The only build that could run these was the
	 * Tauri desktop shell, retired 2026-07-20; no current platform offers the
	 * family and no weights are fetched. They also carry NO LICENCE — the
	 * upstream repo states none — so implementing this needs the author's
	 * permission first, not just an lc0 sidecar (#45, #47). */
	dalaBand?: number;
	/** horizon: js-chess-engine difficulty level (1-2 shipped) */
	jsceLevel?: number;
	/** garbo: Garbochess-JS movetime in ms */
	garboMs?: number;
	/** persona needs the native shell (lc0 sidecar); hidden in the web roster */
	nativeOnly?: boolean;
}

function square(displayElo: number): BotPersona {
	const label = shapedLabelFor(displayElo + SCALE_OFFSET);
	const missPct = Math.round(shapedParams(label).missProb * 100);
	return {
		id: `squarefish-${displayElo}`,
		name: `Squarefish ${displayElo}`,
		elo: displayElo,
		family: 'squarefish',
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

// Sampled Maias: the same nets, but SAMPLING the policy distribution instead
// of playing its argmax. Argmax plays the training population's consensus
// move every time — far stronger than any individual in it (the Humaia
// insight; measured −260 Elo in a same-net control pair). Display elos are
// ESTIMATES (the argmax bots' lichess ratings − 260), refined by play — the
// only roster numbers not directly measured, and labeled so in the blurb.
function maiaSampled(displayElo: number, band: number, roman: string): BotPersona {
	return {
		id: `maia-s-${band}`,
		name: `Maia ${roman} (sampled)`,
		elo: displayElo,
		family: 'maia',
		blurb: `The same net as Maia ${roman}, but drawing from its whole move distribution instead of the consensus move — weaker, moodier, more like one player than an average. Rating estimated.`,
		maiaBand: band,
		maiaTemp: 1
	};
}

function fish(displayElo: number): BotPersona {
	return {
		id: `stockfish-${displayElo}`,
		name: `Stockfish ${displayElo}`,
		elo: displayElo,
		family: 'stockfish',
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

// Dala (desktop only): BT4 imitation nets trained exclusively on human games
// in each bracket (hrschubert/dala-training), played by policy sampling — the
// display elos are the dala lichess bots' REAL human-pool rapid ratings.
// Native-gated: they run on an lc0 sidecar; weights download on first use.
function dala(displayElo: number, band: number): BotPersona {
	return {
		id: `dala-${band}`,
		name: `Dala ${band}`,
		elo: displayElo,
		family: 'dala',
		blurb: `A neural net trained only on games by ~${band}-rated humans, playing their moves — habits, hopes, blind spots and all. (Downloads its brain on first use.)`,
		dalaBand: band,
		nativeOnly: true
	};
}

// The Horizon personas: js-chess-engine at levels 1-2 — no quiescence, so it
// starts exchanges it can't see the end of (the horizon effect). Gym-measured
// 535/860 lichess-equiv vs honest rulers; search-family, so no pool gap (the
// retro finding). Extends the roster BELOW the Squares' floor.
function horizon(displayElo: number, level: number): BotPersona {
	return {
		id: `horizon-${level}`,
		name: `Horizon ${displayElo}`,
		elo: displayElo,
		family: 'horizon',
		blurb:
			level === 1
				? 'A tiny JavaScript engine that cannot see past its own captures — it takes, you take back, it is surprised. The weakest honest engine we could find.'
				: 'One ply deeper than its little sibling: still starts exchanges it cannot finish, but needs slightly more convincing.',
		jsceLevel: level
	};
}

// Garbochess-JS (2011, Gary Linscott — later of fishtest and Leela fame):
// hand-written JS, Fruit-era eval, anchored by @GarboBot's ~2000 lichess
// rating over 90k+ human games. Same strength slot as Fish 2000, entirely
// different mind: sharp tactics, pre-neural positional judgment.
const GARBO: BotPersona = {
	id: 'garbo-2000',
	name: 'Garbo 2011',
	elo: 2020,
	family: 'garbo',
	blurb:
		"Gary Linscott's 2011 JavaScript engine, verbatim — its author went on to build the tools modern chess engines are made with. Plays like 2011: sharp, material-minded, honestly pre-neural.",
	garboMs: 1000
};

// 12 Squares (600-1700) + 3 Maias (real @maia lichess ratings) + 3 retro
// engines (real morlock-bot lichess ratings) + 3 Dalas (desktop only, real
// dala-bot lichess ratings) + 8 Fish (1800-2500; internal 2040-2740, inside
// the WASM honest ceiling 2800) = 29 (26 on the web).
export const PERSONAS: BotPersona[] = [
	horizon(550, 1),
	horizon(860, 2),
	...[600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700].map(square),
	...RETROS,
	dala(911, 700),
	dala(1095, 900),
	dala(1315, 1300),
	maiaSampled(1310, 1100, 'I'),
	maiaSampled(1380, 1500, 'V'),
	maiaSampled(1440, 1900, 'IX'),
	maia(1570, 1100, 'I'),
	maia(1640, 1500, 'V'),
	maia(1700, 1900, 'IX'),
	GARBO,
	...[1800, 1900, 2000, 2100, 2200, 2300, 2400, 2500].map(fish)
].sort((a, b) => a.elo - b.elo || a.name.localeCompare(b.name));

/** The roster available in this runtime (dala needs the native lc0 sidecar). */
export function availablePersonas(native: boolean): BotPersona[] {
	return native ? PERSONAS : PERSONAS.filter((p) => !p.nativeOnly);
}

const byId = new Map(PERSONAS.map((p) => [p.id, p]));

/**
 * Ids renamed 2026-07-21: `fish-*` became `stockfish-*` and `square-*` became
 * `squarefish-*`.
 *
 * Persona ids are PERSISTED — every archived game carries one as
 * `StoredGame.botPersona`, and the player's chosen opponents are stored the
 * same way. `personaById` is the single door both go through, so mapping here
 * is the whole migration.
 *
 * `estimatePlayerElo` is why this matters rather than being cosmetic: it does
 * `if (!p) continue`, so an id that stops resolving does not error, it silently
 * drops that game from the rating fit. Renaming without this would have quietly
 * erased every Squarefish and Stockfish game ever played.
 *
 * Never delete an entry. A game archived under an old id keeps pointing here
 * for as long as the archive exists.
 */
function renamedId(id: string): string | null {
	// `square-` cannot match `squarefish-*`: the seventh character is `f`, not `-`
	if (id.startsWith('fish-')) return `stockfish-${id.slice(5)}`;
	if (id.startsWith('square-')) return `squarefish-${id.slice(7)}`;
	return null;
}

export function personaById(id: string | null | undefined): BotPersona | null {
	if (!id) return null;
	const direct = byId.get(id);
	if (direct) return direct;
	const renamed = renamedId(id);
	return (renamed && byId.get(renamed)) || null;
}

/** The persona's strength on the app's internal WASM scale (for stored games). */
export function personaInternalElo(p: BotPersona): number {
	return p.elo + SCALE_OFFSET;
}
