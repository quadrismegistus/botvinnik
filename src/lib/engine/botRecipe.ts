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

// ---- the requested-ELO → spec mapping, from MEASURED knots ----
//
// Calibrated 2026-07-13 (native SF, 1,200 bot-vs-bot games, Bradley–Terry
// fit anchored on UCI_Elo@movetime-400 — data/bot-calibration.json +
// data/bot-probes.json). Two mechanisms suffice: the sampler covers the
// whole −60…2350 range CONTINUOUSLY (α is ~linear in log-space vs Elo),
// and UCI_Elo@movetime covers 2130…2960. The old Skill Level band was
// entirely redundant (all its rungs sat inside the sampler's range) and
// non-monotonic against UCI_Elo, so it's gone. Substrate note: knots were
// measured with the native big-net engine; the app's WASM small-net will
// shift them somewhat (rerun the harness with --engine to re-measure).

const SAMPLER_KNOTS = [
	{ e: -59, alpha: 0.1, depth: 1 },
	{ e: 241, alpha: 0.3, depth: 1 },
	{ e: 579, alpha: 0.5, depth: 2 },
	{ e: 848, alpha: 0.7, depth: 2 },
	{ e: 1221, alpha: 1.2, depth: 2 },
	{ e: 1638, alpha: 2, depth: 2 },
	{ e: 2022, alpha: 4, depth: 2 },
	{ e: 2349, alpha: 8, depth: 2 }
];
const UCIELO_KNOTS = [
	{ e: 2132, elo: 2400, movetimeMs: 400 },
	{ e: 2433, elo: 2800, movetimeMs: 400 },
	{ e: 2815, elo: 3190, movetimeMs: 400 }
];
// seam: sampler below, UCI_Elo above (both measured within ~±50 there)
const SAMPLER_MAX = 2100;
// Honest ceiling. The 560-game verification ladder (data/bot-verify.json)
// measured requested 2700→3000 as only ~+80 true Elo: at UCI_Elo 3190 the
// engine is saturated, and stretching movetime 400→1000ms buys almost
// nothing on these short controls. That flat top rung was a lie, so the
// movetime-stretch knot is gone and the slider caps where strength actually
// tops out — UCI_Elo 3190 @ 400ms sits at ~e2815, so 2800 is the last
// setting that means what it says. (The app's WASM small-net is weaker
// still, so 2800 is already generous — re-measure with --engine to tighten.)
export const BOT_ELO_MAX = 2800;
export const BOT_ELO_MIN = 100;

function lerp(x: number, x0: number, x1: number, y0: number, y1: number): number {
	const t = x1 === x0 ? 0 : (x - x0) / (x1 - x0);
	return y0 + t * (y1 - y0);
}

export function botSpec(elo: number): BotSpec {
	const e = Math.max(BOT_ELO_MIN, Math.min(BOT_ELO_MAX, elo));
	if (e <= SAMPLER_MAX) {
		return { kind: 'sampler', alpha: samplerAlphaFor(e), depth: e < 410 ? 1 : 2 };
	}
	const k = UCIELO_KNOTS;
	if (e <= k[0].e) return { kind: 'ucielo', elo: k[0].elo, movetimeMs: k[0].movetimeMs };
	for (let i = 0; i + 1 < k.length; i++) {
		if (e <= k[i + 1].e) {
			if (k[i].elo !== k[i + 1].elo) {
				// interpolate the UCI_Elo knob at fixed movetime
				return {
					kind: 'ucielo',
					elo: Math.round(lerp(e, k[i].e, k[i + 1].e, k[i].elo, k[i + 1].elo)),
					movetimeMs: k[i].movetimeMs
				};
			}
			// knob saturated — interpolate movetime instead (geometrically)
			const mt = Math.exp(
				lerp(e, k[i].e, k[i + 1].e, Math.log(k[i].movetimeMs), Math.log(k[i + 1].movetimeMs))
			);
			return { kind: 'ucielo', elo: k[i].elo, movetimeMs: Math.round(mt / 50) * 50 };
		}
	}
	const top = k[k.length - 1];
	return { kind: 'ucielo', elo: top.elo, movetimeMs: top.movetimeMs };
}

// the sampler's softmax exponent for a requested ELO: geometric interpolation
// between measured knots (α is ~linear in log-space against true strength)
export function samplerAlphaFor(elo: number): number {
	const e = Math.max(BOT_ELO_MIN, Math.min(BOT_ELO_MAX, elo));
	const k = SAMPLER_KNOTS;
	if (e <= k[0].e) return k[0].alpha;
	for (let i = 0; i + 1 < k.length; i++) {
		if (e <= k[i + 1].e) {
			return Math.exp(
				lerp(e, k[i].e, k[i + 1].e, Math.log(k[i].alpha), Math.log(k[i + 1].alpha))
			);
		}
	}
	return k[k.length - 1].alpha;
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
