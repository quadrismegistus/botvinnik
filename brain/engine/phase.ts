// Game-phase division, for the #268 skill report's endgame axis.
//
// The boundary is lila's own divider rule: a position is an ENDGAME once the
// board holds at most six majors-and-minors across BOTH sides — kings and
// pawns excluded, force not weighed (a queen endgame is an endgame; the rule
// counts pieces). One rule, one implementation: the aggregate pipeline's T5
// sampling and the app's axis computation both import THIS, because two
// notions of "endgame" would make the user's number and the peer baseline
// silently incomparable — the exact drift class the pipeline README's
// commensurability invariant exists to prevent.
import { Chess } from 'chess.js';

const MAJORS_AND_MINORS = new Set(['q', 'r', 'b', 'n', 'Q', 'R', 'B', 'N']);

export function isEndgamePosition(fen: string): boolean {
	const placement = fen.split(' ')[0];
	let n = 0;
	for (const ch of placement) {
		if (MAJORS_AND_MINORS.has(ch)) n++;
	}
	return n <= 6;
}

/**
 * The 1-based ply of the first move PLAYED in an endgame position (so "the
 * endgame's moves" are plies >= this), or null: a game that never got there,
 * a game whose final move only just crossed the line (no move was played
 * beyond it), or movetext that fails to replay — which claims nothing rather
 * than guessing.
 */
export function endgameStartPly(sans: string[], startFen?: string): number | null {
	let board: Chess;
	try {
		board = startFen ? new Chess(startFen) : new Chess();
	} catch {
		return null;
	}
	for (let i = 0; i < sans.length; i++) {
		if (isEndgamePosition(board.fen())) return i + 1;
		try {
			board.move(sans[i]);
		} catch {
			return null;
		}
	}
	return null;
}
