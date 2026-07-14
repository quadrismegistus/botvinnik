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
// Params below are sensible defaults, to be corpus-calibrated (measure real
// ~700–900-rated blunder rate/severity) and harness-calibrated (bot-vs-bot ELO)
// before shipping. `ShapedParams` lets the calibrator override them per band,
// the same way the plain sampler takes a calibrated `alpha`.

export interface ShapedParams {
	/** P(make a mistake this move) in a non-easy position. */
	blunderProb: number;
	/** Max win% we'll voluntarily give up when we do err. */
	windowPct: number;
	/** Best beats 2nd by ≥ this many win% points ⇒ treat as easy, play best. */
	easyGapPct: number;
}

// Defaults interpolated over ELO ~600..1600; above ~1500 it plays pure best.
export function shapedParams(elo: number): ShapedParams {
	const t = clamp01((1500 - elo) / 900); // 0 at 1500+, 1 at 600
	return {
		blunderProb: 0.55 * t, // ~0.5 at 800, ~0.29 at 1100, 0 at 1500
		windowPct: 6 + 34 * t, // ~32% at 800, ~18% at 1100, 6% floor
		easyGapPct: 25 // best clearly best ⇒ no gamble, any band
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

	const { blunderProb, windowPct, easyGapPct } = { ...shapedParams(elo), ...params };

	const wins = sorted.map(moveWin); // win% per candidate, mover POV
	const bestWin = wins[0];
	const secondWin = wins[1];

	// Anti-swing rule: don't gamble when there's nothing to gamble over.
	//  - best towers over the alternatives (recapture / only good move)
	//  - the game is already decided (winning or lost) — playing on best avoids
	//    both throwing a won game and flailing in a lost one
	// (win% saturates near 95/5 for big material leads — the ±1500cp clamp — so
	// the decided band is 90/10, not 97/3)
	const easy = bestWin - secondWin >= easyGapPct || bestWin >= 90 || bestWin <= 10;
	if (easy || Math.random() >= blunderProb) return best.pv[0];

	// Bounded, human-shaped mistake: worse moves within the win% window only
	// (this auto-excludes free hangs — they drop win% past the window), weighted
	// toward the smaller mistakes.
	const inWindow: { move: string; drop: number }[] = [];
	for (let i = 1; i < sorted.length; i++) {
		const drop = bestWin - wins[i];
		if (drop > 0 && drop <= windowPct) inWindow.push({ move: sorted[i].pv[0], drop });
	}
	if (inWindow.length === 0) return best.pv[0];

	const weights = inWindow.map((x) => 1 / Math.max(x.drop, 1));
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
