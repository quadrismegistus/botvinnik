// App-internal player rating, fit from stored results against roster bots of
// known strength. The BOTS' ratings are fixed (they're calibrated measurements
// — letting game results move them would corrupt the ruler); only the player
// floats. Maximum-likelihood over the logistic Elo model, all games weighted
// equally.
//
// Only RATED persona games count. Rated is a mode the player starts a game in
// (blind, no hint overlays, and a takeback still costs the game) rather than
// something read back off the settings afterwards — the argument is beside the
// exclusion below.
//
// Roster personas AND downloaded/custom engines count; only LEGACY slider games
// (no persona id) are excluded — they were played against the old softmax
// sampler, whose label-vs-strength mapping is broken against coherent opponents
// (the founding result of the shaped-bot work), so those results don't sit on
// the ruler. A downloaded engine's strength is its stated label for now; the
// gym plugs a measured correction into `customEngineElo` later (an opt-in seam).
//
// Everything here is on the DISPLAY scale (lichess-rapid-equivalent).

import type { StoredGame } from './gameStore';
import { personaById, SCALE_OFFSET } from './bots';

export interface PlayerEloEstimate {
	elo: number;
	/** standard error from the Fisher information (huge until ~8-10 games) */
	se: number;
	/** decided persona games in the fit */
	games: number;
}

interface Outcome {
	opp: number; // opponent display elo
	score: number; // 1 / 0.5 / 0 for the player
}

function playerScore(g: StoredGame): number | null {
	// botColor is the side the human did NOT play
	if (g.result === '1/2-1/2') return 0.5;
	if (g.result === '1-0') return g.botColor === 'b' ? 1 : 0;
	if (g.result === '0-1') return g.botColor === 'w' ? 1 : 0;
	return null; // '*' abandoned
}

function expected(me: number, opp: number): number {
	return 1 / (1 + Math.pow(10, (opp - me) / 400));
}

/** GYM-OVERRIDE SEAM. Map a downloaded engine's stated label to its measured
 * display-scale strength. Identity today — we trust the catalog/UCI label — but
 * the gym plugs its per-engine measured curve in HERE, applied at fit time so a
 * later calibration retroactively corrects every stored game without rewriting
 * the archive. Keyed by the engine slug in the persona id
 * (`custom-velvet~mcts` -> `velvet`). */
function customEngineElo(_slug: string, statedLabel: number): number {
	// e.g. return GYM_ELO[_slug]?.(statedLabel) ?? statedLabel;
	return statedLabel;
}

/** The opponent's display-scale elo for the fit, or null to leave the game off
 * the ruler. A built-in roster bot reads its calibrated elo from bots.ts; a
 * downloaded/custom engine (a persona id bots.ts does not know) reads the label
 * recorded on the game — botElo is stored on the internal scale — and runs it
 * through the gym seam. Legacy slider games carry no persona id and stay off. */
function opponentElo(g: StoredGame): number | null {
	const p = personaById(g.botPersona);
	if (p) return p.elo;
	// A downloaded engine's id is `custom-<slug>[~style]` and is deliberately not
	// in bots.ts. Anything else that fails to resolve — a legacy slider game (no
	// id) or a stale/renamed roster id — stays off the ruler.
	if (!g.botPersona?.startsWith('custom-') || g.botElo == null) return null;
	const slug = g.botPersona.slice('custom-'.length).split('~')[0];
	return customEngineElo(slug, g.botElo - SCALE_OFFSET);
}

export function estimatePlayerElo(gamesList: StoredGame[]): PlayerEloEstimate | null {
	const outcomes: Outcome[] = [];
	for (const g of gamesList) {
		const opp = opponentElo(g);
		if (opp == null) continue; // legacy slider game, or no opponent on record
		if (g.botFallback) continue; // opponent wasn't really the persona — off the ruler
		if ((g.botUndos ?? 0) > 0) continue; // takebacks = assisted result — off the ruler
		// Two bots playing each other. playerColor falls back to White when both
		// sides carry a persona, so such a game archives looking like a human
		// White game and was being scored as one. #144 stopped it earning a crown
		// and not this; the exclusion belongs here, beside the other two, or every
		// future consumer of the archive repeats the mistake.
		if (g.botBothSides) continue;
		// Rated play is a MODE the player opted into, not a property inferred
		// from the four help switches (#168).
		//
		// Inference was the obvious design and it is unreachable. Arrows,
		// threats and control all default ON and blind defaults OFF
		// (settings_store.dart), so "no help was on the board" rates no game a
		// default install ever plays; and no archived game carries the intent
		// either, so it would rate nothing historical. A field is also honest
		// about what it records — the player knew they were on the record —
		// and survives a later change to what "assisted" means, where
		// inference re-derives that decision from whatever the switches happen
		// to mean at the time of the read.
		//
		// Nothing archived before #168 rates. That discontinuity is deliberate
		// and sanctioned; real rated games accumulate from here.
		if (g.rated !== true) continue;
		// The mode is a starting state, not a promise: all four switches stay
		// live during the game, and botHintsUsed is sampled at every human move
		// (GameController._hintsOnBoard). Turn arrows back on for one move in a
		// rated game and this drops it — `rated` is what the player meant, this
		// is what they did. Written since #144 and, until #168, read by nothing:
		// arrows, threat rings and square control excluded no game at all.
		//
		// Takebacks need nothing extra here — `botUndos > 0` above already
		// takes a rewound rated game off the ruler.
		if (g.botHintsUsed) continue;
		const score = playerScore(g);
		if (score === null) continue;
		outcomes.push({ opp, score });
	}
	if (outcomes.length === 0) return null;

	// Regularize with one virtual DRAW against the mean opponent (the standard
	// performance-rating trick): keeps the MLE finite on an all-win or all-loss
	// record without meaningfully biasing a mixed one.
	const meanOpp = outcomes.reduce((a, o) => a + o.opp, 0) / outcomes.length;
	const fit = [...outcomes, { opp: meanOpp, score: 0.5 }];

	// 1-D MLE by grid search — trivially cheap at this scale and robust
	let best = meanOpp;
	let bestLL = -Infinity;
	for (let e = 200; e <= 2900; e += 5) {
		let ll = 0;
		for (const o of fit) {
			const p = expected(e, o.opp);
			ll += o.score * Math.log(p) + (1 - o.score) * Math.log(1 - p);
		}
		if (ll > bestLL) {
			bestLL = ll;
			best = e;
		}
	}

	// Fisher information of the logistic model at the MLE (virtual draw included
	// — it genuinely contributes information under this model)
	const k = Math.LN10 / 400;
	let info = 0;
	for (const o of fit) {
		const p = expected(best, o.opp);
		info += k * k * p * (1 - p);
	}
	const se = info > 0 ? Math.round(1 / Math.sqrt(info)) : Infinity;

	return { elo: best, se, games: outcomes.length };
}
