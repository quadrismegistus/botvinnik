import { describe, expect, it } from 'vitest';
import {
	encodeBoard,
	mirrorFEN,
	mirrorSquare,
	squareIndex,
	moveVocabIndex,
	isBlackToMove,
	POLICY_VOCAB_SIZE,
} from './encoding';
import {
	maskAndSoftmax,
	softmaxWdl,
	expectedScore,
	computeMoveCurves,
	type RawPolicyByElo,
	type RawWdlByElo,
} from './decoding';
import { MAIA_ELO_LADDER } from './ladder';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const AFTER_E4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';

// ─── ladder ───────────────────────────────────────────────────────────────

describe('MAIA_ELO_LADDER', () => {
	it('is 600..2600 step 100 (21 rungs)', () => {
		expect(MAIA_ELO_LADDER).toHaveLength(21);
		expect(MAIA_ELO_LADDER[0]).toBe(600);
		expect(MAIA_ELO_LADDER[20]).toBe(2600);
	});

	it('steps by 100', () => {
		for (let i = 1; i < MAIA_ELO_LADDER.length; i++) {
			expect(MAIA_ELO_LADDER[i]! - MAIA_ELO_LADDER[i - 1]!).toBe(100);
		}
	});
});

// ─── squareIndex ──────────────────────────────────────────────────────────

describe('squareIndex', () => {
	it('maps a1=0, h1=7, a8=56, h8=63', () => {
		expect(squareIndex('a1')).toBe(0);
		expect(squareIndex('h1')).toBe(7);
		expect(squareIndex('a8')).toBe(56);
		expect(squareIndex('h8')).toBe(63);
	});

	it('maps e4 to 28', () => {
		expect(squareIndex('e4')).toBe(28);
	});
});

// ─── mirrorSquare ─────────────────────────────────────────────────────────

describe('mirrorSquare', () => {
	it('flips the rank, keeps the file', () => {
		expect(mirrorSquare('e2')).toBe('e7');
		expect(mirrorSquare('e7')).toBe('e2');
		expect(mirrorSquare('a1')).toBe('a8');
		expect(mirrorSquare('h8')).toBe('h1');
	});
});

// ─── mirrorFEN ────────────────────────────────────────────────────────────

describe('mirrorFEN', () => {
	it('flips the board and swaps colours so Black is presented as White', () => {
		const mirrored = mirrorFEN(AFTER_E4);
		// After mirror, the white pawn on e4 should appear as a black pawn on e5
		// (rank flipped, colour swapped), and it should be White's turn.
		expect(mirrored.split(' ')[1]).toBe('w');
		// The original has '4P3' on rank 4 (white pawn on e4); mirrored should
		// have '4p3' on rank 5 (black pawn on e5 from White's perspective).
		expect(mirrored.split('/')[3]).toContain('p');
	});

	it('preserves castling rights with colour swap', () => {
		const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1';
		const mirrored = mirrorFEN(fen);
		expect(mirrored.split(' ')[2]).toBe('KQkq'); // all four, swapped order
	});
});

// ─── encodeBoard ──────────────────────────────────────────────────────────

describe('encodeBoard', () => {
	it('produces a 768-element (64×12) tensor', () => {
		expect(encodeBoard(START).length).toBe(768);
	});

	it('places white pawns on rank 2 when White to move', () => {
		const tokens = encodeBoard(START);
		// White pawns = plane 0 (P in PNBRQKpnbrqk). Rank 2 = rows 1..1 (a2=8..h2=15).
		// Tensor is square-major: index = squareIdx * 12 + planeIdx.
		for (let sq = 8; sq <= 15; sq++) {
			expect(tokens[sq * 12 + 0]).toBe(1); // plane 0 = P
		}
	});

	it('mirrors the board for Black to move (black pawns become "white")', () => {
		const tokens = encodeBoard(AFTER_E4);
		// After mirror, Black's 8 pawns (rank 7) appear as White pawns (plane 0)
		// on rank 2. Tensor is square-major: plane 0 of square sq is at sq*12+0.
		let ownPawns = 0;
		for (let sq = 0; sq < 64; sq++) ownPawns += tokens[sq * 12 + 0];
		expect(ownPawns).toBe(8);
	});

	it('is a pure one-hot encoding (every nonzero value is exactly 1.0)', () => {
		const tokens = encodeBoard(START);
		for (const v of tokens) {
			if (v !== 0) expect(v).toBe(1);
		}
	});

	it('encodes exactly 32 pieces on the start position', () => {
		const tokens = encodeBoard(START);
		const nonZero = Array.from(tokens).filter((v) => v !== 0).length;
		expect(nonZero).toBe(32);
	});
});

// ─── moveVocabIndex ───────────────────────────────────────────────────────

describe('moveVocabIndex', () => {
	it('maps a non-promoting move to from*64+to', () => {
		// e2e4: e2=12, e4=28 → 12*64+28 = 796
		expect(moveVocabIndex('e2', 'e4')).toBe(12 * 64 + 28);
	});

	it('maps a queen promotion to the SAME base lane as the non-promoting move', () => {
		// a7a8q: from=a7=48, to=a8=56 → 48*64+56 = 3128 (same as no promo)
		expect(moveVocabIndex('a7', 'a8', 'q')).toBe(48 * 64 + 56);
		expect(moveVocabIndex('a7', 'a8', 'q')).toBe(moveVocabIndex('a7', 'a8'));
	});

	it('maps underpromotions to the reserved region above 4096', () => {
		const idx = moveVocabIndex('a7', 'a8', 'r');
		expect(idx).toBeGreaterThanOrEqual(4096);
		expect(idx).toBeLessThan(POLICY_VOCAB_SIZE);
	});

	it('distinguishes r/b/n underpromotions for the same destination', () => {
		const r = moveVocabIndex('a7', 'a8', 'r');
		const b = moveVocabIndex('a7', 'a8', 'b');
		const n = moveVocabIndex('a7', 'a8', 'n');
		expect(new Set([r, b, n])).toHaveLength(3);
	});
});

// ─── isBlackToMove ────────────────────────────────────────────────────────

describe('isBlackToMove', () => {
	it('reads the active colour field', () => {
		expect(isBlackToMove(START)).toBe(false);
		expect(isBlackToMove(AFTER_E4)).toBe(true);
	});
});

// ─── maskAndSoftmax ───────────────────────────────────────────────────────

describe('maskAndSoftmax', () => {
	it('returns only legal moves (start position has 20)', () => {
		const policy = new Float32Array(POLICY_VOCAB_SIZE);
		const probs = maskAndSoftmax(policy, START);
		expect(Object.keys(probs)).toHaveLength(20);
	});

	it('sums to ~1.0 over the legal moves', () => {
		const policy = new Float32Array(POLICY_VOCAB_SIZE);
		// Give e2e4 a high logit
		policy[moveVocabIndex('e2', 'e4')] = 5;
		policy[moveVocabIndex('d2', 'd4')] = 3;
		const probs = maskAndSoftmax(policy, START);
		const sum = Object.values(probs).reduce((a, b) => a + b, 0);
		expect(sum).toBeCloseTo(1.0, 6);
	});

	it('assigns the highest probability to the move with the highest logit', () => {
		const policy = new Float32Array(POLICY_VOCAB_SIZE);
		policy[moveVocabIndex('e2', 'e4')] = 5;
		policy[moveVocabIndex('d2', 'd4')] = 1;
		const probs = maskAndSoftmax(policy, START);
		expect(probs['e4']).toBeGreaterThan(probs['d4']);
	});

	it('returns equal probabilities for all-equal logits', () => {
		const policy = new Float32Array(POLICY_VOCAB_SIZE).fill(1);
		const probs = maskAndSoftmax(policy, START);
		const values = Object.values(probs);
		expect(values.every((v) => Math.abs(v - 1 / 20) < 1e-6)).toBe(true);
	});

	it('handles a single legal move (checkmate position)', () => {
		// Black king on h8, white queen + rook covering all escapes but h7 is not
		// covered → not mate. Use a real mate: scholars mate.
		// FEN after 1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6?? 4.Qxf7#
		const mate = 'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4';
		const policy = new Float32Array(POLICY_VOCAB_SIZE);
		const probs = maskAndSoftmax(policy, mate);
		expect(Object.keys(probs)).toHaveLength(0);
	});
});

// ─── softmaxWdl ───────────────────────────────────────────────────────────

describe('softmaxWdl', () => {
	it('produces equal WDL for equal logits', () => {
		const wdl = softmaxWdl([0, 0, 0]);
		expect(wdl.win).toBeCloseTo(1 / 3, 6);
		expect(wdl.draw).toBeCloseTo(1 / 3, 6);
		expect(wdl.loss).toBeCloseTo(1 / 3, 6);
	});

	it('skews toward win when the win logit dominates (order: L=0, D=1, W=2)', () => {
		const wdl = softmaxWdl([0, 0, 10]);
		expect(wdl.win).toBeGreaterThan(0.99);
		expect(wdl.loss).toBeLessThan(0.01);
	});

	it('skews toward loss when the loss logit dominates', () => {
		const wdl = softmaxWdl([10, 0, 0]);
		expect(wdl.loss).toBeGreaterThan(0.99);
	});

	it('sums to 1.0', () => {
		const wdl = softmaxWdl([1.2, -0.3, 0.5]);
		expect(wdl.win + wdl.draw + wdl.loss).toBeCloseTo(1.0, 6);
	});
});

// ─── expectedScore ────────────────────────────────────────────────────────

describe('expectedScore', () => {
	it('is 1.0 for a certain win', () => {
		expect(expectedScore({ win: 1, draw: 0, loss: 0 })).toBe(1);
	});

	it('is 0.0 for a certain loss', () => {
		expect(expectedScore({ win: 0, draw: 0, loss: 1 })).toBe(0);
	});

	it('is 0.5 for a certain draw', () => {
		expect(expectedScore({ win: 0, draw: 1, loss: 0 })).toBe(0.5);
	});
});

// ─── computeMoveCurves ────────────────────────────────────────────────────

describe('computeMoveCurves', () => {
	it('produces one MoveCurvePoint per ELO rung', () => {
		const rawPolicy: RawPolicyByElo[] = [
			{ elo: 1100, policy: new Float32Array(POLICY_VOCAB_SIZE) },
			{ elo: 1900, policy: new Float32Array(POLICY_VOCAB_SIZE) },
		];
		const rawWdl: RawWdlByElo[] = [
			{ elo: 1100, wdl: new Float32Array([0, 0, 0]) },
			{ elo: 1900, wdl: new Float32Array([0, 0, 0]) },
		];
		const result = computeMoveCurves(START, rawPolicy, rawWdl);
		expect(result.perElo).toHaveLength(2);
		expect(result.wdlByElo).toHaveLength(2);
		expect(result.perElo[0]!.elo).toBe(1100);
		expect(result.perElo[1]!.elo).toBe(1900);
	});

	it('each perElo entry has a moveProbabilities map summing to ~1.0', () => {
		const rawPolicy: RawPolicyByElo[] = [
			{ elo: 1500, policy: new Float32Array(POLICY_VOCAB_SIZE) },
		];
		const rawWdl: RawWdlByElo[] = [{ elo: 1500, wdl: new Float32Array([0, 0, 0]) }];
		const result = computeMoveCurves(START, rawPolicy, rawWdl);
		const sum = Object.values(result.perElo[0]!.moveProbabilities).reduce((a, b) => a + b, 0);
		expect(sum).toBeCloseTo(1.0, 6);
	});

	it('each wdlByElo entry has a normalized WdlVector', () => {
		const rawPolicy: RawPolicyByElo[] = [
			{ elo: 1500, policy: new Float32Array(POLICY_VOCAB_SIZE) },
		];
		const rawWdl: RawWdlByElo[] = [{ elo: 1500, wdl: new Float32Array([1, 2, 3]) }];
		const result = computeMoveCurves(START, rawPolicy, rawWdl);
		const { win, draw, loss } = result.wdlByElo[0]!.wdl;
		expect(win + draw + loss).toBeCloseTo(1.0, 6);
	});
});
