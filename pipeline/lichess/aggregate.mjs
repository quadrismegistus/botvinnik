// The band × time-class accumulator: T1 (time-allocation), T2
// (clock-pressure), T3 (while-winning retention), T4 (while-losing
// composure), and the book-ply half of T6. T5 and T7 are stubs — both are
// blocked on the brain exporting a phase function / motif-detector sampling
// budget it does not have yet (README).
//
// All win-chance math goes through brain.winChance (loaded via loadBrain.mjs)
// — the commensurability invariant. Nothing here reimplements the sigmoid;
// the only local logic is bookkeeping: which side is "the mover", which cell
// a move belongs to, and how a raw sample turns into a decile+n envelope.
import { Samples } from './stats.mjs';
import { plyOfFirstDeviation } from './book.mjs';

export const BAND_MIN = 800;
export const BAND_MAX = 2600;
export const BAND_STEP = 100;
export const TIME_CLASSES = ['blitz', 'rapid', 'classical'];

/** T5's default per-cell budget of per-side game contributions. Replays are
 *  bounded by cap / endgame-rate (~2-3× the cap in games), a few minutes of
 *  chess.js per production month. */
export const T5_SAMPLE_CAP = 2000;

/** Lichess rating band a game-Elo falls into — 800-2600 step 100, open-ended
 *  tails (README: "do not bake any [rating-scale] conversion into the
 *  tables" — this is the lichess-native band, not a cross-scale mapping). */
export function bandFor(elo) {
	if (!Number.isFinite(elo)) return null;
	const clamped = Math.max(BAND_MIN, Math.min(BAND_MAX, elo));
	return Math.floor(clamped / BAND_STEP) * BAND_STEP;
}

// Remaining-clock buckets shared by T1 (time-allocation) and T2
// (clock-pressure). Provisional boundaries — not yet calibrated against a
// real population — chosen so the 30s cut lines up with T2's headline claim
// ("you collapse under 30 seconds", README).
export const CLOCK_BUCKETS = [
	{ label: '0-5s', lo: 0, hi: 5 },
	{ label: '5-10s', lo: 5, hi: 10 },
	{ label: '10-30s', lo: 10, hi: 30 },
	{ label: '30-60s', lo: 30, hi: 60 },
	{ label: '60-120s', lo: 60, hi: 120 },
	{ label: '120-300s', lo: 120, hi: 300 },
	{ label: '300s+', lo: 300, hi: Infinity }
];

export function clockBucketLabel(seconds) {
	for (const b of CLOCK_BUCKETS) {
		if (seconds >= b.lo && seconds < b.hi) return b.label;
	}
	return CLOCK_BUCKETS[CLOCK_BUCKETS.length - 1].label;
}

// T1 ply buckets: opening / middlegame-by-ply / late (README). Static ply
// cuts, not the brain's phase function — T5 is the table that's explicitly
// blocked pending that export; T1 only needed a coarse split and does not
// wait on it.
export const OPENING_PLY_MAX = 10;
export const LATE_PLY_MIN = 61;

function plyBucket(ply) {
	if (ply <= OPENING_PLY_MAX) return 'opening';
	if (ply >= LATE_PLY_MIN) return 'late';
	return 'middlegame';
}

// lichess's nominal start-of-game eval, White POV — mirrors
// brain/lichessImport.ts's START_EVAL (`{ eval: 15 }` centipawns) exactly,
// for the same reason it exists there: ply 1 has no "previous move" to read
// a before-state off, so the pipeline needs the same nominal anchor the
// app's own lichess-import grading uses, or ply-1 wcDrops would not be
// comparable to the app's.
const START_EVAL = { pawns: 0.15, mate: null };

/** White-POV win% for an `{ pawns, mate }` eval entry (both fields as
 *  extract.mjs stores them: White POV, one of the two set). Null in, null
 *  out. brain.winChance is perspective-agnostic — it returns win% FOR
 *  whichever side the input score is scored from — so a White-POV score in
 *  gives a White-POV win% out. */
export function whiteWinChance(brain, evalEntry) {
	if (!evalEntry) return null;
	return brain.winChance(evalEntry.pawns, evalEntry.mate);
}

/** Flip a White-POV win% to the mover's own POV — the sign convention pinned
 *  by brain/gameStore.ts's gameAccuracy (`last = m.color === 'w' ? wc : 100 -
 *  wc`) and brain/lichessImport.ts's wcWhite/moverBefore/moverAfter, which
 *  this function mirrors move-for-move. */
export function moverWinChance(brain, evalEntry, color) {
	const wcWhite = whiteWinChance(brain, evalEntry);
	if (wcWhite === null) return null;
	return color === 'w' ? wcWhite : 100 - wcWhite;
}

function mateEntryFor(color) {
	// A move whose SAN ends in "#" delivered checkmate; the position right
	// after it is 100% for the side who just moved and 0% for the other,
	// with no eval comment needed to say so (lichess's own dumps frequently
	// omit the eval on the mating move itself — see brain/lichessImport.ts's
	// identical `c.isCheckmate()` special case for the API-analysis path).
	return color === 'w' ? { pawns: null, mate: 1 } : { pawns: null, mate: -1 };
}

const BLUNDER_WC_DROP = 20; // README: "blunder = wcDrop >= 20"
const WINNING_THRESHOLD = 70; // T3: win chance >= 70 for the mover
const LOSING_THRESHOLD = 30; // T4: win chance <= 30 for the mover

class Cell {
	constructor() {
		// T1: think-time share by ply bucket, total think-time for the
		// denominator, and decile think-time per remaining-clock bucket.
		this.t1PlyThink = { opening: 0, late: 0, middlegame: new Map() };
		this.t1PlyN = { opening: 0, late: 0, middlegame: new Map() };
		this.t1TotalThink = 0;
		this.t1TotalN = 0;
		this.t1Under2sCount = 0;
		this.t1ClockBucketSamples = new Map(); // label -> Samples (think time)

		// T2: P(blunder | remaining clock bucket)
		this.t2ClockBucket = new Map(); // label -> { n, blunders }

		// T3 / T4: wcDrop distribution while winning / losing
		this.t3 = new Samples();
		this.t3Blunders = 0;
		this.t4 = new Samples();
		this.t4Blunders = 0;

		// T5: wcDrop distribution over endgame plies (sampled — see addGame)
		this.t5 = new Samples();
		this.t5Blunders = 0;
		this.t5Games = 0; // per-SIDE contributions, like t6's convention

		// T6 (book-ply half): ply of first out-of-book move
		this.t6Deviation = new Samples();
	}

	recordT1(ply, thinkSeconds, clockBucketLabelBefore) {
		const bucket = plyBucket(ply);
		if (bucket === 'middlegame') {
			const prevT = this.t1PlyThink.middlegame.get(ply) ?? 0;
			this.t1PlyThink.middlegame.set(ply, prevT + thinkSeconds);
			const prevN = this.t1PlyN.middlegame.get(ply) ?? 0;
			this.t1PlyN.middlegame.set(ply, prevN + 1);
		} else {
			this.t1PlyThink[bucket] += thinkSeconds;
			this.t1PlyN[bucket] += 1;
		}
		this.t1TotalThink += thinkSeconds;
		this.t1TotalN += 1;
		if (thinkSeconds < 2) this.t1Under2sCount += 1;

		let s = this.t1ClockBucketSamples.get(clockBucketLabelBefore);
		if (!s) {
			s = new Samples();
			this.t1ClockBucketSamples.set(clockBucketLabelBefore, s);
		}
		s.push(thinkSeconds);
	}

	recordT2(clockBucketLabelBefore, wcDrop) {
		let e = this.t2ClockBucket.get(clockBucketLabelBefore);
		if (!e) {
			e = { n: 0, blunders: 0 };
			this.t2ClockBucket.set(clockBucketLabelBefore, e);
		}
		e.n += 1;
		if (wcDrop >= BLUNDER_WC_DROP) e.blunders += 1;
	}

	recordT3(wcDrop) {
		this.t3.push(wcDrop);
		if (wcDrop >= BLUNDER_WC_DROP) this.t3Blunders += 1;
	}

	recordT4(wcDrop) {
		this.t4.push(wcDrop);
		if (wcDrop >= BLUNDER_WC_DROP) this.t4Blunders += 1;
	}

	recordT5(wcDrop) {
		this.t5.push(wcDrop);
		if (wcDrop >= BLUNDER_WC_DROP) this.t5Blunders += 1;
	}

	recordT6(deviationPly) {
		this.t6Deviation.push(deviationPly);
	}
}

export class Aggregator {
	/**
	 * @param {object} brain the loaded brain.js bundle (loadBrain.mjs)
	 * @param {{ root: object, lines: number }} book buildBook() output
	 * @param {{ t5SampleCap?: number }} [opts] T5's per-cell budget of
	 *   per-side game contributions — the one place this pipeline replays a
	 *   board (brain.endgameStartPly), so it is capped and the cap recorded
	 *   in meta rather than silently sampling (README: no silent caps).
	 */
	constructor(brain, book, opts = {}) {
		this.brain = brain;
		this.book = book;
		this.t5SampleCap = opts.t5SampleCap ?? T5_SAMPLE_CAP;
		/** @type {Map<string, Cell>} */
		this.cells = new Map();
	}

	cellFor(band, timeClass) {
		const key = `${band}|${timeClass}`;
		let cell = this.cells.get(key);
		if (!cell) {
			cell = new Cell();
			this.cells.set(key, cell);
		}
		return cell;
	}

	/** @param {ReturnType<import('./extract.mjs').extractGame>} rec a
	 *  successfully-extracted game (rec.skip === null) */
	addGame(rec) {
		const { timeClass, whiteElo, blackElo, moves, initial, increment } = rec;
		const band = { w: bandFor(whiteElo), b: bandFor(blackElo) };
		const cellOf = (color) => (band[color] === null ? null : this.cellFor(band[color], timeClass));

		// ---- T1 / T2: clock-based, one pass tracking each color's own
		// remaining-clock state. `haveClk[color]` is true only when the
		// IMMEDIATELY PRECEDING move of that color also carried a %clk value —
		// a gap (a move with no clk) invalidates the running clock for that
		// color until it reappears, rather than silently computing a
		// think-time against a stale remaining-clock value that predates an
		// unknown amount of untracked play.
		// A side's FIRST move contributes no think time: lichess grants no
		// increment on it, so the seeded-with-initial walk booked exactly
		// `increment` phantom seconds per side per game — and a berserked
		// arena game (halved clock, same header) booked initial/2 as one
		// giant "think" (#293 review, measured: the opening think bucket was
		// up to 95% artifact at 2200/rapid). pgn_import.dart has always
		// stated this rule: "the first move of each side gets nothing".
		const prevClk = { w: initial, b: initial };
		const haveClk = { w: false, b: false };

		// ---- T3 / T4 / T2-blunder: eval-based wcDrop. `prevEval` is NOT
		// per-color — it is "the eval attached to the previous ply, whoever
		// played it", because that is the position the current mover is
		// actually looking at. Seeded with the nominal start-of-game eval for
		// ply 1; a gap resets it to null until an eval reappears, exactly
		// mirroring the clk gap rule above and for the same reason.
		let prevEval = START_EVAL;

		// ---- T5 (endgame): the one place the pipeline touches a board.
		// Decided per SIDE before the loop: a side samples only if its cell
		// still has budget, and the replay runs only when a side wants it AND
		// the game has evals at all — the budget buys data, not replays of
		// games that cannot yield any. Both players in one cell contend for
		// that cell's budget (the fixture pins it).
		const sanMoves = moves.map((m) => m.san);
		const cellW = cellOf('w');
		const cellB = cellOf('b');
		let egPly = null;
		let t5W = false;
		let t5B = false;
		if (moves.some((m) => m.eval)) {
			const wantW = cellW !== null && cellW.t5Games < this.t5SampleCap;
			const wantB = cellB !== null && cellB.t5Games < this.t5SampleCap;
			if (wantW || wantB) egPly = this.brain.endgameStartPly(sanMoves);
			if (egPly !== null) {
				if (wantW) {
					cellW.t5Games += 1;
					t5W = true;
				}
				if (cellB !== null && cellB.t5Games < this.t5SampleCap) {
					cellB.t5Games += 1;
					t5B = true;
				}
			}
		}

		for (const m of moves) {
			const cell = cellOf(m.color);

			// T1 + T2 (clock half)
			let bucketBefore = null;
			if (cell && m.clk !== null && haveClk[m.color]) {
				const before = prevClk[m.color];
				const think = Math.max(0, before - m.clk + increment);
				bucketBefore = clockBucketLabel(before);
				cell.recordT1(m.ply, think, bucketBefore);
			}
			if (m.clk !== null) {
				prevClk[m.color] = m.clk;
				haveClk[m.color] = true;
			} else {
				haveClk[m.color] = false;
			}

			// T3 / T4 / T2 (eval half)
			const afterEval = m.eval ?? (m.san.endsWith('#') ? mateEntryFor(m.color) : null);
			if (cell && prevEval && afterEval) {
				const moverBefore = moverWinChance(this.brain, prevEval, m.color);
				const moverAfter = moverWinChance(this.brain, afterEval, m.color);
				const wcDrop = Math.max(0, moverBefore - moverAfter);

				if (bucketBefore !== null) cell.recordT2(bucketBefore, wcDrop);
				if (moverBefore >= WINNING_THRESHOLD) cell.recordT3(wcDrop);
				else if (moverBefore <= LOSING_THRESHOLD) cell.recordT4(wcDrop);
				if (egPly !== null && m.ply >= egPly && (m.color === 'w' ? t5W : t5B)) {
					cell.recordT5(wcDrop);
				}
			}
			prevEval = afterEval;
		}

		// ---- T6 (book-ply half): one sample per game per side. Both sides
		// of the SAME game share one "how deep did this line go" fact, but
		// each side's own rating band gets its own data point — it's a claim
		// about the games players at that rating play, not about who caused
		// the deviation.
		const deviationPly = plyOfFirstDeviation(this.book, sanMoves);
		if (deviationPly !== null) {
			const cellW = cellOf('w');
			const cellB = cellOf('b');
			if (cellW) cellW.recordT6(deviationPly);
			if (cellB) cellB.recordT6(deviationPly);
		}
	}

	/** @param {{ source: string, brainVersion: number, games: object }} meta */
	toEnvelope(meta) {
		const bands = {};
		for (const [key, cell] of this.cells) {
			const [bandStr, timeClass] = key.split('|');
			bands[bandStr] ??= {};
			bands[bandStr][timeClass] = cellToTables(cell);
		}
		return {
			v: 1,
			source: meta.source,
			generatedAt: new Date().toISOString(),
			brainVersion: meta.brainVersion,
			meta: {
				analysedOnly: ['t2', 't3', 't4', 't5'],
				// t7 is STRUCK, not deferred: the dumps' [%eval] comments carry
				// no best move or variation, so "the best line carries a
				// tactical motif" is uncomputable from this source. Tactics'
				// peer column is Maia-3's per-position P_R(bestUci) at report
				// time (README).
				struck: ['t7'],
				partial: {
					t6: 'out-of-book-ply only; the plies-1-12 wcDrop distribution sub-table is deferred (see README T6 / task scope)'
				},
				caps: { t5: this.t5SampleCap },
				plyBuckets: { openingMax: OPENING_PLY_MAX, lateMin: LATE_PLY_MIN },
				clockBuckets: CLOCK_BUCKETS.map((b) => b.label),
				bookLines: this.book.lines,
				games: meta.games
			},
			bands
		};
	}
}

function shareTable(cell) {
	const total = cell.t1TotalThink;
	const share = (t) => (total > 0 ? t / total : null);
	const middlegameByPly = {};
	for (const [ply, think] of cell.t1PlyThink.middlegame) {
		middlegameByPly[ply] = { share: share(think), n: cell.t1PlyN.middlegame.get(ply) };
	}
	return {
		opening: { share: share(cell.t1PlyThink.opening), n: cell.t1PlyN.opening },
		late: { share: share(cell.t1PlyThink.late), n: cell.t1PlyN.late },
		middlegameByPly
	};
}

function clockBucketDistributions(samplesByLabel) {
	const out = {};
	for (const b of CLOCK_BUCKETS) {
		const s = samplesByLabel.get(b.label);
		out[b.label] = s ? { n: s.n, medianDecile: s.deciles(), mean: s.mean() } : { n: 0 };
	}
	return out;
}

function t1Table(cell) {
	return {
		n: cell.t1TotalN,
		plyShare: shareTable(cell),
		thinkTimeByClockBucket: clockBucketDistributions(cell.t1ClockBucketSamples),
		under2s: {
			n: cell.t1TotalN,
			fraction: cell.t1TotalN > 0 ? cell.t1Under2sCount / cell.t1TotalN : null
		}
	};
}

function t2Table(cell) {
	const byBucket = {};
	let n = 0;
	for (const b of CLOCK_BUCKETS) {
		const e = cell.t2ClockBucket.get(b.label);
		if (e) {
			byBucket[b.label] = { n: e.n, blunders: e.blunders, pBlunder: e.blunders / e.n };
			n += e.n;
		} else {
			byBucket[b.label] = { n: 0 };
		}
	}
	return { n, blunderByClockBucket: byBucket };
}

function retentionTable(samples, blunders) {
	return {
		n: samples.n,
		mean: samples.mean(),
		blunderRate: samples.n > 0 ? blunders / samples.n : null,
		deciles: samples.deciles()
	};
}

function t6Table(cell) {
	return {
		n: cell.t6Deviation.n,
		plyOfFirstDeviation: { n: cell.t6Deviation.n, deciles: cell.t6Deviation.deciles() },
		note: 'out-of-book-ply only; see meta.partial.t6'
	};
}

function cellToTables(cell) {
	return {
		t1: t1Table(cell),
		t2: t2Table(cell),
		t3: retentionTable(cell.t3, cell.t3Blunders),
		t4: retentionTable(cell.t4, cell.t4Blunders),
		t5: { ...retentionTable(cell.t5, cell.t5Blunders), games: cell.t5Games },
		t6: t6Table(cell)
		// no t7 — struck (see meta.struck and README)
	};
}
