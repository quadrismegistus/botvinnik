import { describe, expect, it } from 'vitest';
import { BOT_ELO_MAX, botSpec, samplerAlphaFor, specToRecipe, parseSpec } from './botRecipe';

describe('botSpec (calibrated mapping)', () => {
	it('hits the measured knots exactly', () => {
		expect(samplerAlphaFor(848)).toBeCloseTo(0.7, 5);
		expect(samplerAlphaFor(1638)).toBeCloseTo(2, 5);
		expect(samplerAlphaFor(2022)).toBeCloseTo(4, 5);
	});

	it('alpha grows monotonically with requested ELO', () => {
		let prev = 0;
		for (let e = 100; e <= 2100; e += 50) {
			const a = samplerAlphaFor(e);
			expect(a).toBeGreaterThan(prev);
			prev = a;
		}
	});

	it('uses the sampler up to the seam, UCI_Elo above it', () => {
		expect(botSpec(1500).kind).toBe('sampler'); // the old coverage hole
		expect(botSpec(2100).kind).toBe('sampler');
		expect(botSpec(2200)).toMatchObject({ kind: 'ucielo', movetimeMs: 400 });
		const mid = botSpec(2200);
		if (mid.kind === 'ucielo') {
			expect(mid.elo).toBeGreaterThan(2400);
			expect(mid.elo).toBeLessThan(2800);
		}
	});

	it('shallow depth only for true beginners', () => {
		expect(botSpec(200)).toMatchObject({ kind: 'sampler', depth: 1 });
		expect(botSpec(600)).toMatchObject({ kind: 'sampler', depth: 2 });
	});

	it('saturates the knob then stretches movetime at the top, and clamps', () => {
		const high = botSpec(2900);
		expect(high).toMatchObject({ kind: 'ucielo', elo: 3190 });
		if (high.kind === 'ucielo') {
			expect(high.movetimeMs).toBeGreaterThan(400);
			expect(high.movetimeMs).toBeLessThan(1000);
		}
		expect(botSpec(9999)).toEqual(botSpec(BOT_ELO_MAX));
	});

	it('spec ids round-trip through parseSpec/specToRecipe (harness contract)', () => {
		expect(specToRecipe(parseSpec('sampler:a2:d2'))).toMatchObject({
			go: 'go depth 2',
			sample: true,
			alpha: 2
		});
		expect(specToRecipe(parseSpec('skill:3:d3')).options).toContainEqual(['Skill Level', '3']);
		expect(specToRecipe(parseSpec('ucielo:2400:mt400')).go).toBe('go movetime 400');
	});
});
