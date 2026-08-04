// Samples must hold FIXED memory at production scale: the dev dump had no
// clocks, so the skeleton's keep-every-value arrays were never exercised
// against a real month — which pushes billions of think-time samples through
// T1 and would OOM long before the end. The reservoir keeps n and mean
// exact, deciles unbiased, and the whole run reproducible (seeded stream,
// same input order → byte-identical tables).
import { describe, expect, it } from 'vitest';
import { RESERVOIR_CAP, resetRandForTest, Samples } from './stats.mjs';

describe('Samples (reservoir)', () => {
	it('below capacity it IS the old exact behavior', () => {
		const s = new Samples();
		for (const v of [5, 1, 3]) s.push(v);
		expect(s.n).toBe(3);
		expect(s.mean()).toBeCloseTo(3, 10);
		const d = s.deciles()!;
		expect(d[0]).toBeCloseTo(1.4, 10); // numpy-linear p10 of [1,3,5]
		expect(d[8]).toBeCloseTo(4.6, 10);
	});

	it('memory is bounded and n/mean stay exact past capacity', () => {
		const s = new Samples();
		const total = RESERVOIR_CAP * 5;
		let sum = 0;
		for (let i = 0; i < total; i++) {
			s.push(i);
			sum += i;
		}
		expect(s.n).toBe(total);
		expect(s.values.length).toBeLessThanOrEqual(RESERVOIR_CAP);
		expect(s.mean()).toBeCloseTo(sum / total, 6);
	});

	it('deciles of a large uniform stream land near the truth', () => {
		const s = new Samples();
		const total = RESERVOIR_CAP * 10;
		for (let i = 0; i < total; i++) s.push(i / total);
		const d = s.deciles()!;
		for (let p = 1; p <= 9; p++) {
			expect(Math.abs(d[p - 1] - p / 10)).toBeLessThan(0.02);
		}
	});

	it('two identical runs produce identical reservoirs — tables must be reproducible', () => {
		// One shared seeded stream: the guarantee is per-RUN (same dump, same
		// order → byte-identical tables), so the comparison resets the stream
		// between fills the way a rerun of the pipeline starts it fresh.
		const fill = () => {
			resetRandForTest();
			const s = new Samples();
			for (let i = 0; i < RESERVOIR_CAP * 3; i++) s.push(i % 977);
			return s;
		};
		const a = fill();
		const b = fill();
		expect(a.values).toEqual(b.values);
		expect(a.deciles()).toEqual(b.deciles());
	});
});
