import { describe, expect, it } from 'vitest';
import { gameAccuracy, labelCounts, moveAccuracy, type StoredMove } from './gameStore';

function move(color: 'w' | 'b', wcDrop: number, label?: StoredMove['label']): StoredMove {
	return {
		ply: 1,
		san: 'e4',
		uci: 'e2e4',
		color,
		fenBefore: '',
		fenAfter: '',
		evalPawns: 0,
		mate: null,
		pctBest: 100,
		wcDrop,
		label
	};
}

describe('moveAccuracy', () => {
	it('follows the lichess curve', () => {
		expect(moveAccuracy(0)).toBeCloseTo(100, 0);
		expect(moveAccuracy(10)).toBeCloseTo(63.5, 0);
		expect(moveAccuracy(100)).toBe(0); // clamped
	});
});

describe('gameAccuracy', () => {
	it('averages only the labeled moves of one side', () => {
		const moves = [
			move('w', 0, 'best'),
			move('b', 0, 'best'),
			move('w', 20, 'blunder'),
			move('w', 5) // unlabeled — ignored
		];
		const w = gameAccuracy(moves, 'w')!;
		expect(w).toBeCloseTo((moveAccuracy(0) + moveAccuracy(20)) / 2, 5);
		expect(gameAccuracy([], 'w')).toBeNull();
	});
});

describe('labelCounts', () => {
	it('counts labels per side', () => {
		const moves = [
			move('w', 0, 'best'),
			move('w', 25, 'blunder'),
			move('w', 22, 'blunder'),
			move('b', 12, 'mistake')
		];
		expect(labelCounts(moves, 'w')).toEqual({ best: 1, blunder: 2 });
		expect(labelCounts(moves, 'b')).toEqual({ mistake: 1 });
	});
});
