// The "Horizon" personas: js-chess-engine (josefjadrny, MIT) at its lowest
// levels — a tiny pure-JavaScript engine with little quiescence search, so it
// launches exchanges it can't see the end of and walks into recaptures: the
// horizon effect, live. Architecturally weak in the human direction, no
// randomness added.
//
// Gym-measured vs honest rulers (data/bot-gym-ext.json, n=80):
// level 1 ≈ 535 lichess-equiv, level 2 ≈ 860 — and search-family bots carry
// no engine-vs-human pool gap (the retro finding: bernstein measured within
// 2 points of its lichess rating), so the labels are trusted directly.
//
// The library is synchronous; levels 1-2 answer in ~10-100ms, so it runs
// inline. Lazily imported to stay out of the boot bundle.

// The {FROM: TO} → UCI half is shared with the brain's bundled copy. Both apps
// had identical hand-copies of it and only one was tested, which is how the
// promotion-ordering trap in it went unnoticed. $brain/horizonUci imports
// chess.js and NOT js-chess-engine, so pulling it in here cannot drag the
// engine library onto a path it was not already on.
import { horizonUci } from '$brain/horizonUci';

export async function jsceMove(fen: string, level: number): Promise<string | null> {
	const { ai } = await import('js-chess-engine');
	// yield once so the thinking indicator paints before the sync search blocks
	await new Promise((r) => setTimeout(r, 0));
	try {
		const result = ai(fen, { level });
		const entry = Object.entries(result.move)[0] as [string, string] | undefined;
		if (!entry) return null;
		return horizonUci(fen, entry[0], entry[1]);
	} catch {
		return null; // finished game, or a level the library rejects
	}
}
