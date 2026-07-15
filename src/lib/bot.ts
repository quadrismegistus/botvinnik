// ELO-scaled bot move selection, ported from botvinnik-app's bots.ts:
// softmax sampling over move confidence, sharpened by ELO, with
// mate-spotting probability, an only-move rule, and blunder penalties.

import type { EngineMove } from './engine/stockfish';
import { winChance } from './engine/insights';
import { getBotSubstrate, type Substrate } from './engine/botRecipe';

function lineCp(l: EngineMove): number {
	if (l.mate !== null) return l.mate > 0 ? 9999 : -9999;
	return l.score * 100;
}

// Win% (0..100) for the side to move after playing this line. EngineMove.score
// is from the mover's POV, so this is the bot's own winning chances.
function moveWin(l: EngineMove): number {
	return winChance(l.mate === null ? l.score : null, l.mate);
}

function clamp01(x: number): number {
	return Math.max(0, Math.min(1, x));
}

export function selectBotMove(lines: EngineMove[], elo: number, alpha?: number): string | null {
	if (lines.length === 0) return null;
	const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);

	// Forced-mate awareness: chance to spot a mate scales 5%..100% over ELO 100..3000
	const mates = sorted.filter((l) => l.mate !== null && l.mate > 0);
	if (mates.length > 0) {
		const quickest = mates.reduce((a, b) => (a.mate! <= b.mate! ? a : b));
		const pSeeMate = 0.05 + 0.95 * clamp01((elo - 100) / (3000 - 100));
		if (Math.random() < pSeeMate) return quickest.pv[0];
		// else: intentionally allowed to miss the mate; fall through to sampling
	}

	// confidence = softmax over cp, τ = 100cp (same as insights)
	const cps = sorted.map(lineCp);
	const maxCp = Math.max(...cps);
	const exps = cps.map((c) => Math.exp((c - maxCp) / 100));
	const denom = exps.reduce((a, b) => a + b, 0) || 1;
	const confs = exps.map((e) => (e / denom) * 100);
	const bestIdx = confs.indexOf(Math.max(...confs));
	const bestConf = confs[bestIdx];

	// Only-move rule: strong players don't gamble when one move towers over the rest
	if (elo >= 2000 && sorted.length > 1) {
		const secondBest = Math.max(...confs.filter((_, i) => i !== bestIdx));
		if ((secondBest / bestConf) * 100 < 20) return sorted[bestIdx].pv[0];
	}

	// Sampling sharpness: the sampler band passes its CALIBRATED exponent in
	// (botSpec's alpha knob); the legacy ELO ramp remains only for the
	// fallback path, where this samples full-strength analysis lines.
	const a = alpha ?? 0.8 + clamp01((elo - 800) / (3600 - 800)) * 7.2;
	let probs = confs.map((c) => Math.pow(Math.max(c, 1e-6) / 100, a));

	// Blunder bias at high ELO: steeply downweight moves far below the best
	if (elo >= 2200) {
		probs = probs.map((p, i) => {
			const pctBest = (confs[i] / bestConf) * 100;
			return p * (pctBest < 60 ? 0.2 : pctBest < 75 ? 0.5 : 1);
		});
	}

	const sum = probs.reduce((a, b) => a + b, 0);
	if (!(sum > 0)) return sorted[0].pv[0];
	let r = Math.random() * sum;
	for (let i = 0; i < sorted.length; i++) {
		r -= probs[i];
		if (r <= 0) return sorted[i].pv[0];
	}
	return sorted[sorted.length - 1].pv[0];
}

// ─── Shaped-blunder sampler (v3: miss-the-tactic model) ─────────────────────
//
// Two earlier designs failed the same way (data/bot-shaped-proto-calib.json,
// data/bot-shaped-calib.json spiky run): both "play best except occasional
// bounded/spiky slips" models fitted 2000-2900 at EVERY label, beating numeric
// 900/1200 100-0. Diagnosis: (a) an easy-gap gate that suppresses slips when
// best towers over the rest protects EXACTLY the tactical positions where real
// humans blunder; (b) a convert-when-winning gate makes every won position a
// depth-12 conversion; (c) blunders only cost when the opponent punishes — and
// a depth-12 backbone punishes every opponent mistake, so strength stays high
// no matter what the error DISTRIBUTION looks like. Matching Ryan's spiky
// profile (median 0.6% loss, rare fat tail) got the texture right and the
// strength completely wrong: error-vs-CRITICALITY correlation, not error size,
// is what sets strength.
//
// So v3 inverts the model. A human blunder is *failing to see* something:
//   1. TACTICAL position (best beats 2nd by a real win% gap — there is
//      something to see): with p = missProb the bot doesn't see it. The best
//      move is EXCLUDED and it chooses among the rest on their apparent merits.
//      Missing the only defence — or the opponent's hanging queen — IS the
//      catastrophe, and it fires precisely where humans fire. This also makes
//      the bot fail to PUNISH (a punish is just a tactic from our side), which
//      is the other half of being genuinely weak.
//   2. QUIET position (moves are close): sound-but-mushy play — softmax over
//      win% with an ELO-scaled temperature, restricted to a window so it never
//      self-destructs when nothing is going on. Constant small leakage, no
//      howlers: quiet howlers are what made the old softmax sampler feel broken.
//   3. NO conversion gate: won positions are sampled like any other, so weak
//      bands wander and flub wins the way beginners do. (Win% saturates ~95
//      for big leads, so decided positions read as quiet ⇒ mushy play.)
//
// Output is still spiky like Ryan's real profile — near-best most moves, rare
// fat-tail catastrophes — but the catastrophes now correlate with criticality.
// missProb/temperature get harness-calibrated per band (run-shaped-calibration.sh).

export interface ShapedParams {
	/** P(failing to see the best move in a tactical position — the human blunder). */
	missProb: number;
	/** Best beats 2nd by ≥ this many win% points ⇒ tactical (something to see). */
	tacticalGapPct: number;
	/** Softmax temperature (win% points) for move choice — higher = mushier play. */
	temperature: number;
	/** Quiet positions only: ignore moves giving up more win% than this. */
	quietWindowPct: number;
}

// Interpolated over ELO ~600..1600; above ~1600 it plays near-best throughout.
// The bottom is HARSH by design: the first quick runs (0.44 miss / temp 8 /
// window 20 / depth 6) still measured ~1500 — a mostly-sound player with any
// engine backbone has a high strength floor, so reaching beginner takes miss
// rates and mushiness that look extreme on paper.
export function shapedParams(elo: number): ShapedParams {
	const t = clamp01((1600 - elo) / 1000); // 0 at 1600+, 1 at 600
	return {
		missProb: 0.04 + 0.56 * t, // 4% at 1600 → ~38% at 1000 → 60% at 600
		tacticalGapPct: 15,
		temperature: 1.5 + 10.5 * t, // 1.5 at 1600 → 12 at 600
		quietWindowPct: 6 + 24 * t // 6 at 1600 → 30 at 600
	};
}

// Deterministic hash → [0,1). Used for STICKY miss decisions: a human who
// doesn't see a tactic keeps not seeing it on later moves — without this the
// per-move re-roll makes eventually-punishing-a-hanging-piece a certainty
// (1 - missProb^k → 1), which kept shaped:600 beating numeric-900 100-0.
function hash01(key: string): number {
	let h = 2166136261;
	for (let i = 0; i < key.length; i++) {
		h ^= key.charCodeAt(i);
		h = Math.imul(h, 16777619);
	}
	return (h >>> 0) / 4294967296;
}

// Softmax-sample over candidate win%s with the given temperature.
function softmaxPick(cands: { move: string; win: number }[], temperature: number): string {
	const maxWin = Math.max(...cands.map((c) => c.win));
	const weights = cands.map((c) => Math.exp((c.win - maxWin) / Math.max(temperature, 0.1)));
	const total = weights.reduce((a, b) => a + b, 0);
	let r = Math.random() * total;
	for (let k = 0; k < cands.length; k++) {
		r -= weights[k];
		if (r <= 0) return cands[k].move;
	}
	return cands[cands.length - 1].move;
}

export function shapedBotMove(
	lines: EngineMove[],
	elo: number,
	params?: Partial<ShapedParams>,
	seed?: string | number
): string | null {
	if (lines.length === 0) return null;
	const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);
	const best = sorted[0];
	if (sorted.length === 1) return best.pv[0];

	const { missProb, tacticalGapPct, temperature, quietWindowPct } = {
		...shapedParams(elo),
		...params
	};

	const wins = sorted.map(moveWin); // win% per candidate, mover POV
	const bestWin = wins[0];

	// Decided-and-WINNING: the ±1500cp clamp saturates win% (~95) so the
	// gradient vanishes — +9, +12 and mate-in-16 all look alike, and quiet
	// temperature sampling becomes an aimless shuffle that can walk into a
	// repetition draw (observed: a 118-move Q-vs-K+P "draw" with M16 on the
	// board). Real weak players convert slowly but DIRECTIONALLY. So here the
	// choice signal switches to the UNCLAMPED eval — pawns, with mate lines
	// scored by mate distance — keeping the temperature so conversion stays
	// human-sloppy, not the old perfect-conversion superpower.
	//
	// Guard: this only applies when the game is won WHICHEVER move it picks
	// (second-best still ≥ 85). If only the best move is winning — a hanging
	// queen to capture, a tactic to land — that's a see-it-or-miss-it moment
	// and must fall through to the miss machinery below, or punishing becomes
	// automatic again.
	if (bestWin >= 90 && wins[1] >= 85) {
		const cands: { move: string; win: number }[] = [];
		for (let i = 0; i < sorted.length; i++) {
			if (wins[i] < 85) continue; // never gamble the win itself away
			const l = sorted[i];
			const v = l.mate !== null && l.mate > 0 ? 25 - Math.min(l.mate, 15) : l.score;
			cands.push({ move: l.pv[0], win: v });
		}
		// temperature is in win% points; evals are in pawns — rescale
		if (cands.length > 0) return softmaxPick(cands, temperature / 4);
	}

	if (bestWin - wins[1] >= tacticalGapPct) {
		// Tactical: there is one move that matters. Either the bot sees it…
		// With a per-game seed the decision is STICKY, keyed on the tactic's
		// focal point (the best move's destination square): a hanging piece
		// missed this move stays unseen while it sits there; the bot only "takes
		// a fresh look" when the tactical focus moves elsewhere.
		//
		// VISIBILITY: a flat missProb had Squares donating mate-in-1s (observed
		// live — Ryan's Square 1300 game). Short mates are the one tactic even
		// beginners reliably scan for (checks first!), so they're ~4× more
		// visible; deeper tactics keep the full miss rate.
		const mateSoon = best.mate !== null && best.mate > 0 && best.mate <= 2;
		const p = mateSoon ? missProb * 0.25 : missProb;
		const roll = seed !== undefined ? hash01(`${seed}:${best.pv[0].slice(2, 4)}`) : Math.random();
		if (roll >= p) return best.pv[0];
		// …or it doesn't. Choose among the REST as if the best move didn't exist —
		// still preferring the more plausible of what it can see. No severity cap:
		// missing the only defence is exactly how a won game gets lost.
		return softmaxPick(
			sorted.slice(1).map((l, i) => ({ move: l.pv[0], win: wins[i + 1] })),
			temperature
		);
	}

	// Quiet: nothing to see, just play sound-but-imperfect chess. Bounded so the
	// leakage is steady small stuff, never a howler out of nowhere.
	const cands: { move: string; win: number }[] = [];
	for (let i = 0; i < sorted.length; i++) {
		if (bestWin - wins[i] <= quietWindowPct) cands.push({ move: sorted[i].pv[0], win: wins[i] });
	}
	return softmaxPick(cands, temperature);
}

// ─── Shaped label inversion ──────────────────────────────────────────────────
//
// The label→strength curves, measured per substrate on the honest UCI_Elo
// ruler (n=50/pair: internal ladder at 150-pt label steps + upper bands vs
// ucielo:1320/1600/2000:mt400, BT fit rebased so ucielo:1320 = 1320).
//   wasm:   data/bot-shaped-calib.json — the web lite-single engine.
//   native: data/bot-shaped-native-calib.json — the EXACT big-net sidecar
//           the Tauri app ships.
//   both:   remeasured 2026-07-15 WITH the mate-visibility discount
//           (short mates ~4x more visible), which nudged the middle bands
//           up ~30-70 — the price of not donating mate-in-1s.
// The two curves agree within cross-run noise (±60-80): the miss-the-tactic
// choice layer dominates so completely that backbone net quality barely
// moves strength — the weakening really does live in the choice, not the
// search. shaped:LABEL plays HARDER than its label at the top (1500→~1950),
// so the app inverts: given a target ELO, find the label that MEASURES there.
const SHAPED_KNOTS: Record<Substrate, { label: number; strength: number }[]> = {
	wasm: [
		{ label: 600, strength: 768 },
		{ label: 750, strength: 904 },
		{ label: 900, strength: 1048 },
		{ label: 1050, strength: 1225 },
		{ label: 1200, strength: 1357 },
		{ label: 1350, strength: 1641 },
		{ label: 1500, strength: 1971 }
	],
	native: [
		{ label: 600, strength: 756 },
		{ label: 750, strength: 815 },
		{ label: 900, strength: 982 },
		{ label: 1050, strength: 1153 },
		{ label: 1200, strength: 1368 },
		{ label: 1350, strength: 1639 },
		{ label: 1500, strength: 2024 }
	]
};

/** Measured strength range the shaped bot can honestly cover. */
export function shapedStrengthRange(substrate: Substrate = getBotSubstrate()): {
	min: number;
	max: number;
} {
	const k = SHAPED_KNOTS[substrate];
	return { min: k[0].strength, max: k[k.length - 1].strength };
}

/** Invert the measured curve: target strength on our scale → shaped label. */
export function shapedLabelFor(
	targetElo: number,
	substrate: Substrate = getBotSubstrate()
): number {
	const k = SHAPED_KNOTS[substrate];
	if (targetElo <= k[0].strength) return k[0].label;
	if (targetElo >= k[k.length - 1].strength) return k[k.length - 1].label;
	for (let i = 1; i < k.length; i++) {
		if (targetElo <= k[i].strength) {
			const f = (targetElo - k[i - 1].strength) / (k[i].strength - k[i - 1].strength);
			return Math.round(k[i - 1].label + f * (k[i].label - k[i - 1].label));
		}
	}
	return k[k.length - 1].label;
}

// Search depth for the shaped bot's MultiPV analysis, by label. Part of the
// weakening (a flat strong backbone kept eval ordering at master strength no
// matter the choice layer); must match the harness's shapedDepth so the app
// reproduces the calibrated strength.
export function shapedSearchDepth(label: number): number {
	return Math.max(4, Math.min(12, Math.round(4 + (8 * (label - 600)) / 900)));
}

export function botDelay(minMs = 300, maxMs = 1000): number {
	return minMs + Math.floor(Math.random() * (maxMs - minMs + 1));
}
