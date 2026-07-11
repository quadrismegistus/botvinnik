// ELO-scaled bot move selection, ported from botvinnik-app's bots.ts:
// softmax sampling over move confidence, sharpened by ELO, with
// mate-spotting probability, an only-move rule, and blunder penalties.

import type { EngineMove } from './engine/stockfish';

function lineCp(l: EngineMove): number {
	if (l.mate !== null) return l.mate > 0 ? 9999 : -9999;
	return l.score * 100;
}

function clamp01(x: number): number {
	return Math.max(0, Math.min(1, x));
}

export function selectBotMove(lines: EngineMove[], elo: number): string | null {
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

	// ELO -> sampling sharpness. Below 800 the exponent drops toward 0.1 —
	// an effective temperature of ~1000cp, i.e. near-random beginner play
	// that only mildly avoids catastrophes. Above 800: α = 0.8..8.0.
	const alpha =
		elo < 800
			? 0.1 + clamp01((elo - 100) / (800 - 100)) * 0.7
			: 0.8 + clamp01((elo - 800) / (3600 - 800)) * 7.2;
	let probs = confs.map((c) => Math.pow(Math.max(c, 1e-6) / 100, alpha));

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

export function botDelay(minMs = 300, maxMs = 1000): number {
	return minMs + Math.floor(Math.random() * (maxMs - minMs + 1));
}
