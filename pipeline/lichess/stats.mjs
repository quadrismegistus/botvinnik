// Distribution bookkeeping shared by every table: "distributions stored as
// deciles + n" (README). Keeps raw samples and sorts once at finalize time —
// fine at dev scale (a month's worth of one band×class cell); a production
// run trades this for a streaming quantile sketch, a deliberate scope cut
// for the skeleton (a production month is explicitly "an explicit,
// supervised step" per the README, not something this pipeline is tuned for
// yet).
export class Samples {
	constructor() {
		/** @type {number[]} */
		this.values = [];
	}

	push(v) {
		this.values.push(v);
	}

	get n() {
		return this.values.length;
	}

	mean() {
		if (this.values.length === 0) return null;
		return this.values.reduce((a, b) => a + b, 0) / this.values.length;
	}

	/** 10th, 20th, ..., 90th percentile, linear interpolation (numpy's
	 *  default "linear" method). Null when there are no samples. */
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
