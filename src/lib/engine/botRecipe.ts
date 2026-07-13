// The ELO → engine-weakening recipe, shared VERBATIM by the live app
// (analyzeBotMove in stockfish.ts) and the offline calibration harness
// (scripts/calibrate-bots.mts). If the two drift, the harness measures
// fiction — change bands ONLY here.
//
// Three bands:
//  - ≥1320: the engine's calibrated UCI_Elo at a fixed movetime.
//  - 800–1319: low Skill Level + shallow depth (standard weak-bot recipe).
//  - <800: even depth-1 NNUE won't hang pieces, so instead evaluate (nearly)
//    every legal move at depth 1–2 via wide MultiPV and let the caller sample
//    with a very flat softmax (selectBotMove) — true beginner play.

export interface BotRecipe {
	options: [string, string][];
	go: string;
	/** wide-MultiPV band: the caller must SAMPLE from result.moves, not play bestmove */
	sample: boolean;
}

export function botRecipe(elo: number): BotRecipe {
	const clamped = Math.max(100, Math.min(3600, elo));
	if (clamped >= 1320) {
		return {
			options: [
				['MultiPV', '1'],
				['UCI_LimitStrength', 'true'],
				['UCI_Elo', String(Math.min(3190, clamped))]
			],
			go: 'go movetime 400',
			sample: false
		};
	}
	if (clamped >= 800) {
		const t = (clamped - 800) / (1320 - 800); // 0..1 over this band
		return {
			options: [
				['MultiPV', '1'],
				['Skill Level', String(Math.round(t * 6))] // 0..6
			],
			go: 'go depth ' + (1 + Math.round(t * 4)), // depth 1..5
			sample: false
		};
	}
	return {
		options: [['MultiPV', '24']],
		go: 'go depth ' + (clamped < 500 ? 1 : 2),
		sample: true
	};
}

// undo every option a recipe may have touched, so the next search (full
// analysis in the app, the other bot in the harness) starts clean
export function botResetOptions(defaultMultiPV: number): [string, string][] {
	return [
		['UCI_LimitStrength', 'false'],
		['Skill Level', '20'],
		['MultiPV', String(defaultMultiPV)]
	];
}
