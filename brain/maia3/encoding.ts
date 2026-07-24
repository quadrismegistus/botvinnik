// Maia-3 board encoding. Written from the model's tensor contract (input
// names, shapes, plane order), NOT from CSSLab's AGPL reference client or
// any other implementation.
//
// Contract (confirmed by loading maia3_simplified.onnx in our calibration
// spike, scripts/maia3-node.mts):
//   inputs:  tokens[batch,64,12]  float32 — one-hot piece occupancy per square
//            elo_self[batch]      float32 — continuous scalar, raw ELO
//            elo_oppo[batch]      float32 — continuous scalar, raw ELO
//   outputs: logits_move[batch,4352]  float32 — policy logits
//            logits_value[batch,3]     float32 — WDL logits (order: L, D, W)
//
// Plane order (standard chess piece ordering): white P,N,B,R,Q,K then black
// p,n,b,r,q,k — indices 0..11. The board is always presented from the
// side-to-move's perspective: when Black is to move, the FEN is mirrored
// (ranks flipped + colours swapped) so the mover is "White" moving up.

const NUM_SQUARES = 64;
const SQUARES_PER_SIDE = 8;
const PLANES_PER_SQUARE = 12;

const PIECE_PLANE_ORDER = ['P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k'];

/** Vocab: 4096 base (every from×to pair; queen promotions share the base lane)
 *  + 256 reserved underpromotion lanes (64 destinations × 4 pieces). */
export const POLICY_VOCAB_SIZE = 4352;
const BASE_VOCAB_SIZE = NUM_SQUARES * NUM_SQUARES; // 4096
const UNDERPROMOTION_LANES = ['q', 'r', 'b', 'n'] as const;

/** Maps an algebraic square to the token index: s = (rank-1)*8 + file. a1=0, h8=63. */
export function squareIndex(square: string): number {
	const file = square.charCodeAt(0) - 'a'.charCodeAt(0);
	const row = Number(square[1]) - 1;
	return row * SQUARES_PER_SIDE + file;
}

/** Mirrors a square vertically (rank r -> 9-r), keeping the file. */
export function mirrorSquare(square: string): string {
	return square[0] + (SQUARES_PER_SIDE + 1 - Number(square[1]));
}

/**
 * Flat policy-vocab index for a move, keyed by from + to + promotion.
 * Queen promotions (and non-promoting moves) use the base from*64+to lane —
 * a pawn reaching the back rank always promotes, so `to` alone disambiguates.
 * Underpromotions (r/b/n) use a reserved lane keyed by destination + piece.
 *
 * Layout verified 2026-07-24 against flawchess's CONFIRMED tensor contract
 * (their maia_encoding.py, re-verified by them against the live model to
 * 0.01%): from*64+to base, a1=0/h8=63 indexing, underpromotion lane
 * 4096 + to*4 + laneIdx with (q,r,b,n) order, raw-ELO scalar inputs. Read
 * for the numerical contract only — no code was copied (their impl is MIT,
 * written from scratch against the same ONNX I/O contract).
 */
export function moveVocabIndex(from: string, to: string, promotion?: string): number {
	const fromIdx = squareIndex(from);
	const toIdx = squareIndex(to);
	if (promotion === undefined || promotion === 'q') {
		return fromIdx * NUM_SQUARES + toIdx;
	}
	const laneIdx = UNDERPROMOTION_LANES.indexOf(promotion as (typeof UNDERPROMOTION_LANES)[number]);
	return BASE_VOCAB_SIZE + toIdx * UNDERPROMOTION_LANES.length + laneIdx;
}

/** Mirrors a FEN piece-placement field: flips ranks + swaps piece colours. */
function mirrorPiecePlacement(piecePlacement: string): string {
	return piecePlacement
		.split('/')
		.reverse()
		.map((row) =>
			row.replace(/[a-zA-Z]/g, (c) =>
				c === c.toUpperCase() ? c.toLowerCase() : c.toUpperCase(),
			),
		)
		.join('/');
}

/** Mirrors castling rights when flipping the board for black-to-move. */
function swapCastling(castling: string): string {
	if (castling === '-') return '-';
	let out = '';
	if (castling.includes('k')) out += 'K';
	if (castling.includes('q')) out += 'Q';
	if (castling.includes('K')) out += 'k';
	if (castling.includes('Q')) out += 'q';
	return out || '-';
}

/** Full FEN mirror: piece placement, active colour, castling, en-passant. */
export function mirrorFEN(fen: string): string {
	const [p, active, castling, ep, half, full] = fen.split(' ');
	const mirroredEp = ep !== '-' ? mirrorSquare(ep) : '-';
	return [
		mirrorPiecePlacement(p),
		active === 'w' ? 'b' : 'w',
		swapCastling(castling),
		mirroredEp,
		half,
		full,
	].join(' ');
}

/**
 * Encodes a FEN into the `tokens[64,12]` input tensor (flat, no batch dim —
 * the caller/worker stacks per-ELO copies). Mirrors the board to the mover's
 * POV when Black is to move. No history planes: the "simplified" export
 * carries n=0 history.
 */
export function encodeBoard(fen: string): Float32Array {
	const [piecePlacement, activeColor] = fen.split(' ');
	if (piecePlacement === undefined) {
		throw new Error(`maia3/encoding: invalid FEN (no piece-placement field): ${fen}`);
	}
	const isBlackToMove = activeColor === 'b';
	const framed = isBlackToMove ? mirrorPiecePlacement(piecePlacement) : piecePlacement;

	const tokens = new Float32Array(NUM_SQUARES * PLANES_PER_SQUARE);
	const rows = framed.split('/');
	for (let rowFromTop = 0; rowFromTop < SQUARES_PER_SIDE; rowFromTop++) {
		const row = SQUARES_PER_SIDE - 1 - rowFromTop; // rank8 -> row7, rank1 -> row0
		let file = 0;
		const rowStr = rows[rowFromTop] ?? '';
		for (const ch of rowStr) {
			const emptyCount = Number.parseInt(ch, 10);
			if (Number.isNaN(emptyCount)) {
				const planeIdx = PIECE_PLANE_ORDER.indexOf(ch);
				if (planeIdx >= 0) {
					tokens[(row * SQUARES_PER_SIDE + file) * PLANES_PER_SQUARE + planeIdx] = 1.0;
				}
				file += 1;
			} else {
				file += emptyCount;
			}
		}
	}
	return tokens;
}

/**
 * [encodeBoard] as a plain number[], for the Dart JSON bridge —
 * JSON.stringify turns a Float32Array into an OBJECT ({"0":..}), which the
 * bridge would hand Dart as a Map. The workers keep the typed-array form.
 */
export function encodeBoardArray(fen: string): number[] {
	return Array.from(encodeBoard(fen));
}

/** Whether the side to move is Black in the given FEN. */
export function isBlackToMove(fen: string): boolean {
	return fen.split(' ')[1] === 'b';
}
