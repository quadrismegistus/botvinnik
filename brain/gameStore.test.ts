import { describe, expect, it } from 'vitest';
import {
	gameAccuracy,
	labelCounts,
	LABEL_VERSION,
	moveAccuracy,
	relabelGames,
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

function relabelGame(m: Partial<StoredMove>, labelVersion?: number): StoredGame {
	const full: StoredMove = {
		ply: 1,
		san: 'Rd7',
		uci: 'd2d7',
		color: 'w',
		fenBefore: 'k2q4/8/8/8/8/8/3R4/K7 w - - 0 1',
		fenAfter: '',
		evalPawns: 0,
		mate: null,
		pctBest: 50,
		wcDrop: 0,
		...m
	};
	return {
		id: 'g',
		endedAt: '2026-07-14T00:00:00.000Z',
		result: '1-0',
		pgn: '',
		botElo: null,
		botColor: null,
		moveCount: 1,
		whiteAccuracy: null,
		blackAccuracy: null,
		labelCounts: { w: {}, b: {} },
		labelVersion,
		moves: [full]
	};
}

describe('relabelGames', () => {
	it('promotes a missed material-winning capture to miss', () => {
		// Rd7 played (uci d2d7); best was Rxd8 (d2d8) taking the hanging queen
		const g = relabelGame({ label: 'mistake', bestUci: 'd2d8', wcDrop: 45, evalPawns: 0 });
		expect(relabelGames([g])).toHaveLength(1);
		expect(g.moves[0].label).toBe('miss');
		expect(g.labelVersion).toBe(LABEL_VERSION);
		expect(g.labelCounts.w).toEqual({ miss: 1 });
	});

	it('does not promote to miss when the best move is not a capture', () => {
		const g = relabelGame({ label: 'mistake', bestUci: 'd2d3', wcDrop: 45, evalPawns: 0 });
		expect(g.moves[0].label).toBe('mistake');
		relabelGames([g]);
		expect(g.moves[0].label).toBe('mistake');
	});

	it('demotes a brilliant that only held equality (win chance < 55)', () => {
		const g = relabelGame({ label: 'brilliant', evalPawns: 0, uci: 'd2d8', bestUci: 'd2d8' });
		relabelGames([g]);
		expect(g.moves[0].label).toBe('best');
	});

	it('keeps a brilliant that leaves you clearly better', () => {
		const g = relabelGame({ label: 'brilliant', evalPawns: 3, uci: 'd2d8', bestUci: 'd2d8' });
		relabelGames([g]);
		expect(g.moves[0].label).toBe('brilliant');
	});

	it('skips games already at the current label version', () => {
		const g = relabelGame({ label: 'brilliant', evalPawns: 0 }, LABEL_VERSION);
		expect(relabelGames([g])).toHaveLength(0);
		expect(g.moves[0].label).toBe('brilliant'); // untouched
	});
});

describe('moveAccuracy', () => {
	it('follows the lichess curve (incl. the +1 uncertainty bonus)', () => {
		expect(moveAccuracy(0)).toBe(100); // clamped
		expect(moveAccuracy(10)).toBeCloseTo(64.5, 0);
		expect(moveAccuracy(100)).toBe(0); // clamped
	});
});

describe('gameAccuracy', () => {
	it('is 100 for a perfect game and null with nothing graded', () => {
		const moves = [move('w', 0, 'best'), move('b', 0, 'best'), move('w', 0, 'best')];
		expect(gameAccuracy(moves, 'w')).toBe(100);
		expect(gameAccuracy([], 'w')).toBeNull();
		expect(gameAccuracy([move('w', 5)], 'w')).toBeNull(); // unlabeled only
	});

	it('the harmonic component punishes blunders far below the plain mean', () => {
		const moves: StoredMove[] = [];
		for (let k = 0; k < 20; k++) {
			moves.push(move('w', 0, 'best'));
			moves.push(move('b', 0, 'best'));
		}
		moves.push(move('w', 30, 'blunder'));
		const mild = gameAccuracy(moves, 'w')!;
		const arithmetic = (20 * 100 + moveAccuracy(30)) / 21; // the old formula ≈ 96
		expect(mild).toBeLessThan(arithmetic - 3);
		expect(gameAccuracy(moves, 'b')).toBe(100); // Black unaffected

		// a total blunder (accuracy 0) zeroes the harmonic mean, as in lila —
		// the game score collapses to half the weighted mean
		moves.push(move('b', 0, 'best'));
		moves.push(move('w', 90, 'blunder'));
		expect(gameAccuracy(moves, 'w')!).toBeLessThan(55);
	});

	it('ignores the other side and unlabeled moves', () => {
		const moves = [
			move('w', 0, 'best'),
			move('b', 40, 'blunder'), // not White's problem
			move('w', 5) // unlabeled — ignored
		];
		expect(gameAccuracy(moves, 'w')).toBe(100);
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
