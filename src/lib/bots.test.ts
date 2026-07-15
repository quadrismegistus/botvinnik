import { describe, it, expect } from 'vitest';
import { PERSONAS, personaById, personaInternalElo, SCALE_OFFSET } from './bots';

describe('bot roster', () => {
	it('has 26 personas: 12 Squares + 3 retros + 3 Maias + 8 Fish', () => {
		expect(PERSONAS.length).toBe(26);
		expect(PERSONAS.filter((p) => p.family === 'square').length).toBe(12);
		expect(PERSONAS.filter((p) => p.family === 'retro').length).toBe(3);
		expect(PERSONAS.filter((p) => p.family === 'maia').length).toBe(3);
		expect(PERSONAS.filter((p) => p.family === 'fish').length).toBe(8);
	});

	it('is sorted by display strength and ids are unique', () => {
		for (let i = 1; i < PERSONAS.length; i++)
			expect(PERSONAS[i].elo).toBeGreaterThanOrEqual(PERSONAS[i - 1].elo);
		expect(new Set(PERSONAS.map((p) => p.id)).size).toBe(PERSONAS.length);
	});

	it('binds each family to exactly one mechanism', () => {
		for (const p of PERSONAS) {
			const bindings = [p.shapedLabel, p.maiaBand, p.numericElo, p.retro].filter(
				(x) => x !== undefined
			).length;
			expect(bindings, p.id).toBe(1);
			if (p.family === 'square') expect(p.shapedLabel).toBeDefined();
			if (p.family === 'maia') expect(p.maiaBand).toBeDefined();
			if (p.family === 'fish') expect(p.numericElo).toBeDefined();
			if (p.family === 'retro') expect(p.retro).toBeDefined();
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
