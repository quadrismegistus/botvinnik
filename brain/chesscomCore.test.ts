import { describe, expect, it } from 'vitest';
import { ccGameToStored, type CcGame } from './chesscomCore';

// A chess.com archive game, in the exact shape the Published-Data API returns
// (verified by hand against api.chess.com/pub/player/<name>/games/<yyyy>/<mm>
// on 2026-07-21): a `games` array whose entries carry `uuid`, `rules`,
// `time_class`, `end_time`, `pgn`, and `white`/`black` objects with
// `username`/`rating`/`result`. The extra fields a real response also carries
// (`accuracies`, `eco`, `tcn`, `url`, …) are dropped here because the mapper
// reads none of them — the point is the shape it DOES read, unaltered.
//
// The movetext is a real 7-ply Scholar's mate with the `{[%clk …]}` annotations
// chess.com writes, so this proves chess.js swallows those on load. White
// (`botvinnik_fan`) delivers mate; that is the importing player below.
const SCHOLARS_MATE: CcGame = {
	uuid: '3277772e-aee0-11de-830e-00000001000b',
	rules: 'chess',
	time_class: 'rapid',
	end_time: 1710095400,
	white: { username: 'botvinnik_fan', rating: 1240, result: 'win' },
	black: { username: 'Opponent99', rating: 1255, result: 'checkmated' },
	pgn: [
		'[Event "Live Chess"]',
		'[Site "Chess.com"]',
		'[Date "2024.03.10"]',
		'[White "botvinnik_fan"]',
		'[Black "Opponent99"]',
		'[Result "1-0"]',
		'[ECO "C20"]',
		'[UTCDate "2024.03.10"]',
		'[UTCTime "18:30:00"]',
		'[TimeControl "600"]',
		'[Termination "botvinnik_fan won by checkmate"]',
		'',
		'1. e4 {[%clk 0:10:00]} 1... e5 {[%clk 0:10:00]} 2. Qh5 {[%clk 0:09:58]} ' +
			'2... Nc6 {[%clk 0:09:55]} 3. Bc4 {[%clk 0:09:57]} 3... Nf6 {[%clk 0:09:50]} ' +
			'4. Qxf7# {[%clk 0:09:56]} 1-0'
	].join('\n')
};

describe('ccGameToStored', () => {
	it('maps a chess.com game to an UNGRADED stored game', () => {
		const out = ccGameToStored(SCHOLARS_MATE, 'botvinnik_fan');
		expect(out).not.toBeNull();
		const { stored, humanColor } = out!;

		// the id namespaces the source so a re-import dedupes and a lichess game
		// of the same uuid could never collide
		expect(stored.id).toBe('chesscom-3277772e-aee0-11de-830e-00000001000b');
		expect(stored.source).toBe('chesscom');
		expect(stored.white).toBe('botvinnik_fan');
		expect(stored.black).toBe('Opponent99');
		expect(stored.result).toBe('1-0');
		expect(stored.moveCount).toBe(7);
		expect(stored.moves.map((m) => m.san)).toEqual([
			'e4',
			'e5',
			'Qh5',
			'Nc6',
			'Bc4',
			'Nf6',
			'Qxf7#'
		]);
		// end_time is unix SECONDS; a mapper that forgot the *1000 would archive
		// every chess.com game at 1970
		expect(stored.endedAt).toBe(new Date(1710095400_000).toISOString());
	});

	it('carries NO grades — that is a later job, not this one', () => {
		const { stored } = ccGameToStored(SCHOLARS_MATE, 'botvinnik_fan')!;
		// the whole distinction from lichess: chess.com ships no evals, so the
		// import is an archive and the practice queue it seeds is empty
		expect(stored.whiteAccuracy).toBeNull();
		expect(stored.blackAccuracy).toBeNull();
		expect(stored.labelCounts).toEqual({ w: {}, b: {} });
		for (const m of stored.moves) {
			expect(m.evalPawns).toBeNull();
			expect(m.mate).toBeNull();
			expect(m.pctBest).toBeNull();
			expect(m.wcDrop).toBe(0);
			expect(m.label).toBeUndefined();
			expect(m.bestUci).toBeUndefined();
		}
	});

	it('parses fenBefore/fenAfter/uci with the grader\'s own chess.js', () => {
		// #170 grades a stored game by re-running the engine from each fenBefore,
		// so these must be exactly what the brain would derive, not a hand build.
		const { stored } = ccGameToStored(SCHOLARS_MATE, 'botvinnik_fan')!;
		const first = stored.moves[0];
		expect(first.fenBefore).toBe(
			'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
		);
		expect(first.uci).toBe('e2e4');
		expect(first.fenAfter).toBe(stored.moves[1].fenBefore);
		expect(stored.moves[stored.moves.length - 1].san).toBe('Qxf7#');
	});

	it('encodes "you" through botColor, both seats', () => {
		// White is the importing player: humanColor 'w', so botColor is the
		// side they did NOT play. Review orients off this and a later grade
		// mines the human's mistakes off it.
		const asWhite = ccGameToStored(SCHOLARS_MATE, 'botvinnik_fan')!;
		expect(asWhite.humanColor).toBe('w');
		expect(asWhite.stored.botColor).toBe('b');

		// case-insensitive, like the account names the API echoes back
		const asBlack = ccGameToStored(SCHOLARS_MATE, 'OPPONENT99')!;
		expect(asBlack.humanColor).toBe('b');
		expect(asBlack.stored.botColor).toBe('w');

		// a name in neither seat is a spectator's import: botColor null, and no
		// side is "you"
		const neither = ccGameToStored(SCHOLARS_MATE, 'someone_else')!;
		expect(neither.humanColor).toBeNull();
		expect(neither.stored.botColor).toBeNull();
	});

	it('reads the winner from the result strings, not a guess', () => {
		const drawn: CcGame = {
			...SCHOLARS_MATE,
			white: { username: 'botvinnik_fan', rating: 1240, result: 'agreed' },
			black: { username: 'Opponent99', rating: 1255, result: 'agreed' }
		};
		expect(ccGameToStored(drawn, 'botvinnik_fan')!.stored.result).toBe('1/2-1/2');

		const blackWon: CcGame = {
			...SCHOLARS_MATE,
			white: { username: 'botvinnik_fan', rating: 1240, result: 'resigned' },
			black: { username: 'Opponent99', rating: 1255, result: 'win' }
		};
		expect(ccGameToStored(blackWon, 'botvinnik_fan')!.stored.result).toBe('0-1');
	});

	it('refuses a non-standard variant, an empty PGN, and a moveless game', () => {
		expect(ccGameToStored({ ...SCHOLARS_MATE, rules: 'chess960' }, 'x')).toBeNull();
		expect(ccGameToStored({ ...SCHOLARS_MATE, pgn: undefined }, 'x')).toBeNull();
		// a real PGN with headers but no movetext parses to zero plies
		const empty: CcGame = {
			...SCHOLARS_MATE,
			pgn: '[Event "Live Chess"]\n[White "a"]\n[Black "b"]\n[Result "*"]\n\n*'
		};
		expect(ccGameToStored(empty, 'x')).toBeNull();
	});
});
