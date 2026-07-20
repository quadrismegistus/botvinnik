// The cases and the helpers the native-Maia fixtures are built from, shared by
// the emitter (which reads brain/maia/ directly) and the smoke test (which
// reads the built bundle). Plain JS so plain node can import it too.

import { createHash } from 'node:crypto';
import { Chess } from 'chess.js';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/** One case per thing an innocent-looking edit has already been shown to break. */
export const CASES = [
	{ name: 'start', history: [START] },
	{
		// the history planes are populated here and empty above: an encode that
		// passes only the current FEN produces the same digest for both
		name: 'after 1.e4, with history',
		history: [START, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1']
	},
	{
		// black to move — the board is flipped and the policy index is looked up
		// from the other side
		name: 'black to move, midgame',
		history: ['r2q1rk1/ppp2ppp/2np1n2/2b1p3/2B1P1b1/2NP1N2/PPP2PPP/R1BQ1RK1 b - - 6 8']
	},
	{
		// A promotion wins here, and it is the KNIGHT one — the index-sharing
		// special case (lc0 encodes a knight promotion as the plain move, with
		// no suffix, so the decoder strips the 'n' and looks the move up again).
		// Chosen deliberately: on most promotion positions the synthetic policy
		// prefers a king move, and a case whose answer is not a promotion tests
		// nothing about promotions.
		name: 'knight promotion wins',
		history: ['k7/2P5/8/8/8/8/8/7K w - - 0 1']
	},
	{
		// the same special case from the other side, where the move is flipped
		// before the lookup and flipped back after
		name: 'knight promotion wins, black',
		history: ['7k/8/8/8/8/8/2p5/K7 b - - 0 1']
	},
	{
		// castling rights are four separate planes, ordered us/them
		name: 'both sides can castle both ways',
		history: ['r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1']
	}
];

/**
 * A fixed stand-in for a net's policy head.
 *
 * Deterministic and spread across all 1858 indices, so which move wins depends
 * on the index lookup, the black-side flip and the promotion handling — the
 * whole decoder, with no ONNX anywhere near it.
 */
export function syntheticPolicy() {
	const p = new Float32Array(1858);
	for (let i = 0; i < p.length; i++) p[i] = Math.sin(i * 0.7) * 4;
	return p;
}

/** @param {string} fen */
export const legalUcis = (fen) =>
	new Chess(fen).moves({ verbose: true }).map((m) => m.from + m.to + (m.promotion ?? ''));

/** Planes are 7168 floats; a digest is the reviewable form of that. */
/** @param {ArrayLike<number>} planes */
export const digest = (planes) =>
	createHash('sha256').update(Array.from(planes).join(',')).digest('hex').slice(0, 16);
