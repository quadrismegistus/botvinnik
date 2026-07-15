// App-internal player rating, fit from stored results against roster bots of
// known strength. The BOTS' ratings are fixed (they're calibrated measurements
// — letting game results move them would corrupt the ruler); only the player
// floats. Maximum-likelihood over the logistic Elo model, all games weighted
// equally.
//
// Only PERSONA games count: legacy slider games were played against the old
// softmax sampler, whose label-vs-strength mapping is broken against coherent
// opponents (the founding result of the shaped-bot work) — those results
// don't sit on the ruler.
//
// Everything here is on the DISPLAY scale (lichess-rapid-equivalent).

import type { StoredGame } from './gameStore';
import { personaById } from './bots';

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

export function estimatePlayerElo(gamesList: StoredGame[]): PlayerEloEstimate | null {
	const outcomes: Outcome[] = [];
	for (const g of gamesList) {
		const p = personaById(g.botPersona);
		if (!p) continue;
		if (g.botFallback) continue; // opponent wasn't really the persona — off the ruler
		const score = playerScore(g);
		if (score === null) continue;
		outcomes.push({ opp: p.elo, score });
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
