// The skill report's user-side computation (#268): the same axes the peer
// pipeline aggregates, computed over the player's own archive, BY THE SAME
// RULES. Every constant here mirrors pipeline/lichess/aggregate.mjs and
// extract.mjs, and report.test.ts pins the parity on a shared synthetic game
// — if the two walks ever disagree about a number, the comparison the report
// draws is between two different quantities and the whole screen lies.
//
// The one deliberate divergence is PERSPECTIVE, and it is a trap: lichess
// dumps carry white-POV evals, so the pipeline flips by mover color; OUR
// stored moves carry MOVER-POV evals (see itemDataFromStoredMove), so this
// walk negates the PREVIOUS ply's eval instead — the previous mover was the
// opponent. The parity test feeds both encodings of one game and demands
// identical output.
//
// Also deliberate: per-move `wcDrop` stored on the archive is NOT used. On
// live-graded games it measures the drop against the engine's BEST move —
// a different quantity from the tables' consecutive-eval drop — and on
// lichess imports it happens to be the consecutive-eval form already
// (lichessImport.ts computes exactly that). One field, two provenances
// ([[stored-move-provenance]]'s recurring class); recomputing here applies
// ONE rule to every population instead of trusting a field that means
// different things by writer.
import { winChance } from './engine/insights';
import { isEndgamePosition } from './engine/phase';
import { clocksFromPgn } from './gameStore';

export interface ReportMove {
	color: 'w' | 'b';
	/** MOVER-perspective, like every stored move in the archive. */
	evalPawns: number | null;
	mate: number | null;
	fenBefore?: string;
	san?: string;
	// The tactics axis (reportTactics.ts) reads four more optional fields; the
	// walk below never does. All genuinely optional: absent means the writer
	// recorded nothing, and the selector treats that as "nobody looked".
	uci?: string;
	bestUci?: string;
	bestMate?: number | null;
	topRecorded?: boolean;
}

export interface ReportGame {
	botColor?: 'w' | 'b' | null;
	botBothSides?: boolean;
	pgn?: string;
	moves: ReportMove[];
	// Assistance provenance, read by the tactics axis (reportTactics.ts): a
	// game where engine arrows were on screen, a takeback replayed the scored
	// move, or refuse-blunders retried it does not measure FINDING anything.
	// Optional — absent (imports) means no assistance was possible.
	botHintsUsed?: boolean;
	botUndos?: number;
	refusedMoves?: number;
}

// ---- mirrors of the pipeline's constants (aggregate.mjs / extract.mjs) ----
const START_EVAL_PAWNS = 0.15; // white-POV nominal start eval
const WINNING_THRESHOLD = 70;
const LOSING_THRESHOLD = 30;
const BLUNDER_WC_DROP = 20;
/** panic = under 30s remaining BEFORE the move; calm = 60s or more. The
 *  10-30s / 30-60s seam between them stays out of both, matching how the
 *  peer side combines its buckets (report reader does the same sums). */
const PANIC_MAX_S = 30;
const CALM_MIN_S = 60;
const UNDER2S_S = 2;

/** The TimeControl header as {initialS, incrementS}, or null. The increment
 *  is OPTIONAL: lichess writes "180+2" but chess.com writes a bare "600" for
 *  a zero-increment control (their fixture in chesscomCore.test.ts is the
 *  witness, and pgn_import.dart has always read the bare form) — requiring
 *  the "+" silently dropped every chess.com game into noClass (#293 review).
 *  Daily/correspondence forms ("1/86400", "-") stay null. */
export function timeControlOfPgn(
	pgn: string | undefined
): { initialS: number; incrementS: number } | null {
	if (!pgn) return null;
	const m = /^\[TimeControl "(\d+)(?:\+(\d+))?"\]/m.exec(pgn);
	if (!m) return null;
	return { initialS: Number(m[1]), incrementS: Number(m[2] ?? 0) };
}

export function timeClassOfPgn(pgn: string | undefined): string | null {
	const tc = timeControlOfPgn(pgn);
	if (!tc) return null;
	const estimate = tc.initialS + 40 * tc.incrementS;
	// extract.mjs classifyTimeClass, verbatim
	if (estimate < 30) return 'ultrabullet';
	if (estimate < 180) return 'bullet';
	if (estimate < 480) return 'blitz';
	if (estimate < 1500) return 'rapid';
	return 'classical';
}

interface DropAcc {
	n: number;
	sum: number;
	blunders: number;
}
const acc = (): DropAcc => ({ n: 0, sum: 0, blunders: 0 });
function push(a: DropAcc, drop: number) {
	a.n += 1;
	a.sum += drop;
	if (drop >= BLUNDER_WC_DROP) a.blunders += 1;
}
function out(a: DropAcc) {
	return {
		n: a.n,
		mean: a.n ? a.sum / a.n : null,
		blunderRate: a.n ? a.blunders / a.n : null
	};
}

/**
 * The user's own axis numbers over [games], restricted to [timeClass] so the
 * peer cell and the user population describe the same kind of chess. Games
 * without a human side, of another class, or with no readable TimeControl
 * are EXCLUDED AND COUNTED — the report renders those counts; silence about
 * the population is how a number starts lying.
 */
export function skillReportUser(
	games: ReportGame[],
	timeClass: 'blitz' | 'rapid' | 'classical'
) {
	const winning = acc();
	const losing = acc();
	const endgame = acc();
	const time = {
		panic: { n: 0, blunders: 0 },
		calm: { n: 0, blunders: 0 },
		clockedMoves: 0,
		under2s: 0,
		thinkSum: 0
	};
	const excluded = { humanless: 0, otherClass: 0, noClass: 0 };
	let considered = 0;

	for (const g of games) {
		const human = g.botBothSides ? null : g.botColor === 'w' ? 'b' : g.botColor === 'b' ? 'w' : null;
		if (!human) {
			excluded.humanless += 1;
			continue;
		}
		const cls = timeClassOfPgn(g.pgn);
		if (cls === null) {
			excluded.noClass += 1;
			continue;
		}
		if (cls !== timeClass) {
			excluded.otherClass += 1;
			continue;
		}
		considered += 1;

		const clocks = g.pgn ? clocksFromPgn(g.pgn) : [];
		const incrementS = timeControlOfPgn(g.pgn)?.incrementS ?? 0;
		// Seeded NULL, not with the header's initial: a side's first move
		// contributes nothing to the clock walk. Seeding from the header
		// booked `increment` phantom seconds on every first move (lichess
		// grants none there) and swallowed a berserked game's halved clock
		// whole — the same #293 finding as the pipeline's haveClk rule, which
		// this mirrors; pgn_import.dart states it as "the first move of each
		// side gets nothing".
		const prevClkS: Record<string, number | null> = { w: null, b: null };

		// prevEvalMover: the PREVIOUS ply's eval in ITS OWN mover's
		// perspective (or the white-POV start for ply 1, which is the same
		// thing for White and negated below for a hypothetical Black start).
		let prevPawns: number | null = START_EVAL_PAWNS;
		let prevMate: number | null = null;
		let prevWasStart = true;
		// STICKY, like the pipeline's `m.ply >= egPly`: a promotion can raise
		// the majors+minors count back above six mid-endgame, and a per-ply
		// test dropped exactly those plies while T5 kept them — same
		// predicate, different application, silently incomparable (#293
		// review, run-proven divergence).
		let inEndgame = false;

		for (let i = 0; i < g.moves.length; i++) {
			const m = g.moves[i];
			const mine = m.color === human;
			if (!inEndgame && m.fenBefore && isEndgamePosition(m.fenBefore)) {
				inEndgame = true;
			}

			// eval after this move, mover POV; checkmate closes without a
			// number, exactly as the pipeline scores it
			let afterPawns = m.evalPawns;
			let afterMate = m.mate;
			if (afterPawns === null && afterMate === null && m.san?.endsWith('#')) {
				afterMate = 1; // mover POV: the mover just won
			}
			const hasAfter = afterPawns !== null || afterMate !== null;
			const hasBefore = prevPawns !== null || prevMate !== null;

			if (mine && hasBefore && hasAfter) {
				// The previous eval belongs to the opponent's move (mover POV),
				// so flip — at the WIN% level, exactly as the pipeline's
				// moverWinChance does, never by negating the mate NUMBER:
				// winChance is not antisymmetric at mate === 0, and the two
				// flips diverge exactly there (#293 review). The white-POV
				// start eval flips only for a Black mover.
				const wcPrev = winChance(prevPawns, prevMate);
				const flip = prevWasStart ? m.color === 'b' : true;
				const before = flip ? 100 - wcPrev : wcPrev;
				const after = winChance(afterPawns, afterMate);
				const drop = Math.max(0, before - after);

				if (before >= WINNING_THRESHOLD) push(winning, drop);
				else if (before <= LOSING_THRESHOLD) push(losing, drop);
				if (inEndgame) push(endgame, drop);

				const beforeClkS = prevClkS[m.color];
				if (beforeClkS !== null && clocks[i] !== null && clocks[i] !== undefined) {
					if (beforeClkS < PANIC_MAX_S) {
						time.panic.n += 1;
						if (drop >= BLUNDER_WC_DROP) time.panic.blunders += 1;
					} else if (beforeClkS >= CALM_MIN_S) {
						time.calm.n += 1;
						if (drop >= BLUNDER_WC_DROP) time.calm.blunders += 1;
					}
				}
			}

			// the clock walk runs for BOTH colors — think time needs each
			// side's own previous remaining-clock, human or not
			const clkMs = clocks[i];
			if (clkMs !== null && clkMs !== undefined) {
				const beforeS = prevClkS[m.color];
				if (mine && beforeS !== null) {
					const thinkS = Math.max(0, beforeS - clkMs / 1000 + incrementS);
					time.clockedMoves += 1;
					time.thinkSum += thinkS;
					if (thinkS < UNDER2S_S) time.under2s += 1;
				}
				prevClkS[m.color] = clkMs / 1000;
			} else {
				prevClkS[m.color] = null; // a gap poisons the running clock
			}

			prevPawns = hasAfter ? afterPawns : null;
			prevMate = hasAfter ? afterMate : null;
			prevWasStart = false;
		}
	}

	return {
		timeClass,
		games: { considered, ...excluded },
		winning: out(winning),
		losing: out(losing),
		endgame: out(endgame),
		time: {
			clockedMoves: time.clockedMoves,
			under2sShare: time.clockedMoves ? time.under2s / time.clockedMoves : null,
			meanThinkS: time.clockedMoves ? time.thinkSum / time.clockedMoves : null,
			panic: {
				n: time.panic.n,
				pBlunder: time.panic.n ? time.panic.blunders / time.panic.n : null
			},
			calm: {
				n: time.calm.n,
				pBlunder: time.calm.n ? time.calm.blunders / time.calm.n : null
			}
		}
	};
}

/**
 * The peer cell for [band]×[timeClass], reshaped to sit beside
 * [skillReportUser]'s output: the same panic/calm bucket sums, the same
 * field names. Null when the tables hold no such cell — the report says
 * "no baseline", never invents one.
 */
export function skillReportPeer(tables: any, band: number, timeClass: string) {
	const cell = tables?.bands?.[String(band)]?.[timeClass];
	if (!cell) return null;
	const sumBuckets = (labels: string[]) => {
		let n = 0;
		let blunders = 0;
		for (const l of labels) {
			const b = cell.t2?.blunderByClockBucket?.[l];
			if (b) {
				n += b.n;
				// an empty bucket is emitted as {n: 0} with NO blunders key —
				// truthy, and `+= undefined` NaN-poisons the whole sum (#293
				// review; latent until the tables are regenerated sparser)
				blunders += b.blunders ?? 0;
			}
		}
		return { n, pBlunder: n ? blunders / n : null };
	};
	return {
		winning: cell.t3 ?? null,
		losing: cell.t4 ?? null,
		endgame: cell.t5 ?? null,
		time: {
			under2sShare: cell.t1?.under2s?.fraction ?? null,
			panic: sumBuckets(['0-5s', '5-10s', '10-30s']),
			calm: sumBuckets(['60-120s', '120-300s', '300s+'])
		},
		bookPlyDeciles: cell.t6?.plyOfFirstDeviation?.deciles ?? null
	};
}
