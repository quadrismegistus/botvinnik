import { getSan, isCapture } from './chess';
import { explainGoodMove, explainMove, materialOverLine, type Explanation } from './explain';
import type { EngineMove } from './stockfish';

// chess.com-style move labels, from their published expected-points bands
// (≤0.02 excellent, ≤0.05 good, 0.05–0.10 inaccuracy, 0.10–0.20 mistake,
// ≥0.20 blunder — our win% drop is expected points ×100), plus the special
// cases: brilliant = a sacrifice that leaves you better, great = the only
// good move, miss = a material-winning capture you didn't play.
export type MoveLabel =
	| 'brilliant'
	| 'great'
	| 'best'
	| 'excellent'
	| 'good'
	| 'inaccuracy'
	| 'miss'
	| 'mistake'
	| 'blunder';

// Grade of one played move, judged against the engine analysis of the
// position it was played from. Evals are from the mover's perspective.
export interface MoveGrade {
	ply: number;
	fenBefore: string;
	san: string;
	uci: string;
	color: 'w' | 'b';
	depth: number;
	rank: number | null; // 1-based rank among engine lines, null if outside them
	evalPawns: number | null;
	mate: number | null;
	pctBest: number | null; // 0..100 vs the best move, null if outside engine lines
	isBest: boolean;
	bestSan: string;
	bestUci: string;
	bestEval: number;
	bestMate: number | null;
	totalLines: number;
	offList: boolean; // wasn't among the engine's pre-move lines
	backfilled: boolean; // eval refined from the post-move search
	preLines: { uci: string; cp: number }[]; // pre-move eval pool, mover's cp
	bestPv: string[]; // the best move's full line, for explanations
	explanation?: Explanation;
	label?: MoveLabel; // set once backfilled
}

function lineCp(l: EngineMove): number {
	if (l.mate !== null) return l.mate > 0 ? 9999 : -9999;
	return l.score * 100;
}

// Win probability (0..100) from an eval in pawns, mover's perspective.
// Lichess's logistic curve: steep near equality, flat when the game is decided.
export function winChance(evalPawns: number | null, mate: number | null): number {
	if (mate !== null) return mate > 0 ? 100 : 0;
	if (evalPawns === null) return 50;
	const cp = Math.max(-1500, Math.min(1500, evalPawns * 100));
	return 50 + 50 * (2 / (1 + Math.exp(-0.00368208 * cp)) - 1);
}

// Win chance (0..100) always from White's perspective. Evals/mates are stored
// from the mover's perspective, so a Black move's win chance is flipped.
export function whitePovWinChance(
	color: 'w' | 'b',
	evalPawns: number | null,
	mate: number | null
): number {
	const wc = winChance(evalPawns, mate);
	return color === 'w' ? wc : 100 - wc;
}

export function gradeMove(
	ply: number,
	fenBefore: string,
	san: string,
	uci: string,
	color: 'w' | 'b',
	lines: EngineMove[]
): MoveGrade | null {
	if (lines.length === 0) return null;
	const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);

	// confidence = softmax over centipawn scores, τ = 100cp (same as the fork)
	const cps = sorted.map(lineCp);
	const maxCp = Math.max(...cps);
	const exps = cps.map((c) => Math.exp((c - maxCp) / 100));
	const denom = exps.reduce((a, b) => a + b, 0) || 1;
	const confs = exps.map((e) => (e / denom) * 100);
	const bestConf = Math.max(...confs);

	const idx = sorted.findIndex((l) => l.pv[0] === uci);
	const best = sorted[0];

	return {
		ply,
		fenBefore,
		san,
		uci,
		color,
		depth: best.depth,
		rank: idx >= 0 ? idx + 1 : null,
		evalPawns: idx >= 0 ? sorted[idx].score : null,
		mate: idx >= 0 ? sorted[idx].mate : null,
		pctBest: idx >= 0 && bestConf > 0 ? (confs[idx] / bestConf) * 100 : null,
		isBest: idx === 0,
		bestSan: getSan(fenBefore, best.pv[0]),
		bestUci: best.pv[0],
		bestEval: best.score,
		bestMate: best.mate,
		totalLines: sorted.length,
		offList: idx < 0,
		backfilled: false,
		preLines: sorted.map((l, i) => ({ uci: l.pv[0], cp: cps[i] })),
		bestPv: best.pv
	};
}

// Refine a grade using the search of the position the move created: the eval
// of a move IS the eval of its child position, negated (the child search
// reports from the opponent's perspective). Gives real numbers for moves
// outside the pre-move MultiPV lines, at no extra engine cost.
export function backfillGrade(grade: MoveGrade, childLines: EngineMove[]): MoveGrade {
	if (childLines.length === 0) return grade;
	const child = [...childLines].sort((a, b) => a.multipv - b.multipv)[0];
	const cp = -(child.mate !== null ? (child.mate > 0 ? 9999 : -9999) : child.score * 100);
	const mate = child.mate !== null ? -child.mate : null;

	// softmax pool = pre-move lines with the played move's entry replaced
	const others = grade.preLines.filter((l) => l.uci !== grade.uci);
	const pool = [...others.map((l) => l.cp), cp];
	const maxCp = Math.max(...pool);
	const exps = pool.map((c) => Math.exp((c - maxCp) / 100));
	const played = exps[exps.length - 1];
	const pctBest = Math.min(100, (played / Math.max(...exps)) * 100);
	const rank = 1 + others.filter((l) => l.cp > cp).length;

	const isBest = grade.isBest || pctBest >= 100;
	const playedPv = [grade.uci, ...child.pv];

	// classification à la chess.com, from win% drop (= expected points ×100)
	const wcBest = winChance(grade.bestEval, grade.bestMate);
	const wcPlayed = winChance(cp / 100, mate);
	const drop = Math.max(0, wcBest - wcPlayed);
	// "Miss": you didn't play the best move, and it was a capture that would
	// have won material — a missed material-winning shot. Only when you're
	// still ok after your move (wcPlayed >= 40); if you dropped into a worse
	// position it's a plain mistake/blunder, not a miss.
	const bestWinsMaterial =
		isCapture(grade.fenBefore, grade.bestUci) &&
		materialOverLine(grade.fenBefore, grade.bestPv.slice(0, 6)) >= 2;
	const missed = !isBest && bestWinsMaterial && drop >= 10 && wcPlayed >= 40;
	let label: MoveLabel;
	if (missed) label = 'miss';
	else if (drop >= 20) label = 'blunder';
	else if (drop >= 10) label = 'mistake';
	else if (drop >= 5) label = 'inaccuracy';
	else if (!isBest) label = drop <= 2 ? 'excellent' : 'good';
	else {
		// played the engine's best move — is it special?
		const shortNet = materialOverLine(grade.fenBefore, playedPv.slice(0, 4));
		const others = grade.preLines.filter((l) => l.uci !== grade.bestUci);
		const secondCp = others.length > 0 ? Math.max(...others.map((l) => l.cp)) : null;
		const wcSecond = secondCp === null ? null : winChance(secondCp / 100, null);
		// brilliant = a real sacrifice (down >=2 over the next plies) that leaves
		// you better (>=55%), and not already trivially winning
		if (shortNet <= -2 && wcPlayed >= 55 && wcBest <= 92) label = 'brilliant';
		else if (wcSecond !== null && wcBest - wcSecond >= 15) label = 'great';
		else label = 'best';
	}

	let explanation: Explanation | undefined;
	if (child.depth >= 10) {
		if (isBest || pctBest >= 90) {
			const point = explainGoodMove(grade.fenBefore, grade.uci, playedPv, mate);
			explanation = point ? { playedPoint: point.text, evidence: point.evidence } : undefined;
		} else {
			explanation = explainMove({
				fenBefore: grade.fenBefore,
				playedUci: grade.uci,
				refutationPv: child.pv.slice(0, 8),
				bestUci: grade.bestUci,
				bestPv: grade.bestPv,
				playedMate: mate,
				bestMate: grade.bestMate,
				isBest
			});
		}
	}

	return {
		...grade,
		depth: child.depth,
		evalPawns: mate !== null ? grade.evalPawns : cp / 100,
		mate,
		pctBest,
		rank,
		isBest,
		backfilled: true,
		explanation,
		label
	};
}
