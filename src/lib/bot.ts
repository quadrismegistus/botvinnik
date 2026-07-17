// ELO-scaled bot move selection, ported from botvinnik-app's bots.ts:
// softmax sampling over move confidence, sharpened by ELO, with
// mate-spotting probability, an only-move rule, and blunder penalties.

import { Chess } from 'chess.js';
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
	/**
	 * v4 (scan model): weight the miss coin by the tactic's VISIBILITY (human
	 * scan order: checks, captures, threats, then quiet moves) and damp errors
	 * over the rehearsed opening moves. Needs the fen passed to shapedBotMove.
	 * OFF by default — v3 personas and the deployed SquareFish keep their
	 * calibrated behavior until the v4 knots are measured.
	 */
	scan?: boolean;
	/** scan-model multiplier overrides (bench sweeps); defaults to SCAN_MULTS */
	scanMults?: Partial<ScanMults>;
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

// ─── v4 scan model: how visible is the tactic? ──────────────────────────────
//
// The puzzle bench exposed v3's structural flaw: the miss coin fires on a
// hanging queen as often as on a five-move quiet win, because the tactical
// gate measures IMPORTANCE (win% at stake), not DIFFICULTY (how hard to see).
// Measured: Square 900 solves only 78% of 400-800-rated puzzles (humans ~99%)
// yet 14% of 2400+ (humans ~0%) — a flat difficulty curve where humans are
// steep. Corroborated by feel ("bot misses obvious captures" — Ryan) and folk
// testimony (blunders happen under pressure, not on free pieces — 1350 USCF).
//
// The fix is the human scan order — checks, captures, threats, then quiet
// moves — as a multiplier on missProb, computed from the best line's PV:
// grabbing a big piece is near-unmissable; a winning capture is easy; a check
// is easy; a QUIET move whose payoff lands deep in the line is where real
// club players go blind; a line that gives up material first (a sacrifice)
// is the least visible of all. Averages redistribute rather than shift, but
// the knots get remeasured before any v4 persona ships (see SHAPED_KNOTS).

const PIECE_VAL: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

export interface TacticVisibility {
	multiplier: number; // scales missProb; <1 = more visible, >1 = subtler
	kind: string; // for logging/tests
}

/** The scan model's tunable multipliers — swept against the puzzle bench. */
export interface ScanMults {
	mateSoon: number; // mate in ≤2: checks are scanned first
	recapture: number; // capture on the square the opponent JUST moved to
	grab: number; // first move takes a rook/queen and keeps it
	capture: number; // any capture that wins material by line's end
	check: number; // non-capture check
	quiet: number; // no capture, no check — the human blind spot
	quietShallow: number; // quiet but engine-preferred at depth 1 (d* known)
	sac: number; // extra factor when material is given up before the payoff
	deepBase: number; // d*≥2 multiplier = deepBase + deepSlope·(d*−1)
	deepSlope: number;
	deepCap: number;
	pCap: number; // ceiling on the effective miss probability
}

// Bench-swept (scripts/puzzle-rating/sweep.mts, 122 configs on cached
// searches — data/puzzle-sweep.json): winner at display-900 solves 96.4% of
// <800 puzzles (v4.0: 87.6%, v3: 78.4%) and 21.6% of 2000+ (humans ~3%).
// BOTH residuals are saturated — no multiplier moves them — because they're
// BRANCH-ROUTING effects, not miss-coin effects: remaining easy fails come
// from the conversion/quiet branches picking a DIFFERENT fine move that
// lichess grades wrong (the "my move also wins" complaint), and the hard
// floor is the 12-candidate quiet softmax guessing the answer ~1/5 of the
// time when depth-7 eval rates it only narrowly best (gap < gate). Deeper
// surgery if ever needed; the gym governs game strength either way.
export const SCAN_MULTS: ScanMults = {
	mateSoon: 0.04,
	recapture: 0.02,
	grab: 0.03,
	capture: 0.08,
	check: 0.1,
	quiet: 2.8,
	quietShallow: 0.98,
	sac: 1.5,
	deepBase: 0.96,
	deepSlope: 0.5,
	deepCap: 2.8,
	pCap: 0.97
};

/**
 * Visibility of the best line's tactic, from the mover's perspective.
 *
 * `discoveryDepth` (d*) is the PRIMARY signal when available: the first
 * search depth at which this move took the lead during iterative deepening.
 * Validated against 1469 human-rated puzzles (Spearman ρ = 0.859 vs puzzle
 * rating, data/puzzle-discovery.json): trivial puzzles are uniformly d*=1,
 * 2400+ ideas average d*≈4.5. d*≥2 sets the multiplier outright; within
 * d*=1 (67% of tactics, ratings 400-1800) the scan-order categories still
 * discriminate the free queen from the subtle-but-shallow shot.
 */
export function tacticVisibility(
	fen: string,
	pv: string[],
	mate: number | null,
	discoveryDepth?: number,
	m: ScanMults = SCAN_MULTS,
	lastMoveTo?: string
): TacticVisibility {
	// short mates: even beginners scan checks first (v3's ×0.25 rule, kept)
	if (mate !== null && mate > 0 && mate <= 2) return { multiplier: m.mateSoon, kind: 'mate-soon' };
	// recapture on the square the opponent JUST moved to: salient in a
	// pre-chess way — attention goes to where their piece landed before any
	// trained scan order exists (observed live: SquareFish let a queen live
	// after QxQ; the sticky miss then kept it alive). Checked before d* and
	// the categories: if the recapture IS the best move, nothing about being
	// deep-to-verify makes it less noticeable.
	if (lastMoveTo && pv[0]?.slice(2, 4) === lastMoveTo) {
		try {
			const probe = new Chess(fen);
			const mv = probe.move({
				from: pv[0].slice(0, 2),
				to: pv[0].slice(2, 4),
				promotion: pv[0].length > 4 ? pv[0][4] : undefined
			});
			if (mv.captured) return { multiplier: m.recapture, kind: 'recapture' };
		} catch {
			// fall through to the normal classification
		}
	}
	// deep-only tactics: only deep search prefers this move — the certified
	// "hard to see" signal. Rises past baseline immediately and saturates at
	// master-level invisibility (d*≥5 ideas are 2200+ puzzles).
	if (discoveryDepth !== undefined && discoveryDepth >= 2) {
		return {
			multiplier: Math.min(m.deepBase + m.deepSlope * (discoveryDepth - 1), m.deepCap),
			kind: `deep-d${discoveryDepth}`
		};
	}
	try {
		const c = new Chess(fen);
		const mover = c.turn();
		const balance = () => {
			let v = 0;
			for (const row of c.board())
				for (const sq of row) if (sq) v += (sq.color === mover ? 1 : -1) * PIECE_VAL[sq.type];
			return v;
		};
		const start = balance();
		let firstCaptureVal = 0;
		let givesCheck = false;
		let settledMin = 0; // worst settled material swing (after opponent replies)
		let finalGain = 0;
		for (let i = 0; i < Math.min(pv.length, 10); i++) {
			const uci = pv[i];
			const m = c.move({
				from: uci.slice(0, 2),
				to: uci.slice(2, 4),
				promotion: uci.length > 4 ? uci[4] : undefined
			});
			if (i === 0) {
				firstCaptureVal = m.captured ? PIECE_VAL[m.captured] : 0;
				givesCheck = c.inCheck();
			}
			const gain = balance() - start;
			// material only counts as spent/won once the opponent has replied
			if (i % 2 === 1) settledMin = Math.min(settledMin, gain);
			finalGain = gain;
		}
		// d* told us it's shallow (or is unknown): the scan-order categories
		// spread the d*=1 mass. With a KNOWN-shallow move, quiet caps at
		// baseline — the engine already prefers it at depth 1, so it can't be
		// harder to see than an ordinary tactic.
		const shallow = discoveryDepth !== undefined; // implies d* <= 1 here
		let v: TacticVisibility;
		if (firstCaptureVal >= 5 && finalGain >= 3)
			v = { multiplier: m.grab, kind: 'grab' }; // free rook/queen: unmissable
		else if (firstCaptureVal > 0 && finalGain >= 1)
			v = { multiplier: m.capture, kind: 'winning-capture' };
		else if (givesCheck) v = { multiplier: m.check, kind: 'check' };
		else v = { multiplier: shallow ? m.quietShallow : m.quiet, kind: 'quiet' };
		if (settledMin <= -2 && !shallow) {
			// gives up real material before the payoff: the brilliancy class
			// (skipped when d* is known — late discovery already encodes it)
			v = { multiplier: Math.min(v.multiplier * m.sac, m.deepCap), kind: `${v.kind}-sac` };
		}
		return v;
	} catch {
		return { multiplier: 1, kind: 'unknown' };
	}
}

// Openings are rehearsed, not calculated: real club players play the first
// ~8 moves near-perfectly and start erring as positions leave known ground
// (1350 USCF testimony; every opening-explorer stat agrees). Ramp errors in
// from 30% strength at move 1 to full by move 9.
export function openingDamp(fen: string): number {
	const moveNo = Number(fen.split(' ')[5]) || 20;
	return clamp01(0.3 + (0.7 * (moveNo - 1)) / 8);
}

// THE SCAN IS A LEARNED SKILL. The visibility discounts encode "nobody misses
// a free queen" — true at 900, false at 500: checks-captures-threats is the
// first discipline chess teachers drill, and beginners haven't internalized
// it. Without this, v4's floor rose to ~display-618 (the gym: label-600
// measured 858 internal) because even maximal missProb was neutered by the
// grab/capture discounts. scanSkill fades every scan-model effect — tactic
// visibility, the danger penalty, opening rehearsal — toward the flat v3
// coin as the label drops toward beginner, restoring the ladder's bottom and
// making sub-600 labels meaningful again (shapedParams saturates at 600, but
// scan discipline keeps declining below it).
export function scanSkill(elo: number): number {
	return clamp01((elo - 350) / 550); // 0 at ≤350 (no scan yet) → 1 at ≥900
}

/**
 * Attenuate a scan-model factor toward 1 (no effect) by skill — but ONLY the
 * discounts. A factor < 1 is a learned ability (spotting visible tactics,
 * avoiding visible danger, opening rehearsal) that beginners lack; a factor
 * > 1 is the tactic being objectively hard to see, which no lack of training
 * relieves. Attenuating amplifiers made label-450 BEAT label-600 in the gym
 * (the less-skilled bot missed FEWER subtle tactics) — monotonicity requires
 * this asymmetry.
 */
function bySkill(factor: number, skill: number): number {
	return factor >= 1 ? factor : 1 + (factor - 1) * skill;
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

// Softmax-sample over candidate win%s with the given temperature. Optional
// per-candidate weight factors (the scan model's danger penalty).
function softmaxPick(
	cands: { move: string; win: number }[],
	temperature: number,
	factors?: number[]
): string {
	const maxWin = Math.max(...cands.map((c) => c.win));
	const weights = cands.map(
		(c, i) => Math.exp((c.win - maxWin) / Math.max(temperature, 0.1)) * (factors?.[i] ?? 1)
	);
	const total = weights.reduce((a, b) => a + b, 0);
	let r = Math.random() * total;
	for (let k = 0; k < cands.length; k++) {
		r -= weights[k];
		if (r <= 0) return cands[k].move;
	}
	return cands[cands.length - 1].move;
}

// ─── The defensive scan: "is my move safe?" ─────────────────────────────────
//
// Observed live (SquareFish-900 on lichess): a missed tactical moment routes
// the choice through an UNCAPPED softmax over the remaining lines, which
// occasionally samples an unprovoked queen-hang. Real 900s miss SUBTLE
// refutations constantly but almost never move a piece onto a square a pawn
// attacks in plain sight — the "is it safe?" check is the scan order applied
// to one's own move. This is its mirror: candidates whose refutation is
// VISIBLE (moved piece immediately capturable by a cheaper attacker, or
// capturable while undefended) get their sampling weight slashed. Subtle
// multi-move refutations keep full weight — falling for those is authentic.
export function dangerVisibility(fen: string, uci: string): number {
	try {
		const c = new Chess(fen);
		const moved = c.move({
			from: uci.slice(0, 2),
			to: uci.slice(2, 4),
			promotion: uci.length > 4 ? uci[4] : undefined
		});
		const dest = moved.to;
		const movedVal = PIECE_VAL[moved.promotion ?? moved.piece];
		// opponent's cheapest immediate capture of the moved piece
		let cheapest = Infinity;
		let canRecapture = false;
		for (const reply of c.moves({ verbose: true })) {
			if (reply.to === dest && reply.captured)
				cheapest = Math.min(cheapest, PIECE_VAL[reply.piece]);
		}
		if (cheapest === Infinity) return 1; // not capturable at all
		// is the moved piece defended? (any of OUR replies recaptures on dest)
		const probe = new Chess(c.fen());
		const attacker = probe
			.moves({ verbose: true })
			.find((m) => m.to === dest && m.captured);
		if (attacker) {
			probe.move(attacker);
			canRecapture = probe.moves({ verbose: true }).some((m) => m.to === dest && m.captured);
		}
		// glaring: taken by a cheaper piece (queen to a pawn-covered square), or
		// taken for free (undefended). Even trades and defended pieces are fine.
		if (cheapest < movedVal - 1) return 0.05;
		if (!canRecapture && movedVal >= 3) return 0.1;
		return 1;
	} catch {
		return 1;
	}
}

export interface DecisionTrace {
	branch: 'tactical-miss' | 'tactical-seen' | 'quiet' | 'conversion' | 'only-move';
	bestMove: string;
	bestWin: number;
	playedMove: string;
	playedWin: number;
	candidates: number;
	temperature: number;
	missProb?: number;
	effectiveP?: number;
	roll?: number;
	visKind?: string;
	visMult?: number;
	openingDamp?: number;
	quietWindow?: number;
}

export function shapedBotMoveTraced(
	lines: EngineMove[],
	elo: number,
	params?: Partial<ShapedParams>,
	seed?: string | number,
	fen?: string,
	discoveryDepth?: number,
	lastMoveTo?: string
): { move: string; trace: DecisionTrace } | null {
	if (lines.length === 0) return null;
	const sorted = [...lines].sort((a, b) => a.multipv - b.multipv);
	const best = sorted[0];
	const wins = sorted.map(moveWin);
	const bestWin = wins[0];

	function result(move: string, branch: DecisionTrace['branch'], extra: Partial<DecisionTrace> = {}): { move: string; trace: DecisionTrace } {
		const playedIdx = sorted.findIndex((l) => l.pv[0] === move);
		return {
			move,
			trace: {
				branch,
				bestMove: best.pv[0],
				bestWin: Math.round(bestWin),
				playedMove: move,
				playedWin: Math.round(playedIdx >= 0 ? wins[playedIdx] : bestWin),
				candidates: sorted.length,
				temperature: 0,
				...extra
			}
		};
	}

	if (sorted.length === 1) return result(best.pv[0], 'only-move');

	const { missProb, tacticalGapPct, temperature, quietWindowPct, scan, scanMults } = {
		...shapedParams(elo),
		...params
	};
	const scanning = !!scan && !!fen;
	const skill = scanning ? scanSkill(elo) : 1;
	const damp = scanning ? bySkill(openingDamp(fen!), skill) : 1;

	let missedVisibleBest = false;
	let preGateVis: TacticVisibility | undefined;
	let preGateP: number | undefined;
	let preGateRoll: number | undefined;
	if (scanning) {
		const mults = { ...SCAN_MULTS, ...scanMults };
		const vis = tacticVisibility(fen!, best.pv, best.mate, discoveryDepth, mults, lastMoveTo);
		if (vis.kind === 'recapture' || vis.kind === 'grab') {
			const s = vis.kind === 'recapture' ? Math.max(skill, 0.7) : skill;
			const p = Math.min(missProb * bySkill(vis.multiplier, s) * damp, mults.pCap);
			const roll = seed !== undefined ? hash01(`${seed}:${best.pv[0].slice(2, 4)}`) : Math.random();
			preGateVis = vis;
			preGateP = p;
			preGateRoll = roll;
			if (roll >= p) return result(best.pv[0], 'tactical-seen', {
				missProb, effectiveP: p, roll, visKind: vis.kind, visMult: vis.multiplier, openingDamp: damp, temperature
			});
			missedVisibleBest = true;
		}
	}

	if (bestWin >= 90 && wins[1] >= 85) {
		const cands: { move: string; win: number }[] = [];
		for (let i = 0; i < sorted.length; i++) {
			if (i === 0 && missedVisibleBest) continue;
			if (wins[i] < 85) continue;
			const l = sorted[i];
			const v = l.mate !== null && l.mate > 0 ? 25 - Math.min(l.mate, 15) : l.score;
			cands.push({ move: l.pv[0], win: v });
		}
		if (cands.length > 0) {
			const move = softmaxPick(
				cands,
				temperature / 4,
				scanning ? cands.map((c) => bySkill(dangerVisibility(fen!, c.move), skill)) : undefined
			);
			return result(move, 'conversion', { candidates: cands.length, temperature: temperature / 4, openingDamp: damp });
		}
	}

	if (bestWin - wins[1] >= tacticalGapPct) {
		if (!missedVisibleBest) {
			const mateSoon = best.mate !== null && best.mate > 0 && best.mate <= 2;
			let p = mateSoon ? missProb * 0.25 : missProb;
			let visKind = mateSoon ? 'mate-soon' : 'flat';
			let visMult = mateSoon ? 0.25 : 1;
			if (scanning) {
				const mults = { ...SCAN_MULTS, ...scanMults };
				const vis = tacticVisibility(fen!, best.pv, best.mate, discoveryDepth, mults, lastMoveTo);
				const s = vis.kind === 'recapture' ? Math.max(skill, 0.7) : skill;
				p = missProb * bySkill(vis.multiplier, s) * damp;
				p = Math.min(p, mults.pCap);
				visKind = vis.kind;
				visMult = vis.multiplier;
			}
			const roll = seed !== undefined ? hash01(`${seed}:${best.pv[0].slice(2, 4)}`) : Math.random();
			if (roll >= p) return result(best.pv[0], 'tactical-seen', {
				missProb, effectiveP: p, roll, visKind, visMult, openingDamp: damp, temperature
			});
			// missed — fall through to sample the rest
			const rest = sorted.slice(1).map((l, i) => ({ move: l.pv[0], win: wins[i + 1] }));
			const move = softmaxPick(
				rest,
				temperature,
				scanning ? rest.map((c) => bySkill(dangerVisibility(fen!, c.move), skill)) : undefined
			);
			return result(move, 'tactical-miss', {
				missProb, effectiveP: p, roll, visKind, visMult,
				openingDamp: damp, temperature, candidates: rest.length
			});
		}
		// pre-gate miss (grab/recapture) — sample the rest via tactical miss path
		const rest = sorted.slice(1).map((l, i) => ({ move: l.pv[0], win: wins[i + 1] }));
		const move = softmaxPick(
			rest,
			temperature,
			scanning ? rest.map((c) => bySkill(dangerVisibility(fen!, c.move), skill)) : undefined
		);
		return result(move, 'tactical-miss', {
			missProb, effectiveP: preGateP, roll: preGateRoll,
			visKind: preGateVis?.kind, visMult: preGateVis?.multiplier,
			openingDamp: damp, temperature, candidates: rest.length
		});
	}

	// Quiet
	const cands: { move: string; win: number }[] = [];
	for (let i = 0; i < sorted.length; i++) {
		if (i === 0 && missedVisibleBest) continue;
		if (bestWin - wins[i] <= quietWindowPct) cands.push({ move: sorted[i].pv[0], win: wins[i] });
	}
	if (cands.length === 0) {
		const move = sorted[1].pv[0];
		return result(move, 'quiet', { candidates: 1, temperature: temperature * damp, quietWindow: quietWindowPct, openingDamp: damp });
	}
	const move = softmaxPick(
		cands,
		temperature * damp,
		scanning ? cands.map((c) => bySkill(dangerVisibility(fen!, c.move), skill)) : undefined
	);
	return result(move, 'quiet', { candidates: cands.length, temperature: temperature * damp, quietWindow: quietWindowPct, openingDamp: damp });
}

export function shapedBotMove(
	lines: EngineMove[],
	elo: number,
	params?: Partial<ShapedParams>,
	seed?: string | number,
	fen?: string,
	discoveryDepth?: number,
	lastMoveTo?: string
): string | null {
	return shapedBotMoveTraced(lines, elo, params, seed, fen, discoveryDepth, lastMoveTo)?.move ?? null;
}

// ─── v4 (scan model) knots ───────────────────────────────────────────────────
//
// Same grid, same honest rulers, shapedBotMove in scan mode (n=50 wasm with
// n=200 kink probes merged; n=100 native). data/bot-shaped-scan-calib.json /
// data/bot-shaped-scan-native-calib.json, both rebased ucielo:1320 = 1320.
// The substrates agree within noise through label 1200 (choice layer
// dominates the backbone, as in v3); the native top runs cooler because the
// big-net engine is far more drawish at near-parity (79/100 draws in
// 1050-vs-ruler — see the W/D/L columns in the gym output).
// The wasm floor reaches internal ~673 ≈ display ~430: scanSkill fades the
// visibility discounts below 900, so sub-600 labels stay meaningful.
const SHAPED_KNOTS_SCAN: Record<Substrate, { label: number; strength: number }[]> = {
	// v4.1 (saturated-loss fix INCLUDED — the fix measured +140-220 across the
	// ladder vs the honest ruler; the earlier 'calibration-neutral' claim was
	// falsified by the imitation-experiment's control pair, 2026-07-17).
	// Fresh grid, n=100 everywhere. Floor note: label-600 measures 891
	// internal ≈ display ~650 — display-600 is currently UNREACHABLE; the
	// pre-gate captures ate scanSkill's restored bottom. Params extension
	// below label 600 is the open fix if the roster wants true 600s back.
	wasm: [
		{ label: 600, strength: 891 },
		{ label: 750, strength: 1051 },
		{ label: 900, strength: 1186 },
		{ label: 1050, strength: 1327 },
		{ label: 1200, strength: 1528 },
		{ label: 1350, strength: 1904 },
		{ label: 1500, strength: 2319 }
	],
	// STALE (v4.0): the native grid predates the saturated-loss fix; desktop
	// Squares will play above label until the native re-grid runs. Web ships
	// from the wasm table; re-measure before any Tauri release.
	native: [
		{ label: 600, strength: 753 },
		{ label: 750, strength: 844 },
		{ label: 900, strength: 1024 },
		{ label: 1050, strength: 1229 },
		{ label: 1200, strength: 1417 },
		{ label: 1350, strength: 1650 },
		{ label: 1500, strength: 1900 }
	]
};

/** Which choice-layer generation the app's Squares run. Flip to 'scan' to
 *  ship v4: square() picks labels off the scan knots and the app passes
 *  scan params + position at move time. The deployed SquareFish is pinned
 *  by its own env (label 1015 --scan) and ignores this. */
export const BOT_MODEL: 'v3' | 'scan' = 'scan'; // v4 shipped 2026-07-16

export type ShapedModel = 'v3' | 'scan';

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
export function shapedStrengthRange(
	substrate: Substrate = getBotSubstrate(),
	model: ShapedModel = BOT_MODEL
): {
	min: number;
	max: number;
} {
	const k = (model === 'scan' ? SHAPED_KNOTS_SCAN : SHAPED_KNOTS)[substrate];
	return { min: k[0].strength, max: k[k.length - 1].strength };
}

/** Invert the measured curve: target strength on our scale → shaped label. */
export function shapedLabelFor(
	targetElo: number,
	substrate: Substrate = getBotSubstrate(),
	model: ShapedModel = BOT_MODEL
): number {
	const k = (model === 'scan' ? SHAPED_KNOTS_SCAN : SHAPED_KNOTS)[substrate];
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
