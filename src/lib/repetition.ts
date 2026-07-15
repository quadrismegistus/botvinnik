// The bots never see game history — every engine family gets a bare FEN
// snapshot per move, and a FEN cannot encode which positions already occurred.
// So a winning bot can shuffle a piece back and forth, blind to the threefold
// it is walking into, and donate a draw (observed: Garbo 2011 toggling a
// knight in a won position until the app adjudicated repetition).
//
// This is the choice-layer guard: when the bot's chosen move would create the
// THIRD occurrence of a position while the bot stands clearly better, swap in
// the strongest full-strength line that neither repeats nor throws the win
// away. Same doctrine as the shaped bots' directional conversion: winning
// bots convert; they don't donate. Repeating while equal or worse is honest
// self-preservation and stays untouched.

import { getFenAfter } from './engine/chess';
import type { EngineMove } from './engine/stockfish';

/** repetition identity: placement, side to move, castling, en passant */
function posKey(fen: string): string {
	return fen.split(' ').slice(0, 4).join(' ');
}

/** the mover is winning by enough that a draw would be a donation */
function clearlyWinning(m: EngineMove): boolean {
	return m.mate !== null ? m.mate > 0 : m.score >= 2;
}

/** the line still wins (or at least doesn't lose) for the mover */
function keepsTheWin(m: EngineMove): boolean {
	return m.mate !== null ? m.mate > 0 : m.score > 0.5;
}

/**
 * Veto a draw-by-repetition donation. `fens` is every position reached so
 * far, oldest first, with the CURRENT position last (maiaFenHistory's shape);
 * `lines` is the full-strength analysis of the current position, mover's POV.
 * Returns the move to play — the original unless the veto fires and a
 * non-repeating winning alternative exists.
 */
export function avoidRepetition(uci: string, fens: string[], lines: EngineMove[]): string {
	const current = fens.at(-1);
	const best = lines[0];
	if (!current || !best || !clearlyWinning(best)) return uci;

	const counts = new Map<string, number>();
	for (const f of fens) {
		const k = posKey(f);
		counts.set(k, (counts.get(k) ?? 0) + 1);
	}
	const wouldBeThird = (mv: string) => {
		const after = getFenAfter(current, mv);
		return after !== null && (counts.get(posKey(after)) ?? 0) >= 2;
	};

	if (!wouldBeThird(uci)) return uci;
	const alt = lines.find((l) => l.pv[0] && l.pv[0] !== uci && keepsTheWin(l) && !wouldBeThird(l.pv[0]));
	// no winning escape → the repetition is forced; let it stand
	return alt?.pv[0] ?? uci;
}
