// Distribution bookkeeping shared by every table: "distributions stored as
// deciles + n" (README).
//
// A RESERVOIR, not a keep-every-value array — the scar is specific: the
// skeleton kept raw arrays, was validated on the 2013 dev dump, and 2013
// predates %clk, so the arrays were never exercised against clock data. A
// real month pushes billions of think-time samples through T1's per-bucket
// distributions; the raw arrays OOM long before the end, and the dev run's
// 188MB peak said nothing about it. n and mean stay EXACT (running count and
// sum); deciles come from a uniform reservoir (Algorithm R), which is
// unbiased and, at this capacity, well inside the tolerance any table cell
// carries anyway.
//
// Seeded, shared PRNG rather than Math.random: these tables are a
// MEASUREMENT artifact, and a rerun of the same dump must reproduce them
// byte-for-byte or a diff of two runs means nothing.
export const RESERVOIR_CAP = 20000;

// Mulberry32 — small, fast, good enough for reservoir indices; one shared
// stream keeps runs reproducible for identical input order.
let _seed = 0x268aa77;
function rand() {
	_seed |= 0;
	_seed = (_seed + 0x6d2b79f5) | 0;
	let t = Math.imul(_seed ^ (_seed >>> 15), 1 | _seed);
	t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

/** Test seam: reset the shared stream so ordering-sensitive assertions can
 *  compare two logically identical runs. The pipeline never calls this. */
export function resetRandForTest(seed = 0x268aa77) {
	_seed = seed;
}

export class Samples {
	constructor() {
		/** @type {number[]} */
		this.values = [];
		this._n = 0;
		this._sum = 0;
	}

	push(v) {
		this._n += 1;
		this._sum += v;
		if (this.values.length < RESERVOIR_CAP) {
			this.values.push(v);
			return;
		}
		// Algorithm R: keep each of the n seen values with probability cap/n.
		const j = Math.floor(rand() * this._n);
		if (j < RESERVOIR_CAP) this.values[j] = v;
	}

	get n() {
		return this._n;
	}

	mean() {
		if (this._n === 0) return null;
		return this._sum / this._n;
	}

	/** 10th, 20th, ..., 90th percentile over the reservoir, linear
	 *  interpolation (numpy's default "linear" method). Exact below capacity
	 *  — the reservoir IS the data there. Null when there are no samples. */
	deciles() {
		if (this.values.length === 0) return null;
		const sorted = [...this.values].sort((a, b) => a - b);
		const out = [];
		for (let p = 1; p <= 9; p++) {
			const idx = (p / 10) * (sorted.length - 1);
			const lo = Math.floor(idx);
			const hi = Math.ceil(idx);
			const frac = idx - lo;
			out.push(sorted[lo] + (sorted[hi] - sorted[lo]) * frac);
		}
		return out;
	}
}
