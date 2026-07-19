// The pure half of the Horizon move: js-chess-engine's {FROM: TO} answer,
// rendered as UCI. Split out from horizon.ts so BOTH callers share it — the
// brain's bundled version (Flutter) and the web's lazily-imported jsce.ts —
// because the two had drifted into identical ten-line copies where a fix to
// one would not reach the other, and only one of them was tested.
//
// chess.js only. Nothing here imports js-chess-engine, which is what lets the
// web app use it without dragging that library onto its eager path.

import { Chess } from 'chess.js';

/**
 * `from`/`to` as js-chess-engine reports them (it uses uppercase squares and
 * never mentions promotion), rendered as a UCI move — or null if the position
 * does not actually allow it.
 *
 * Total: never throws, including on a malformed FEN, because both callers want
 * a fallback rather than an exception. On the Flutter side especially, a throw
 * crosses the bridge as a StateError on the bot's turn and wedges the game.
 */
export function horizonUci(fen: string, from: string, to: string): string | null {
	const a = from.toLowerCase();
	const b = to.toLowerCase();
	let moves: { from: string; to: string; promotion?: string }[];
	try {
		moves = new Chess(fen).moves({ verbose: true });
	} catch {
		return null; // chess.js rejects the position; nothing legal to name
	}
	const matches = moves.filter((m) => m.from === a && m.to === b);
	if (matches.length === 0) return null;
	// js-chess-engine always promotes to queen and never says so, so UCI has to
	// spell it out. `some` rather than `find` on purpose: chess.js orders
	// promotions n, b, r, q, so the FIRST match is the KNIGHT — reading a
	// promotion piece off it would silently underpromote. All we need is
	// whether this from/to is a promotion at all, which is a yes/no.
	return `${a}${b}${matches.some((m) => m.promotion) ? 'q' : ''}`;
}
