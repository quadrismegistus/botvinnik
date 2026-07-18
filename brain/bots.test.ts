import { describe, it, expect } from 'vitest';
import { availablePersonas, PERSONAS, personaById, personaInternalElo, SCALE_OFFSET } from './bots';

describe('bot roster', () => {
	it('has 35 personas: 2 Horizons + 12 Squares + 3 retros + 3 Dalas + 6 Maias + Garbo + 8 Fish', () => {
		expect(PERSONAS.length).toBe(35);
		expect(PERSONAS.filter((p) => p.family === 'garbo').length).toBe(1);
		expect(PERSONAS.filter((p) => p.family === 'horizon').length).toBe(2);
		expect(PERSONAS.filter((p) => p.family === 'square').length).toBe(12);
		expect(PERSONAS.filter((p) => p.family === 'retro').length).toBe(3);
		expect(PERSONAS.filter((p) => p.family === 'dala').length).toBe(3);
		expect(PERSONAS.filter((p) => p.family === 'maia').length).toBe(6);
		expect(PERSONAS.filter((p) => p.family === 'fish').length).toBe(8);
	});

	it('sampled Maias: same nets, temperature 1, estimated ratings 260 below argmax', () => {
		expect(personaById('maia-s-1100')?.maiaTemp).toBe(1);
		expect(personaById('maia-s-1100')?.elo).toBe(1310);
		expect(personaById('maia-s-1500')?.elo).toBe(1380);
		expect(personaById('maia-s-1900')?.elo).toBe(1440);
		expect(personaById('maia-1100')?.maiaTemp).toBeUndefined(); // argmax untouched
	});

	it('dala is native-only: hidden from the web roster, present on desktop', () => {
		expect(availablePersonas(false).filter((p) => p.family === 'dala').length).toBe(0);
		expect(availablePersonas(false).length).toBe(32);
		expect(availablePersonas(true).length).toBe(35);
	});

	it('dala personas carry the dala lichess bots real human-pool ratings', () => {
		expect(personaById('dala-700')?.elo).toBe(911);
		expect(personaById('dala-900')?.elo).toBe(1095);
		expect(personaById('dala-1300')?.elo).toBe(1315);
	});

	it('is sorted by display strength and ids are unique', () => {
		for (let i = 1; i < PERSONAS.length; i++)
			expect(PERSONAS[i].elo).toBeGreaterThanOrEqual(PERSONAS[i - 1].elo);
		expect(new Set(PERSONAS.map((p) => p.id)).size).toBe(PERSONAS.length);
	});

	it('binds each family to exactly one mechanism', () => {
		for (const p of PERSONAS) {
			const bindings = [p.shapedLabel, p.maiaBand, p.numericElo, p.retro, p.dalaBand, p.jsceLevel, p.garboMs].filter(
				(x) => x !== undefined
			).length;
			expect(bindings, p.id).toBe(1);
			if (p.family === 'square') expect(p.shapedLabel).toBeDefined();
			if (p.family === 'maia') expect(p.maiaBand).toBeDefined();
			if (p.family === 'fish') expect(p.numericElo).toBeDefined();
			if (p.family === 'retro') expect(p.retro).toBeDefined();
			if (p.family === 'dala') expect(p.dalaBand).toBeDefined();
			if (p.family === 'horizon') expect(p.jsceLevel).toBeDefined();
			if (p.family === 'garbo') expect(p.garboMs).toBeDefined();
		}
	});

	it('retro personas carry the morlock lichess-bot ratings and configs', () => {
		expect(personaById('retro-bernstein-2')?.elo).toBe(1200);
		expect(personaById('retro-sargon-1')?.elo).toBe(1230);
		expect(personaById('retro-turochamp-1')?.elo).toBe(1300);
		expect(personaById('retro-bernstein-2')?.retro).toEqual({ engine: 'bernstein', ply: 2 });
	});

	it('square labels come from the measured curve and stay in the calibrated range', () => {
		const squares = PERSONAS.filter((p) => p.family === 'square');
		for (const p of squares) {
			expect(p.shapedLabel!).toBeGreaterThanOrEqual(600);
			expect(p.shapedLabel!).toBeLessThanOrEqual(1500);
		}
		// stronger display elo ⇒ weakly increasing label
		for (let i = 1; i < squares.length; i++)
			expect(squares[i].shapedLabel!).toBeGreaterThanOrEqual(squares[i - 1].shapedLabel!);
	});

	it('maia bands are the real nets with their real lichess rapid ratings', () => {
		expect(personaById('maia-1100')?.elo).toBe(1570);
		expect(personaById('maia-1500')?.elo).toBe(1640);
		expect(personaById('maia-1900')?.elo).toBe(1700);
	});

	it('fish stay inside the WASM honest ceiling (2800 internal)', () => {
		for (const p of PERSONAS.filter((q) => q.family === 'fish'))
			expect(p.numericElo!).toBeLessThanOrEqual(2800);
	});

	it('personaInternalElo applies the maia-bridge offset', () => {
		const p = personaById('square-1000')!;
		expect(personaInternalElo(p)).toBe(1000 + SCALE_OFFSET);
	});

	it('personaById returns null for unknown/null ids', () => {
		expect(personaById('nope')).toBeNull();
		expect(personaById(null)).toBeNull();
	});
});
