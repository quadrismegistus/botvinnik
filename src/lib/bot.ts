// ELO-scaled bot move selection, ported from botvinnik-app's bots.ts:
// softmax sampling over move confidence, sharpened by ELO, with
// mate-spotting probability, an only-move rule, and blunder penalties.

import type { EngineMove } from './engine/stockfish';
import { winChance } from './engine/insights';

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

// ─── Shaped-blunder sampler (prototype) ────────────────────────────────────
//
// The plain sampler above blunders position-INDEPENDENTLY and UNBOUNDEDLY: it
// can play a howler in a trivial recapture and it can hang a queen, because it
// softmaxes over raw cp. Bot-vs-Maia calibration showed that kind of weakness
// is *exploitable* (our bands lost ~95% to a coherent bot dialed to ELO 600).
//
// This variant plays a SOUND player who makes BOUNDED, human-shaped mistakes:
//   1. Play the engine-best move most of the time (coherent baseline).
//   2. Only gamble in genuinely non-forcing positions — collapse to best in
//      easy/forcing/decided ones (the anti-swing rule).
//   3. When it does err, keep the move within a rating-scaled WIN-PROBABILITY
//      window (not raw cp), so a weaker bot gives up more but never hangs free
//      material — a hanging move falls outside the window and is filtered out.
//   4. Bias toward the SMALLER mistakes in that window (humans rarely find the
//      single worst move).
//
// SHAPE, from Ryan's own 4505-game profile (data/elonmarxx-profile.html): a real
// weak human plays a SPIKY distribution — near-perfect most moves (median win%
// loss ~0.6, ~55% of moves lose <1%) with a RARE FAT TAIL (~5.5% of moves lose
// ≥20% — the catastrophes), ~1.4 blunders/game. NOT uniform moderate sloppiness.
// So the model is a mixture: play best the large majority of the time; when a
// "slip" fires, sample within a rating-scaled win% window whose severity is fat-
// tailed at low ELO (real blunders happen) and small-biased at high ELO. Slips
// are suppressed in easy/forcing/decided positions (a beginner doesn't hang in a
// quiet recapture — their blunders cluster in the complex middlegame).
//
// Defaults are SEEDED from that profile; slipProb/windowPct get harness-
// calibrated per band (run-shaped-calibration.sh) to hit target ELOs, then the
// output distribution is checked back against the spiky profile.

export interface ShapedParams {
	/** P(not best) this move in a non-easy position — kept LOW (spiky, not sloppy). */
	slipProb: number;
	/** Max win% a slip may give up (wide at low ELO ⇒ real blunders possible). */
	windowPct: number;
	/** Best beats 2nd by ≥ this many win% points ⇒ treat as easy, play best. */
	easyGapPct: number;
	/** Severity weighting exponent 1/drop^tailBias: low ⇒ fatter catastrophe tail. */
	tailBias: number;
}

// Interpolated over ELO ~600..1600; above ~1500 it essentially plays best.
export function shapedParams(elo: number): ShapedParams {
	const t = clamp01((1500 - elo) / 900); // 0 at 1500+, 1 at 600
	return {
		slipProb: 0.05 + 0.22 * t, // ~5% at 1500 → ~22% at 800 → ~27% at 600
		windowPct: 10 + 45 * t, // 10% at 1500 → ~45% at 800 (a slip can be a real blunder)
		easyGapPct: 25, // best clearly best ⇒ no slip, any band
		tailBias: 1.4 - 0.9 * t // 1.4 (small-biased) at 1500 → 0.5 (fat tail) at 600
	};
}

export function shapedBotMove(
	lines: EngineMove[],
	elo: number,
	params?: Partial<ShapedParams>
): string | null {
	if (lines.length === 0) return null;
	const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);
	const best = sorted[0];
	if (sorted.length === 1) return best.pv[0];

	const { slipProb, windowPct, easyGapPct, tailBias } = { ...shapedParams(elo), ...params };

	const wins = sorted.map(moveWin); // win% per candidate, mover POV
	const bestWin = wins[0];
	const secondWin = wins[1];

	// Slips are suppressed where a weak human wouldn't blunder anyway:
	//  - best towers over the alternatives (recapture / only good move)
	//  - the game is already decided (win% saturates near 95/5 for big material
	//    leads — the ±1500cp clamp — so the decided band is 90/10, not 97/3)
	const easy = bestWin - secondWin >= easyGapPct || bestWin >= 90 || bestWin <= 10;
	if (easy || Math.random() >= slipProb) return best.pv[0];

	// A slip: sample a worse move within the win% window. The window bounds the
	// severity (so it never simply resigns), but at low ELO it's wide enough to
	// include genuine blunders — which real players at that level do make. The
	// 1/drop^tailBias weighting controls how often a slip is a catastrophe vs a
	// mild imprecision.
	const inWindow: { move: string; drop: number }[] = [];
	for (let i = 1; i < sorted.length; i++) {
		const drop = bestWin - wins[i];
		if (drop > 0 && drop <= windowPct) inWindow.push({ move: sorted[i].pv[0], drop });
	}
	if (inWindow.length === 0) return best.pv[0];

	const weights = inWindow.map((x) => 1 / Math.pow(Math.max(x.drop, 1), tailBias));
	const total = weights.reduce((a, b) => a + b, 0);
	let r = Math.random() * total;
	for (let k = 0; k < inWindow.length; k++) {
		r -= weights[k];
		if (r <= 0) return inWindow[k].move;
	}
	return inWindow[inWindow.length - 1].move;
}

export function botDelay(minMs = 300, maxMs = 1000): number {
	return minMs + Math.floor(Math.random() * (maxMs - minMs + 1));
}
