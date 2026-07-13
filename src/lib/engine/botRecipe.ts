// The ELO → engine-weakening recipe, shared VERBATIM by the live app
// (analyzeBotMove in stockfish.ts) and the offline calibration harness
// (scripts/calibrate-bots.mts). If the two drift, the harness measures
// fiction — change the mapping ONLY here.
//
// Three MECHANISMS (a "spec"):
//  - sampler: wide-MultiPV shallow evals; the caller samples with softmax^α
//    (selectBotMove). Continuous knob: alpha. Beginner..club strength.
//  - skill: Stockfish "Skill Level" + a depth cap. Discrete rungs.
//  - ucielo: the engine's UCI_Elo limiter at a fixed movetime.
//
// The requested-ELO → spec mapping is CALIBRATED: scripts/calibrate-bots.mts
// plays specs against each other and fits true strengths; the knot tables
// below are measured, not guessed. See ROADMAP "Bot ELO calibration".

export type BotSpec =
	| { kind: 'sampler'; alpha: number; depth: number }
	| { kind: 'skill'; level: number; depth: number }
	| { kind: 'ucielo'; elo: number; movetimeMs: number };

export interface BotRecipe {
	options: [string, string][];
	go: string;
	/** sampler mechanism: the caller must SAMPLE from result.moves, not play bestmove */
	sample: boolean;
	/** the sampler's softmax exponent (only meaningful when sample is true) */
	alpha?: number;
}

export function specToRecipe(spec: BotSpec): BotRecipe {
	if (spec.kind === 'sampler') {
		return {
			options: [['MultiPV', '24']],
			go: `go depth ${spec.depth}`,
			sample: true,
			alpha: spec.alpha
		};
	}
	if (spec.kind === 'skill') {
		return {
			options: [
				['MultiPV', '1'],
				['Skill Level', String(spec.level)]
			],
			go: `go depth ${spec.depth}`,
			sample: false
		};
	}
	return {
		options: [
			['MultiPV', '1'],
			['UCI_LimitStrength', 'true'],
			['UCI_Elo', String(Math.max(1320, Math.min(3190, spec.elo)))]
		],
		go: `go movetime ${spec.movetimeMs}`,
		sample: false
	};
}

// spec ids for the harness: "sampler:a0.5:d2" | "skill:2:d3" | "ucielo:1600:mt400"
export function parseSpec(id: string): BotSpec {
	const parts = id.split(':');
	if (parts[0] === 'sampler') {
		return {
			kind: 'sampler',
			alpha: Number(parts[1].replace('a', '')),
			depth: Number(parts[2].replace('d', ''))
		};
	}
	if (parts[0] === 'skill') {
		return { kind: 'skill', level: Number(parts[1]), depth: Number(parts[2].replace('d', '')) };
	}
	if (parts[0] === 'ucielo') {
		return {
			kind: 'ucielo',
			elo: Number(parts[1]),
			movetimeMs: Number(parts[2].replace('mt', ''))
		};
	}
	// bare number: the app mapping
	return botSpec(Number(id));
}

// ---- the requested-ELO → spec mapping (the app's bands) ----

export function botSpec(elo: number): BotSpec {
	const clamped = Math.max(100, Math.min(3600, elo));
	if (clamped >= 1320) {
		return { kind: 'ucielo', elo: Math.min(3190, clamped), movetimeMs: 400 };
	}
	if (clamped >= 800) {
		const t = (clamped - 800) / (1320 - 800); // 0..1 over this band
		return { kind: 'skill', level: Math.round(t * 6), depth: 1 + Math.round(t * 4) };
	}
	return { kind: 'sampler', alpha: samplerAlphaFor(clamped), depth: clamped < 500 ? 1 : 2 };
}

// the sampler band's softmax exponent for a requested ELO — bot.ts uses this
// when sampling, so the curve must live here beside the band boundaries
export function samplerAlphaFor(elo: number): number {
	const clamped = Math.max(0, Math.min(1, (elo - 100) / (800 - 100)));
	return 0.1 + clamped * 0.7;
}

export function botRecipe(elo: number): BotRecipe {
	return specToRecipe(botSpec(elo));
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
