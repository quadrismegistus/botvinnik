import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { epdKey } from './practice';
import type { ReportGame, ReportMove } from './report';
import {
	REPORT_TACTICAL_MOTIFS,
	TACTICS_OPENING_MAX_PLY,
	skillReportTactics
} from './reportTactics';

// Fixtures are borrowed from explain.test.ts, where each is already proven
// legal and its tags pinned — never hand-composed here (three illegal
// hand-built positions in one day earned that rule). Each test still asserts
// the properties it leans on.

/** Royal fork: Nc7+ forks king and queen. */
const FORK_FEN = 'q3k3/8/8/1N6/8/8/8/4K3 w - - 0 1';
const FORK_UCI = 'b5c7';

/** Rd5 forks the b5 and d7 knights. */
const ROOK_FORK_FEN = '7k/3n4/8/1n5R/8/8/8/4K3 w - - 0 1';
const ROOK_FORK_UCI = 'h5d5';

/** Back-rank mate in ONE, black to move — 'mate' comes from the board. */
const BACKRANK_FEN = '4r1k1/p2r3p/2p3p1/4p3/1P3p1Q/P6R/5PPP/2B3K1 b - - 0 33';
const BACKRANK_UCI = 'd7d1';

/** Rd1+ starts mate in TWO, black to move — 'mate' only via bestMate. */
const MATE_IN_2_FEN = '3k4/p2r2p1/Pp3p2/4b2p/8/4Q3/1R3PPP/6K1 b - - 0 33';
const MATE_IN_2_UCI = 'd7d1';

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

const sanOf = (fen: string, uci: string) =>
	new Chess(fen).move({
		from: uci.slice(0, 2),
		to: uci.slice(2, 4),
		promotion: uci.length > 4 ? uci.slice(4) : undefined
	}).san;

it('fixtures are legal and the best moves apply', () => {
	expect(sanOf(FORK_FEN, FORK_UCI)).toBe('Nc7+');
	expect(sanOf(ROOK_FORK_FEN, ROOK_FORK_UCI)).toBe('Rd5');
	expect(sanOf(BACKRANK_FEN, BACKRANK_UCI)).toBe('Rd1#');
	expect(sanOf(MATE_IN_2_FEN, MATE_IN_2_UCI)).toBe('Rd1+');
});

/** Filler plies: alternate colors from white, carry nothing the selector
 *  reads (no topRecorded), exist to push a fixture past the opening gate. */
const filler = (n: number): ReportMove[] =>
	Array.from({ length: n }, (_, i) => ({
		color: i % 2 === 0 ? 'w' : 'b',
		evalPawns: null,
		mate: null
	}));

interface Fx {
	fen: string;
	bestUci: string;
	playedUci?: string; // defaults to bestUci (found)
	playedSan?: string;
	bestMate?: number | null;
	topRecorded?: boolean;
	at?: number; // 0-based index in the move list
}

/** A game whose only selector-visible move is the fixture. The fixture's
 *  index must land on the mover's color in the w/b alternation. */
function gameWith(fx: Fx, { tc = '180+2', human = 'w' as 'w' | 'b' } = {}): ReportGame {
	const at = fx.at ?? (human === 'w' ? 12 : 13);
	const color = at % 2 === 0 ? 'w' : 'b';
	expect(color).toBe(human); // a fixture on the bot's ply tests nothing
	const move: ReportMove = {
		color,
		evalPawns: 0.5,
		mate: null,
		fenBefore: fx.fen,
		uci: fx.playedUci ?? fx.bestUci,
		...(fx.playedSan !== undefined ? { san: fx.playedSan } : {}),
		bestUci: fx.bestUci,
		bestMate: fx.bestMate ?? null,
		topRecorded: fx.topRecorded ?? true
	};
	return {
		botColor: human === 'w' ? 'b' : 'w',
		botBothSides: false,
		pgn: `[TimeControl "${tc}"]\n\n1. e4 *`,
		moves: [...filler(at), move]
	};
}

describe('skillReportTactics selection', () => {
	it('selects a fork and scores found by the exact-move predicate', () => {
		const r = skillReportTactics([gameWith({ fen: FORK_FEN, bestUci: FORK_UCI })]);
		expect(r.positions).toHaveLength(1);
		const p = r.positions[0];
		expect(p.motifs).toContain('fork');
		expect(p.bestSan).toBe('Nc7+');
		expect(p.found).toBe(true);
		expect(p.cls).toBe('blitz');
		expect(p.key).toBe(`${epdKey(FORK_FEN)}|${FORK_UCI}`);
		expect(r.byClass.blitz).toEqual({ n: 1, found: 1, noTopGames: 0, assistedGames: 0 });
		expect(r.games).toEqual({
			considered: 1,
			humanless: 0,
			offClass: 0,
			assisted: 0,
			noTopMoves: 0
		});
	});

	it('admits the same position whether the user found it or not — the bias invariant', () => {
		// e1f2 is a legal quiet alternative in the fork position
		expect(() => new Chess(FORK_FEN).move({ from: 'e1', to: 'f2' })).not.toThrow();
		const found = skillReportTactics([gameWith({ fen: FORK_FEN, bestUci: FORK_UCI })]);
		const missed = skillReportTactics([
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, playedUci: 'e1f2' })
		]);
		expect(found.positions[0].key).toBe(missed.positions[0].key);
		expect(found.positions[0].motifs).toEqual(missed.positions[0].motifs);
		expect(found.positions[0].found).toBe(true);
		expect(missed.positions[0].found).toBe(false);
	});

	it("excludes opening plies up to the peer tables' opening bucket, boundary exact", () => {
		// index 8 = ply 9 ≤ 10: theory territory, excluded; ply 13 selected
		const early = skillReportTactics([gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, at: 8 })]);
		expect(early.positions).toHaveLength(0);
		// The excluded game is CONSIDERED, not "not yet graded": sawTop must be
		// set before the opening gate, or the card tells the user a graded game
		// is pending a grade (#294 review, MUT-B5).
		expect(early.games).toEqual({
			considered: 1,
			humanless: 0,
			offClass: 0,
			assisted: 0,
			noTopMoves: 0
		});
		// Both edges of the boundary, so neither the operator nor the 0-based
		// index arithmetic can drift (#294 review, MUT-B1/B2): index 9 = ply 10
		// is the LAST excluded ply, index 10 = ply 11 the first selectable.
		const plyTen = skillReportTactics([
			gameWith({ fen: BACKRANK_FEN, bestUci: BACKRANK_UCI, at: 9 }, { human: 'b' })
		]);
		expect(plyTen.positions).toHaveLength(0);
		const plyEleven = skillReportTactics([
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, at: 10 })
		]);
		expect(plyEleven.positions).toHaveLength(1);
		const late = skillReportTactics([gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, at: 12 })]);
		expect(late.positions).toHaveLength(1);
		expect(TACTICS_OPENING_MAX_PLY).toBe(10);
	});

	it('skips the opening gate for a game from a custom start position', () => {
		// A fromFen game's move index is not a ply from the standard start:
		// "ply ≤ 10" there drops midgame moves, not theory (#294 review). The
		// fork fixture AT INDEX 0 is selectable because its first fenBefore is
		// not the standard board.
		const r = skillReportTactics([gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, at: 0 })]);
		expect(r.positions).toHaveLength(1);
		expect(r.positions[0].motifs).toContain('fork');
	});

	it('excludes assisted games and counts them', () => {
		const base = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI });
		const r = skillReportTactics([
			{ ...base, botHintsUsed: true },
			{ ...base, botUndos: 2 },
			{ ...base, refusedMoves: 1 },
			base
		]);
		// With arrows on screen, after a takeback, or behind a refusal retry,
		// "found" is not a measurement of finding (#294 review).
		expect(r.positions).toHaveLength(1);
		expect(r.games.assisted).toBe(3);
		expect(r.byClass.blitz.assistedGames).toBe(3);
		expect(r.games.considered).toBe(1);
	});

	it('counts ungraded games per class, so a card never cites another class', () => {
		const blitz = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI }, { tc: '180+2' });
		const rapidUngraded =
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, topRecorded: false }, { tc: '600' });
		const r = skillReportTactics([blitz, rapidUngraded, rapidUngraded]);
		expect(r.byClass.blitz.noTopGames).toBe(0);
		expect(r.byClass.rapid.noTopGames).toBe(2);
		expect(r.games.noTopMoves).toBe(2);
	});

	it('gates the population on topRecorded and counts the excluded game', () => {
		const r = skillReportTactics([
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, topRecorded: false })
		]);
		expect(r.positions).toHaveLength(0);
		expect(r.games.noTopMoves).toBe(1);
		expect(r.byClass.blitz.noTopGames).toBe(1);
		expect(r.games.considered).toBe(0);
	});

	it('does not select a quiet move', () => {
		const r = skillReportTactics([gameWith({ fen: START_FEN, bestUci: 'e2e4' })]);
		expect(r.positions).toHaveLength(0);
		expect(r.games.considered).toBe(1); // the game is in the population; the move is just not tactical
	});

	it('selects a mate the board cannot see via bestMate', () => {
		const r = skillReportTactics([
			gameWith(
				{ fen: MATE_IN_2_FEN, bestUci: MATE_IN_2_UCI, bestMate: 2, playedUci: 'e5c7' },
				{ human: 'b' }
			)
		]);
		expect(r.positions).toHaveLength(1);
		expect(r.positions[0].motifs).toContain('mate');
		expect(r.positions[0].found).toBe(false);
	});

	it('selects a mate-in-one from the board alone, bestMate unknown', () => {
		const r = skillReportTactics([
			gameWith({ fen: BACKRANK_FEN, bestUci: BACKRANK_UCI, bestMate: null }, { human: 'b' })
		]);
		expect(r.positions).toHaveLength(1);
		expect(r.positions[0].motifs).toContain('mate');
	});

	it('lets a matching SAN vouch for a move whose UCI spelling differs', () => {
		// The real case is a dragged castle (stored e1h1, engine e1g1) — see
		// game_controller.engineUci. Exercised here as the contract itself:
		// same SAN ⇒ same move, suffixes stripped; a different SAN stays missed.
		const spelled = skillReportTactics([
			gameWith({
				fen: ROOK_FORK_FEN,
				bestUci: ROOK_FORK_UCI,
				playedUci: 'h5d5x', // spelling the exact-match predicate cannot accept
				playedSan: 'Rd5'
			})
		]);
		expect(spelled.positions[0].found).toBe(true);
		const other = skillReportTactics([
			gameWith({
				fen: ROOK_FORK_FEN,
				bestUci: ROOK_FORK_UCI,
				playedUci: 'b5d4',
				playedSan: 'Nd4'
			})
		]);
		expect(other.positions[0].found).toBe(false);
	});

	it('strips check/mate suffixes before the SAN comparison', () => {
		const r = skillReportTactics([
			gameWith(
				{
					fen: BACKRANK_FEN,
					bestUci: BACKRANK_UCI,
					playedUci: 'd7d1x',
					playedSan: 'Rd1' // dartchess might not stamp the # the engine's line earns
				},
				{ human: 'b' }
			)
		]);
		expect(r.positions[0].found).toBe(true);
	});

	it('routes positions by time class and counts off-class games', () => {
		const r = skillReportTactics([
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI }, { tc: '180+2' }),
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, playedUci: 'e1f2' }, { tc: '600' }),
			gameWith({ fen: FORK_FEN, bestUci: FORK_UCI }, { tc: '60' })
		]);
		expect(r.byClass.blitz).toEqual({ n: 1, found: 1, noTopGames: 0, assistedGames: 0 });
		// chess.com's bare "600" form
		expect(r.byClass.rapid).toEqual({ n: 1, found: 0, noTopGames: 0, assistedGames: 0 });
		expect(r.byClass.classical).toEqual({ n: 0, found: 0, noTopGames: 0, assistedGames: 0 });
		expect(r.games.offClass).toBe(1);
		expect(r.positions).toHaveLength(2);
	});

	it('excludes bot-vs-bot and unknown-sided games as humanless', () => {
		const g = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI });
		const r = skillReportTactics([
			{ ...g, botBothSides: true },
			{ ...g, botColor: null }
		]);
		expect(r.positions).toHaveLength(0);
		expect(r.games.humanless).toBe(2);
	});

	it('skips a move whose bestUci is illegal, not the game around it', () => {
		const bad = gameWith({ fen: FORK_FEN, bestUci: 'a1a8' }); // a1 is empty here
		const good = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, at: 14 });
		const r = skillReportTactics([{ ...bad, moves: [...bad.moves, ...good.moves.slice(13)] }]);
		expect(r.positions).toHaveLength(1);
		expect(r.games.considered).toBe(1);
	});

	it('counts a repeated position every time it was faced', () => {
		const g = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI });
		const again = gameWith({ fen: FORK_FEN, bestUci: FORK_UCI, playedUci: 'e1f2', at: 14 });
		const r = skillReportTactics([{ ...g, moves: [...g.moves, ...again.moves.slice(13)] }]);
		expect(r.positions).toHaveLength(2);
		expect(r.positions[0].key).toBe(r.positions[1].key); // one inference serves both
		expect(r.byClass.blitz).toEqual({ n: 2, found: 1, noTopGames: 0, assistedGames: 0 });
	});

	it('pins the tactical motif set exactly', () => {
		// The exact list, not membership spot-checks: deleting seven of ten
		// entries survived every other test (#294 review, MUT-B3b), and adding
		// the positional four would quietly turn outposts into "tactics"
		// (MUT-B4b). sacrifice/material stay out because they can only fire
		// from a multi-move line, which only MISSED moves carry (#287) —
		// letting them in reintroduces the bias.
		expect([...REPORT_TACTICAL_MOTIFS]).toEqual([
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
		]);
	});

	it('selects a pin and a free capture — geometric motifs beyond the fork', () => {
		// Bg5 pins the f6 knight (explain.test.ts's own fixture).
		const PIN_FEN = 'rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4';
		const pin = skillReportTactics([gameWith({ fen: PIN_FEN, bestUci: 'c1g5' })]);
		expect(pin.positions).toHaveLength(1);
		expect(pin.positions[0].motifs).toContain('pin');
		// Rxd7 wins the queen for free while mate is on (bestMate known).
		const FREE_FEN = 'k7/3q4/8/8/8/8/3R4/K7 w - - 0 1';
		const free = skillReportTactics([
			gameWith({ fen: FREE_FEN, bestUci: 'd2d7', bestMate: 5 })
		]);
		expect(free.positions).toHaveLength(1);
		expect(free.positions[0].motifs).toContain('free capture');
		expect(free.positions[0].motifs).toContain('mate');
	});

	it('does not select a positional-only move — an outpost is not a shot', () => {
		// Nd5 takes an outpost; motifTags says ['outpost'] and nothing else
		// (explain.test.ts). The pool must refuse it or "tactics" quietly
		// becomes "good moves".
		const OUTPOST_FEN = '4k3/pp3ppp/8/8/2P5/2N5/8/4K3 w - - 0 1';
		const r = skillReportTactics([gameWith({ fen: OUTPOST_FEN, bestUci: 'c3d5' })]);
		expect(r.positions).toHaveLength(0);
		expect(r.games.considered).toBe(1);
	});
});
