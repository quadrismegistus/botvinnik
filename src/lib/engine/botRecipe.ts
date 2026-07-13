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

export type Substrate = 'native' | 'wasm';

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
// The app runs TWO different engines depending on the build:
//  - native: desktop/Tauri drives real Stockfish (big net, many cores) via
//    the Rust UCI sidecar. Strong.
//  - wasm: the web build drives Stockfish.js (small "lite-single" net,
//    single-threaded) in a Worker. Meaningfully weaker, especially at the
//    limiter's low end.
// The SAME requested ELO must therefore choose DIFFERENT settings on each
// substrate, so each has its own measured knot table. A knot's `e` is the
// setting's true strength (Bradley–Terry fit); botSpec inverts it — to hit
// strength X, pick the setting whose e = X.

interface SamplerKnot {
	e: number;
	alpha: number;
	depth: number;
}
interface UcieloKnot {
	e: number;
	elo: number;
	movetimeMs: number;
}
interface Bands {
	sampler: SamplerKnot[];
	ucielo: UcieloKnot[];
	samplerMax: number; // seam: sampler below, UCI_Elo above
	depthBoundary: number; // sampler runs depth 1 below this strength, else 2
	eloMin: number;
	eloMax: number; // honest ceiling — the strongest setting's measured strength
}

// native (desktop/Tauri big-net) — calibrated 2026-07-13, 1,760 games
// (data/bot-calibration.json + bot-probes.json + bot-verify.json). UCI_Elo
// @400ms is COMPRESSED here: the big net plays strong even when limited, so
// 2400→3190 spans only ~683 Elo and saturates — hence the 2800 cap.
const NATIVE: Bands = {
	// SAMPLER refined 2026-07-13 from a 2,600-game high-N ladder
	// (data/bot-native-hisample.json). The original n=40 fit ran ~85 Elo weak
	// across 100–1300 (slider-1000 actually played ~900); n=200 caught the
	// systematic tilt and the knots now invert to identity (700–2100 within
	// ±45). The UCI_Elo top band is still the n=40 fit (movetime = expensive).
	sampler: [
		{ e: -153, alpha: 0.1, depth: 1 },
		{ e: 155, alpha: 0.3, depth: 1 },
		{ e: 495, alpha: 0.5, depth: 2 },
		{ e: 773, alpha: 0.7, depth: 2 },
		{ e: 1161, alpha: 1.2, depth: 2 },
		{ e: 1627, alpha: 2, depth: 2 },
		{ e: 2033, alpha: 4, depth: 2 },
		{ e: 2327, alpha: 8, depth: 2 }
	],
	ucielo: [
		{ e: 2132, elo: 2400, movetimeMs: 400 },
		{ e: 2433, elo: 2800, movetimeMs: 400 },
		{ e: 2815, elo: 3190, movetimeMs: 400 }
	],
	samplerMax: 2100,
	depthBoundary: 410,
	eloMin: 100,
	eloMax: 2800
};

// wasm (web small-net) — calibrated 2026-07-13 from the app's actual engine
// (data/bot-wasm-specs.json spec ladder → data/bot-wasm-verify.json numeric
// ladder → knots rebuilt by inverting the verify, both anchored ≥1320→nominal
// like native). Opposite of native: the small net is weaker THROUGHOUT and its
// UCI_Elo band is EXPANDED (the limiter bites hard at the low end), and the
// softmax sampler is relatively stronger (a8 ≈ UCI_Elo 2400@400), so the seam
// sits higher (2485 vs native's 2100). The SAMPLER knots come from a 2,600-game
// high-N ladder (data/bot-wasm-hisample.json, 200 games/pair — sampler games
// are basically free at ~2000/min) inverted to identity: 700→2100 lands within
// ±32 of nominal, and the floor is ~90 so eloMin returns to 100. The UCIELO
// knots (the top, where games are movetime-bounded and expensive) are the
// n=40 fit and stay soft — that whole band is "very strong", the least
// label-sensitive region. NB the absolute scale is per-engine: web and desktop
// numbers are each internally honest but NOT comparable across substrates.
const WASM: Bands = {
	sampler: [
		{ e: 87, alpha: 0.1, depth: 1 },
		{ e: 416, alpha: 0.3, depth: 1 },
		{ e: 732, alpha: 0.5, depth: 2 },
		{ e: 968, alpha: 0.7, depth: 2 },
		{ e: 1397, alpha: 1.2, depth: 2 },
		{ e: 1812, alpha: 2, depth: 2 },
		{ e: 2239, alpha: 4, depth: 2 },
		{ e: 2485, alpha: 8, depth: 2 }
	],
	ucielo: [
		{ e: 2346, elo: 2400, movetimeMs: 400 },
		{ e: 2573, elo: 2800, movetimeMs: 400 },
		{ e: 3342, elo: 3190, movetimeMs: 400 }
	],
	// sampler covers cleanly up to a8 (2485); UCI_Elo takes only the top above it
	samplerMax: 2485,
	depthBoundary: 550,
	eloMin: 100,
	eloMax: 2800
};

const BANDS: Record<Substrate, Bands> = { native: NATIVE, wasm: WASM };

// The web build (default) drives WASM; Tauri flips this to 'native' at startup
// (see +layout.svelte). The offline harness sets it from --substrate.
let activeSubstrate: Substrate = 'wasm';
export function setBotSubstrate(s: Substrate): void {
	activeSubstrate = s;
}
export function getBotSubstrate(): Substrate {
	return activeSubstrate;
}
export function botEloMin(s: Substrate = activeSubstrate): number {
	return BANDS[s].eloMin;
}
export function botEloMax(s: Substrate = activeSubstrate): number {
	return BANDS[s].eloMax;
}

function lerp(x: number, x0: number, x1: number, y0: number, y1: number): number {
	const t = x1 === x0 ? 0 : (x - x0) / (x1 - x0);
	return y0 + t * (y1 - y0);
}

export function botSpec(elo: number, s: Substrate = activeSubstrate): BotSpec {
	const b = BANDS[s];
	const e = Math.max(b.eloMin, Math.min(b.eloMax, elo));
	if (e <= b.samplerMax) {
		return { kind: 'sampler', alpha: samplerAlphaFor(e, s), depth: e < b.depthBoundary ? 1 : 2 };
	}
	const k = b.ucielo;
	if (e <= k[0].e) return { kind: 'ucielo', elo: k[0].elo, movetimeMs: k[0].movetimeMs };
	for (let i = 0; i + 1 < k.length; i++) {
		if (e <= k[i + 1].e) {
			// interpolate the UCI_Elo knob at fixed movetime
			return {
				kind: 'ucielo',
				elo: Math.round(lerp(e, k[i].e, k[i + 1].e, k[i].elo, k[i + 1].elo)),
				movetimeMs: k[i].movetimeMs
			};
		}
	}
	const top = k[k.length - 1];
	return { kind: 'ucielo', elo: top.elo, movetimeMs: top.movetimeMs };
}

// the sampler's softmax exponent for a requested ELO: geometric interpolation
// between measured knots (α is ~linear in log-space against true strength)
export function samplerAlphaFor(elo: number, s: Substrate = activeSubstrate): number {
	const b = BANDS[s];
	const e = Math.max(b.eloMin, Math.min(b.eloMax, elo));
	const k = b.sampler;
	if (e <= k[0].e) return k[0].alpha;
	for (let i = 0; i + 1 < k.length; i++) {
		if (e <= k[i + 1].e) {
			return Math.exp(lerp(e, k[i].e, k[i + 1].e, Math.log(k[i].alpha), Math.log(k[i + 1].alpha)));
		}
	}
	return k[k.length - 1].alpha;
}

export function botRecipe(elo: number, s: Substrate = activeSubstrate): BotRecipe {
	return specToRecipe(botSpec(elo, s));
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
