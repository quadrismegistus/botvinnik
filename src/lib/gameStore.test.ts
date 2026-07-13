import { describe, expect, it } from 'vitest';
import {
	gameAccuracy,
	labelCounts,
	moveAccuracy,
	sanitizeExplanations,
	type StoredGame,
	type StoredMove
} from './gameStore';

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

describe('sanitizeExplanations', () => {
	function game(moves: StoredMove[]): StoredGame {
		return {
			id: 'g1',
			endedAt: '2026-07-01T00:00:00.000Z',
			result: '1-0',
			pgn: '',
			botElo: null,
			botColor: null,
			moveCount: moves.length,
			whiteAccuracy: null,
			blackAccuracy: null,
			labelCounts: { w: {}, b: {} },
			moves
		};
	}

	it('drops a stale pin claim the tightened detector no longer makes', () => {
		// the value-blind v1 sentence: the b8 knight is rook-defended, so the
		// "pin" of the b5 pawn restrains nothing
		const m: StoredMove = {
			...move('w', 12, 'mistake'),
			fenBefore: 'rn5k/8/8/1p6/8/8/8/1Q5K w - - 0 1',
			bestSan: 'Qb3',
			bestUci: 'b1b3',
			explanation: { bestPoint: 'Qb3 pins the pawn on b5 against the knight on b8.' }
		};
		const g = game([m]);
		const changed = sanitizeExplanations([g]);
		expect(changed).toEqual([g]);
		expect(m.explanation!.bestPoint).toBeUndefined();
	});

	it('keeps prose the current detectors still stand behind', () => {
		// the classic Bg5 pin re-verifies verbatim — nothing to rewrite
		const m: StoredMove = {
			...move('w', 12, 'mistake'),
			fenBefore: 'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4',
			bestSan: 'Bg5',
			bestUci: 'c1g5',
			explanation: { bestPoint: 'Bg5 pins the knight on f6 against the queen on d8.' }
		};
		expect(sanitizeExplanations([game([m])])).toEqual([]);
		expect(m.explanation!.bestPoint).toContain('pins');
	});

	it('leaves non-claim prose untouched', () => {
		// material sentences need the full PV to recompute — never re-derived
		const m: StoredMove = {
			...move('w', 12, 'mistake'),
			explanation: { bestPoint: 'Instead, Qxb7 wins 3 points of material.' }
		};
		expect(sanitizeExplanations([game([m])])).toEqual([]);
		expect(m.explanation!.bestPoint).toContain('wins 3 points');
	});
});
