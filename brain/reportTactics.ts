// The skill report's tactics axis (#268): SELECTION of tactical positions
// from the archive, plus the found-rate the card shows. The peer half is
// Maia-3's per-position P_R(best move) — computed in Dart over these same
// positions, cached by `key` — because the lichess dumps carry no best lines
// (the pipeline's T7 is struck by design, see pipeline/lichess/README.md).
//
// THE INVARIANT THIS FILE EXISTS TO PROTECT: selection must be SYMMETRIC in
// whether the user found the shot. The issue's original sketch ("motifTags
// over bestPv") would not be — bestPv is stored only on practice candidates
// (#287), i.e. mostly on MISTAKES, so a pool selected through it admits a
// position mainly when the user failed there and the found-rate is biased
// toward zero by construction. Two consequences drawn here:
//
//   1. The tagger always gets the ONE-PLY line `[bestUci]`, never the stored
//      bestPv, so a position classifies identically found or missed. That
//      forfeits the line-dependent motifs (sacrifice, material) for every
//      move equally — a smaller pool, not a slanted one.
//   2. The population is gated on `topRecorded` — the writer recorded the
//      engine's own move on EVERY analysed ply (#281) — so "the engine
//      agreed" and "nobody looked" stay distinguishable. Within this
//      population bestUci exists on found and missed moves alike. (Lichess
//      imports lack it until the background grader regrades them; the card
//      counts those games as excluded rather than silently shrinking.)
//
// The user is scored on the SAME predicate the peer is: played exactly the
// engine's move. Positions with two equally good moves dilute both sides of
// the comparison identically — the framing caveat is honest ("played the
// engine's top move"), the comparison stays fair.
import { Chess } from 'chess.js';
import { motifTags, type Motif } from './engine/explain';
import { epdKey } from './practice';
import { timeClassOfPgn, type ReportGame } from './report';

/** Which motifs make a position "tactical" FOR THE REPORT. Distinct from
 *  practice.ts's TACTICAL_MOTIFS, which is a findability heuristic for
 *  puzzle difficulty and excludes discovered attacks / trapped pieces for
 *  its own reasons. Excluded here instead: 'sacrifice' and 'material' can
 *  only fire from a multi-move line (see invariant note above), and the
 *  positional four are not tactics. */
export const REPORT_TACTICAL_MOTIFS: readonly Motif[] = [
	'mate',
	'back-rank mate',
	'smothered mate',
	'fork',
	'free capture',
	'pin',
	'skewer',
	'discovered attack',
	'trapped piece',
	'promotion'
];

/** Opening plies are excluded: motif geometry there (the Bb4/Bg4 pins of
 *  half the openings in the book) is planted by known theory, and reciting
 *  theory is a different skill from finding a shot. The boundary is the
 *  peer tables' own opening bucket (meta.plyBuckets.openingMax). */
export const TACTICS_OPENING_MAX_PLY = 10;

const REPORT_CLASSES = ['blitz', 'rapid', 'classical'] as const;
type ReportClass = (typeof REPORT_CLASSES)[number];

export interface TacticalPosition {
	/** epdKey(fen) + '|' + bestUci — the sweep's cache key. Position identity
	 *  by the practice rule (#286); bestUci kept in the key so a regrade that
	 *  changes the engine's mind cannot serve a stale curve. */
	key: string;
	fen: string;
	bestUci: string;
	/** Computed HERE by chess.js from (fen, bestUci) — never the stored
	 *  bestSan — so it matches computeMoveCurves' SAN keys by construction
	 *  (same library builds both) and the Maia lookup cannot silently miss. */
	bestSan: string;
	found: boolean;
	cls: ReportClass;
	motifs: Motif[];
}

export interface TacticsReport {
	positions: TacticalPosition[];
	byClass: Record<ReportClass, { n: number; found: number }>;
	games: {
		/** in-class human games contributing at least one top-recorded move */
		considered: number;
		humanless: number;
		/** bullet/ultrabullet/no-TimeControl — outside the report's classes */
		offClass: number;
		/** in-class human games with NO top-recorded human move: imported and
		 *  not yet (re)graded, or graded before #281. Counted, not silent. */
		noTopMoves: number;
	};
}

/** `O-O+` and `O-O#` disambiguate nothing — strip so the played SAN (written
 *  by dartchess) can vouch for a move whose UCI spelling differs. */
const stripSanSuffix = (san: string) => san.replace(/[+#]+$/, '');

function applyUci(board: Chess, uci: string) {
	return board.move({
		from: uci.slice(0, 2),
		to: uci.slice(2, 4),
		promotion: uci.length > 4 ? uci.slice(4) : undefined
	});
}

export function skillReportTactics(games: ReportGame[]): TacticsReport {
	const positions: TacticalPosition[] = [];
	const byClass: TacticsReport['byClass'] = {
		blitz: { n: 0, found: 0 },
		rapid: { n: 0, found: 0 },
		classical: { n: 0, found: 0 }
	};
	const counts = { considered: 0, humanless: 0, offClass: 0, noTopMoves: 0 };

	for (const g of games) {
		const human = g.botBothSides
			? null
			: g.botColor === 'w'
				? 'b'
				: g.botColor === 'b'
					? 'w'
					: null;
		if (!human) {
			counts.humanless += 1;
			continue;
		}
		const cls = timeClassOfPgn(g.pgn) as ReportClass | null;
		if (!cls || !REPORT_CLASSES.includes(cls)) {
			counts.offClass += 1;
			continue;
		}

		let sawTop = false;
		for (let i = 0; i < g.moves.length; i++) {
			const m = g.moves[i];
			if (m.color !== human) continue;
			if (!m.topRecorded || !m.bestUci || !m.fenBefore) continue;
			sawTop = true;
			if (i + 1 <= TACTICS_OPENING_MAX_PLY) continue;

			// One unreadable fen or illegal bestUci skips one move, never the
			// report — the archive holds every writer's history.
			let bestSan: string;
			try {
				bestSan = applyUci(new Chess(m.fenBefore), m.bestUci).san;
			} catch {
				continue;
			}
			const tags = motifTags(m.fenBefore, m.bestUci, [m.bestUci], m.bestMate ?? null);
			const motifs = tags.filter((t) => REPORT_TACTICAL_MOTIFS.includes(t));
			if (motifs.length === 0) continue;

			// Exact-move predicate, with a SAN fallback for spelling variants:
			// a dragged castle stores dartchess's king-takes-rook `e1h1` while
			// the engine's bestUci is `e1g1` (game_controller.engineUci tells
			// the whole story). Two DIFFERENT moves can never share a SAN in
			// one position, so the fallback only rescues spellings.
			const found =
				m.uci === m.bestUci ||
				(m.san != null && stripSanSuffix(m.san) === stripSanSuffix(bestSan));

			positions.push({
				key: `${epdKey(m.fenBefore)}|${m.bestUci}`,
				fen: m.fenBefore,
				bestUci: m.bestUci,
				bestSan,
				found,
				cls,
				motifs
			});
			byClass[cls].n += 1;
			if (found) byClass[cls].found += 1;
		}
		if (sawTop) counts.considered += 1;
		else counts.noTopMoves += 1;
	}

	return { positions, byClass, games: counts };
}
