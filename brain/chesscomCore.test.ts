import { describe, expect, it } from 'vitest';
import { ccGameToAnalysed, ccGameToStored, mapOneGame, type CcGame } from './chesscomCore';
import { analysedGameToStored } from './lichessImport';
import type { UciEval } from './engine/types';

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

	it('skips a shape-drifted record instead of throwing', () => {
		// The importer walks a whole archive with ONE bridge call per game and no
		// catch, so a mapper that THREW on a missing field would discard the entire
		// batch, not just the bad game. A drifted record must come back null like
		// any other refusal. (These deletions violate CcGame on purpose — the
		// chess.com API shape is not ours to trust.)
		const noEndTime = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noEndTime.end_time;
		expect(() => ccGameToStored(noEndTime as CcGame, 'x')).not.toThrow();
		expect(ccGameToStored(noEndTime as CcGame, 'x')).toBeNull();

		const noWhite = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noWhite.white;
		expect(() => ccGameToStored(noWhite as CcGame, 'x')).not.toThrow();
		expect(ccGameToStored(noWhite as CcGame, 'x')).toBeNull();

		const noBlack = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noBlack.black;
		expect(ccGameToStored(noBlack as CcGame, 'x')).toBeNull();
	});
});

// a stub evaluator: no engine, just enough shape for ccGameToAnalysed to walk
// every position without waiting on a real search
const flatEval: (fen: string) => Promise<UciEval> = async () => ({ cp: 0, pv: [] });

describe('ccGameToAnalysed', () => {
	it('fabricates the lichess-shaped analysis from a chess.com game', async () => {
		const game = await ccGameToAnalysed(SCHOLARS_MATE, flatEval);
		expect(game).not.toBeNull();
		expect(game!.id).toBe(SCHOLARS_MATE.uuid);
		expect(game!.variant).toBe('standard');
		expect(game!.winner).toBe('white'); // white.result === 'win' above
		expect(game!.pgn).toBe(SCHOLARS_MATE.pgn);
		expect(game!.moves).toBe('e4 e5 Qh5 Nc6 Bc4 Nf6 Qxf7#');
		expect(game!.players.white).toEqual({ user: { name: 'botvinnik_fan' }, rating: 1240 });
		expect(game!.players.black).toEqual({ user: { name: 'Opponent99' }, rating: 1255 });
		// one analysis entry per ply, same as a real Lichess export
		expect(game!.analysis).toHaveLength(7);

		// the mapped shape must survive the SAME grader analysedGameToStored feeds
		// on, since that is the only reason ccGameToAnalysed exists
		const mapped = analysedGameToStored(game!, 'botvinnik_fan', 'chesscom');
		expect(mapped).not.toBeNull();
		expect(mapped!.stored.moveCount).toBe(7);
	});

	it('skips a shape-drifted record instead of throwing', async () => {
		// Same hazard as ccGameToStored above, for the offline script's sibling
		// mapper: the script makes one call per game with no catch of its own, and
		// resumes from a per-month checkpoint, so a mapper that threw on a missing
		// field would wedge this month AND every earlier month behind it, on every
		// re-run. A drifted record must resolve null like any other refusal.
		const noEndTime = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noEndTime.end_time;
		await expect(ccGameToAnalysed(noEndTime as CcGame, flatEval)).resolves.toBeNull();

		const noWhite = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noWhite.white;
		await expect(ccGameToAnalysed(noWhite as CcGame, flatEval)).resolves.toBeNull();

		const noBlack = { ...SCHOLARS_MATE } as Partial<CcGame>;
		delete noBlack.black;
		await expect(ccGameToAnalysed(noBlack as CcGame, flatEval)).resolves.toBeNull();
	});
});

// scripts/analyze-chesscom.mts cannot be imported directly in a unit test: it
// spawns real engine processes and reads process.argv at module load, before
// any test harness gets a say. So this reproduces its per-game loop verbatim
// — guard-then-catch, skip-and-continue — against the REAL ccGameToAnalysed,
// to prove the shape survives a throw the guard above does NOT anticipate
// (here, evalPosition itself rejecting — an engine crash mid-analysis) without
// losing the good games on either side of it. Mirrors the batch-survival test
// chesscom_import_api.dart added for the in-app importer's own backstop (#176).
describe('offline script per-game resilience (mirrors scripts/analyze-chesscom.mts)', () => {
	it('one game whose analysis throws does not abort the batch', async () => {
		const good1: CcGame = { ...SCHOLARS_MATE, uuid: 'good-1' };
		const crashes: CcGame = { ...SCHOLARS_MATE, uuid: 'crashes' };
		const good2: CcGame = { ...SCHOLARS_MATE, uuid: 'good-2' };
		// every position of this game hits the same evaluator, so a crash fires
		// regardless of which position gets probed first — an engine dying
		// mid-search, not a shape the guard above could have caught
		const crashingEval: (fen: string) => Promise<UciEval> = async () => {
			throw new Error('engine crashed');
		};

		let skipped = 0;
		const mappedIds: string[] = [];
		for (const cc of [good1, crashes, good2]) {
			const evalForThisGame = cc.uuid === crashes.uuid ? crashingEval : flatEval;
			let mapped: ReturnType<typeof analysedGameToStored> = null;
			try {
				const lichessShaped = await ccGameToAnalysed(cc, evalForThisGame);
				mapped = lichessShaped ? analysedGameToStored(lichessShaped, 'botvinnik_fan', 'chesscom') : null;
			} catch {
				skipped++;
			}
			if (mapped) mappedIds.push(mapped.stored.id);
		}

		expect(mappedIds).toEqual(['chesscom-good-1', 'chesscom-good-2']);
		expect(skipped).toBe(1);
	});
});

// The per-game skip the offline analyzer depends on (#177 review follow-up).
//
// These call the SAME function scripts/analyze-chesscom.mts calls. The
// previous version of this file mirrored the script's loop shape instead,
// because the script spawns engines at module load and cannot be imported —
// which meant deleting the script's try/catch left the whole suite green.
describe('mapOneGame — the offline analyzer\'s per-game step', () => {
	const good = SCHOLARS_MATE;

	it('maps a good game', async () => {
		const r = await mapOneGame(good, flatEval, 'ryan');
		expect(r.ok).toBe(true);
		if (r.ok) expect(r.mapped?.stored.id).toBeTruthy();
	});

	// The guard and the backstop are DIFFERENT mechanisms and these pin the
	// difference. Drift the guard anticipates comes back as an ordinary
	// refusal — ok, nothing mapped — and the caller just moves on without
	// counting a skip or holding the month open. Only a throw the guard did
	// not see becomes ok:false.
	it('a drifted record is an ordinary refusal, not an error', async () => {
		// A NUMBER where a username belongs: truthy, so the old truthiness
		// guard passed it and .toLowerCase() threw one call later.
		const drifted = { ...good, white: { ...good.white, username: 12345 as never } };
		const r = await mapOneGame(drifted, flatEval, 'ryan');
		expect(r.ok).toBe(true);
		if (r.ok) expect(r.mapped).toBeNull();
	});

	it('a missing end_time is refused rather than becoming a NaN date', async () => {
		const { end_time: _drop, ...rest } = good;
		const r = await mapOneGame(rest as never, flatEval, 'ryan');
		expect(r.ok).toBe(true);
		if (r.ok) expect(r.mapped).toBeNull();
	});

	it('surfaces an evaluator throw as a skip, so one game cannot abort a month',
		async () => {
			const boom = async () => {
				throw new Error('engine died');
			};
			const r = await mapOneGame(good, boom, 'ryan');
			expect(r.ok).toBe(false);
			if (!r.ok) expect(r.reason).toContain('engine died');
		});
});
