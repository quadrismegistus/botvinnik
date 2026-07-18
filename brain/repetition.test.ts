import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { avoidRepetition } from './repetition';
import type { EngineMove } from './engine/types';

// build the fen history (oldest first, current last) by playing SANs
function fensAfter(sans: string[]): string[] {
	const c = new Chess();
	const fens = [c.fen()];
	for (const san of sans) {
		c.move(san);
		fens.push(c.fen());
	}
	return fens;
}

function line(uci: string, score: number, mate: number | null = null): EngineMove {
	return { pv: [uci], score, mate, depth: 20, multipv: 1 };
}

// knight shuffle from the start position, 7 plies: Black to move in a
// position occurring for the SECOND time; Black's ...Ng8 (f6g8) would recreate
// the start position for the third time — the last legal
// moment to break the loop before the app adjudicates the draw
const SHUFFLE = ['Nf3', 'Nf6', 'Ng1', 'Ng8', 'Nf3', 'Nf6', 'Ng1'];

describe('avoidRepetition', () => {
	it('vetoes the move that would create a third occurrence when clearly winning', () => {
		const fens = fensAfter(SHUFFLE);
		const picked = avoidRepetition('f6g8', fens, [line('f6g8', 5), line('e7e5', 4)]);
		expect(picked).toBe('e7e5');
	});

	it('lets the repetition stand when not clearly winning', () => {
		const fens = fensAfter(SHUFFLE);
		// equal position: repeating is legitimate self-preservation
		const picked = avoidRepetition('f6g8', fens, [line('f6g8', 0.2), line('e7e5', 0.1)]);
		expect(picked).toBe('f6g8');
	});

	it('does nothing when the chosen move does not repeat', () => {
		const fens = fensAfter(SHUFFLE);
		const picked = avoidRepetition('e7e5', fens, [line('e7e5', 5), line('f6g8', 4)]);
		expect(picked).toBe('e7e5');
	});

	it('does nothing without repetition history', () => {
		const fens = fensAfter(['Nf3', 'Nf6']);
		const picked = avoidRepetition('f3e5', fens, [line('f3e5', 5), line('e2e4', 4)]);
		expect(picked).toBe('f3e5');
	});

	it('keeps the original move when every alternative throws the win away', () => {
		const fens = fensAfter(SHUFFLE);
		// the only non-repeating line is losing — forced repetition, let it stand
		const picked = avoidRepetition('f6g8', fens, [line('f6g8', 5), line('e7e5', -3)]);
		expect(picked).toBe('f6g8');
	});

	it('keeps the original move when every alternative also repeats', () => {
		const fens = fensAfter(SHUFFLE);
		const picked = avoidRepetition('f6g8', fens, [line('f6g8', 5), line('f6g8', 4)]);
		expect(picked).toBe('f6g8');
	});

	it('prefers a mating line as the escape', () => {
		const fens = fensAfter(SHUFFLE);
		const picked = avoidRepetition('f6g8', fens, [
			line('f6g8', 9),
			line('e7e5', 0, 3) // mate in 3
		]);
		expect(picked).toBe('e7e5');
	});
});
