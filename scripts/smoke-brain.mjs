// Post-build smoke test for flutter/assets/brain.js: evaluate the IIFE in a
// bare context (no require/window/DOM — approximating the embedded JS engine
// in the Flutter app) and exercise one call from each export family. Catches
// bundling regressions in seconds; the on-simulator parity suite (M4) covers
// the Dart marshalling layer.
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('../flutter/assets/brain.js', import.meta.url), 'utf8');
const g = {};
new Function('globalThis', `${src}; globalThis.brain = brain;`)(g);
const brain = g.brain;

const fail = (msg) => {
	console.error(`brain smoke FAILED: ${msg}`);
	process.exit(1);
};

if (typeof brain.BRAIN_VERSION !== 'number') fail('BRAIN_VERSION missing');

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const lines = [
	{ pv: ['d2d4'], score: 0.4, mate: null, depth: 12, multipv: 1 },
	{ pv: ['e2e4'], score: 0.35, mate: null, depth: 12, multipv: 2 },
	{ pv: ['g1f3'], score: 0.3, mate: null, depth: 12, multipv: 3 },
	{ pv: ['c2c4'], score: 0.25, mate: null, depth: 12, multipv: 4 },
	{ pv: ['b1c3'], score: 0.2, mate: null, depth: 12, multipv: 5 }
];

// bot family
const move = brain.shapedBotMove(lines, 600, { scan: true }, 'smoke', START);
if (typeof move !== 'string') fail(`shapedBotMove returned ${move}`);
if (typeof brain.shapedSearchDepth(600) !== 'number') fail('shapedSearchDepth');
if (brain.avoidRepetition('d2d4', [START], lines) !== 'd2d4') fail('avoidRepetition');

// horizon — the one export carrying a third-party library into the bundle,
// so whether it survives bare-context evaluation is the whole question. NOT
// deterministic: js-chess-engine picks among equal-scoring moves at random,
// so assert a legal-looking UCI move, never a particular one.
const horizon = brain.horizonMove(START, 1);
if (typeof horizon !== 'string' || !/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(horizon))
	fail(`horizonMove returned ${horizon}`);

// roster
const personas = brain.availablePersonas(false);
if (!Array.isArray(personas) || personas.length < 20) fail(`roster size ${personas?.length}`);
if (!brain.personaById('square-900')) fail('personaById(square-900)');

// grading
const grade = brain.gradeMove(1, START, 'e4', 'e2e4', 'w', lines);
if (grade.pctBest == null || grade.bestUci !== 'd2d4') fail('gradeMove shape');
const child = [{ pv: ['e7e5'], score: -0.3, mate: null, depth: 14, multipv: 1 }];
const backfilled = brain.backfillGrade(grade, child);
if (!backfilled.backfilled || !backfilled.label) fail('backfillGrade shape');
if (typeof brain.winChance(0.5, null) !== 'number') fail('winChance');
if (!brain.CLASS.blunder?.color) fail('CLASS table');
// Dart reads this by string through the bridge, so a dropped export is silent
// everywhere else: tsc passes, vitest passes, the bundle rebuilds and CI's
// brain.js diff passes — and Review dies on open with a null cast. Proved by
// deleting the export and watching the whole green path stay green.
if (!Array.isArray(brain.LABEL_ORDER) || brain.LABEL_ORDER.length === 0) {
  fail('LABEL_ORDER export');
}

// unified move table — Dart calls both of these by name from
// flutter/lib/brain/explorer_api.dart, so a dropped export is invisible until
// the Book pane throws on a device
const conf = brain.confidences(lines);
if (conf.length !== lines.length || Math.abs(conf.reduce((a, b) => a + b, 0) - 100) > 1e-6)
	fail(`confidences ${JSON.stringify(conf)}`);
const unified = brain.unifyMoves(
	START,
	lines,
	{ total: 300, moves: [{ uci: 'e2e4', san: 'e4', white: 100, draws: 50, black: 50 }] },
	null
);
// the book move outranks every engine-only line, whatever the engine thinks
if (unified[0]?.san !== 'e4' || unified[0]?.lichess?.games !== 200)
	fail(`unifyMoves ${JSON.stringify(unified[0])}`);
if (unified.length !== lines.length) fail(`unifyMoves rows ${unified.length}`);

// SAN helpers
if (brain.getSan(START, 'g1f3') !== 'Nf3') fail('getSan');
if (!brain.getFenAfter(START, 'e2e4')?.includes(' b ')) fail('getFenAfter');

// practice (pure scheduling)
if (brain.dueCount([], 0) !== 0) fail('dueCount');
if (brain.nextItem([], true, 0, () => 0.5) !== null) fail('nextItem empty');

// lichess import — the mapper only, called by name from
// flutter/lib/brain/lichess_import_api.dart. Dart does the HTTP, so this is
// the whole brain surface the import stands on; drop the export and the
// import dialog throws on a device while everything else stays green.
//
// Two plies of a real (trimmed) response shape: White plays a losing queen
// move, and the importing player is White, so the mapper must both grade it
// and mine it as a practice candidate.
const imported = brain.lichessGameToStored(
	{
		id: 'smokeGam',
		variant: 'standard',
		speed: 'blitz',
		status: 'resign',
		winner: 'black',
		lastMoveAt: 1775677126911,
		players: { white: { user: { name: 'Smoke' } }, black: { user: { name: 'Test' } } },
		moves: 'e4 e5 Qh5 Nc6 Qxf7+',
		pgn: '1. e4 e5 2. Qh5 Nc6 3. Qxf7+ 0-1',
		analysis: [
			{ eval: 30 },
			{ eval: 25 },
			{ eval: 20 },
			{ eval: 15 },
			{ eval: -900, best: 'd2d4', variation: 'd4 Nf6' }
		]
	},
	'Smoke'
);
if (imported?.humanColor !== 'w') fail(`lichessGameToStored humanColor ${imported?.humanColor}`);
if (imported.stored.id !== 'lichess-smokeGam' || imported.stored.source !== 'lichess')
	fail(`lichessGameToStored stored ${JSON.stringify(imported.stored.id)}`);
if (imported.stored.moves.length !== 5) fail(`lichessGameToStored moves ${imported.stored.moves.length}`);
// the drop is the whole point: no candidates means an import seeds nothing
if (!imported.practice.some((p) => p.drop > 20)) fail('lichessGameToStored practice candidates');
if (typeof brain.analysedGameToStored !== 'function') fail('analysedGameToStored export');

// stored-game math
if (brain.moveAccuracy(0) < 99) fail('moveAccuracy(0)');
if (brain.gameAccuracy([], 'w') !== null) fail('gameAccuracy empty');

console.log(
	`brain smoke OK — v${brain.BRAIN_VERSION}, ${personas.length} web personas, sample move ${move}`
);
