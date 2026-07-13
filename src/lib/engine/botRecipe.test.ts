import { describe, expect, it } from 'vitest';
import { botEloMax, botEloMin, botSpec, samplerAlphaFor, specToRecipe, parseSpec } from './botRecipe';

describe('botSpec — native mapping (desktop/Tauri big net)', () => {
	it('hits the measured sampler knots exactly', () => {
		expect(samplerAlphaFor(848, 'native')).toBeCloseTo(0.7, 5);
		expect(samplerAlphaFor(1638, 'native')).toBeCloseTo(2, 5);
		expect(samplerAlphaFor(2022, 'native')).toBeCloseTo(4, 5);
	});

	it('alpha grows monotonically with requested ELO', () => {
		let prev = 0;
		for (let e = 100; e <= 2100; e += 50) {
			const a = samplerAlphaFor(e, 'native');
			expect(a).toBeGreaterThan(prev);
			prev = a;
		}
	});

	it('uses the sampler up to the seam, UCI_Elo above it', () => {
		expect(botSpec(1500, 'native').kind).toBe('sampler');
		expect(botSpec(2100, 'native').kind).toBe('sampler');
		expect(botSpec(2200, 'native')).toMatchObject({ kind: 'ucielo', movetimeMs: 400 });
	});

	it('shallow depth only for true beginners', () => {
		expect(botSpec(200, 'native')).toMatchObject({ kind: 'sampler', depth: 1 });
		expect(botSpec(600, 'native')).toMatchObject({ kind: 'sampler', depth: 2 });
	});

	it('caps at the honest ceiling (2800) at base movetime', () => {
		const top = botSpec(botEloMax('native'), 'native');
		expect(top.kind).toBe('ucielo');
		if (top.kind === 'ucielo') {
			expect(top.movetimeMs).toBe(400);
			expect(top.elo).toBeGreaterThan(3100);
			expect(top.elo).toBeLessThanOrEqual(3190);
		}
		expect(botSpec(9999, 'native')).toEqual(botSpec(botEloMax('native'), 'native'));
	});
});

describe('botSpec — wasm mapping (web small net, the default)', () => {
	it('hits the measured sampler knots exactly', () => {
		expect(samplerAlphaFor(968, 'wasm')).toBeCloseTo(0.7, 5);
		expect(samplerAlphaFor(1812, 'wasm')).toBeCloseTo(2, 5);
		expect(samplerAlphaFor(2239, 'wasm')).toBeCloseTo(4, 5);
	});

	it('is the default substrate, capped at 2800, floored at 100', () => {
		expect(botSpec(1200)).toEqual(botSpec(1200, 'wasm'));
		expect(botEloMax()).toBe(2800);
		expect(botEloMin()).toBe(100);
	});

	it('alpha grows monotonically across the honest range', () => {
		let prev = 0;
		for (let e = botEloMin('wasm'); e <= 2485; e += 50) {
			const a = samplerAlphaFor(e, 'wasm');
			expect(a).toBeGreaterThan(prev);
			prev = a;
		}
	});

	it('seam sits higher than native (sampler up to ~2485)', () => {
		expect(botSpec(2400, 'wasm').kind).toBe('sampler');
		expect(botSpec(2600, 'wasm')).toMatchObject({ kind: 'ucielo', movetimeMs: 400 });
	});

	it('clamps below the floor to the weakest sampler setting', () => {
		expect(botSpec(50, 'wasm')).toEqual(botSpec(100, 'wasm'));
	});

	it('caps at 2800', () => {
		expect(botSpec(9999, 'wasm')).toEqual(botSpec(2800, 'wasm'));
		expect(botSpec(2800, 'wasm').kind).toBe('ucielo');
	});
});

describe('spec ids round-trip (harness contract)', () => {
	it('parseSpec/specToRecipe map spec ids to go/sample/alpha', () => {
		expect(specToRecipe(parseSpec('sampler:a2:d2'))).toMatchObject({
			go: 'go depth 2',
			sample: true,
			alpha: 2
		});
		expect(specToRecipe(parseSpec('skill:3:d3')).options).toContainEqual(['Skill Level', '3']);
		expect(specToRecipe(parseSpec('ucielo:2400:mt400')).go).toBe('go movetime 400');
	});
});
