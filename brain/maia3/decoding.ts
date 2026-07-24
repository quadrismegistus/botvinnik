import { Chess } from 'chess.js';
import { isBlackToMove, mirrorSquare, moveVocabIndex } from './encoding';

/** Normalized WDL probability vector, in the natural W/D/L reading order. */
export interface WdlVector {
	win: number;
	draw: number;
	loss: number;
}

/** One ELO rung's per-legal-move probability distribution, keyed by SAN. */
export interface MoveCurvePoint {
	elo: number;
	moveProbabilities: Record<string, number>;
}

/** Raw per-rung policy as the worker returns it (one Float32Array per ELO). */
export interface RawPolicyByElo {
	elo: number;
	policy: Float32Array;
}

/** Raw per-rung WDL logits as the worker returns it (L, D, W order). */
export interface RawWdlByElo {
	elo: number;
	wdl: Float32Array;
}

/** Chart-ready output: every rung's move distribution + WDL. */
export interface MoveCurveResult {
	perElo: MoveCurvePoint[];
	wdlByElo: { elo: number; wdl: WdlVector }[];
}

/**
 * Masks the flat policy logits to the FEN's legal moves (via chess.js) and
 * applies a numerically-stable softmax, returning a normalized per-legal-move
 * distribution keyed by SAN. Mirrors from/to squares into the model's
 * white-POV frame when Black is to move before indexing into `policy`.
 */
export function maskAndSoftmax(policy: Float32Array, fen: string): Record<string, number> {
	const chess = new Chess(fen);
	const black = isBlackToMove(fen);
	const legalMoves = chess.moves({ verbose: true });

	const scores = legalMoves.map((move) => {
		const from = black ? mirrorSquare(move.from) : move.from;
		const to = black ? mirrorSquare(move.to) : move.to;
		const idx = moveVocabIndex(from, to, move.promotion);
		return policy[idx] ?? Number.NEGATIVE_INFINITY;
	});

	const max = scores.length > 0 ? Math.max(...scores) : 0;
	const exps = scores.map((s) => Math.exp(s - max));
	const sum = exps.reduce((a, b) => a + b, 0);

	const probabilities: Record<string, number> = {};
	legalMoves.forEach((move, i) => {
		probabilities[move.san] = sum > 0 ? (exps[i] ?? 0) / sum : 0;
	});
	return probabilities;
}

/**
 * Softmaxes raw `logits_value` into a normalized WDL vector. Logit order is
 * index 0 = Loss, 1 = Draw, 2 = Win (NOT W/D/L). Numerically stable.
 */
export function softmaxWdl(logits: ArrayLike<number>): WdlVector {
	const values = [logits[0] ?? 0, logits[1] ?? 0, logits[2] ?? 0];
	const max = Math.max(...values);
	const exps = values.map((v) => Math.exp(v - max));
	const sum = exps.reduce((a, b) => a + b, 0);
	const at = (i: number): number => (sum > 0 ? (exps[i] ?? 0) / sum : 0);
	return { loss: at(0), draw: at(1), win: at(2) };
}

/** Collapses WDL to a single expected-score fraction (0..1): win + 0.5*draw. */
export function expectedScore(wdl: WdlVector): number {
	return wdl.win + 0.5 * wdl.draw;
}

/**
 * Converts a worker's raw per-rung payload into the chart-friendly shape.
 * Each policy rung is masked+softmaxed against the FEN's legal moves; each
 * WDL rung is softmaxed. This is the single brain export the Flutter store
 * calls — keeping the math here (not duplicated in Dart) avoids the
 * brain→Flutter wire-gap hazard.
 */
export function computeMoveCurves(
	fen: string,
	rawPolicyByElo: readonly RawPolicyByElo[],
	rawWdlByElo: readonly RawWdlByElo[],
): MoveCurveResult {
	return {
		perElo: rawPolicyByElo.map(({ elo, policy }) => ({
			elo,
			moveProbabilities: maskAndSoftmax(policy, fen),
		})),
		wdlByElo: rawWdlByElo.map(({ elo, wdl }) => ({ elo, wdl: softmaxWdl(wdl) })),
	};
}
