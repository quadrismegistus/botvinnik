#!/usr/bin/env node
// Minimal UCI shim around js-chess-engine (a JS library, not a UCI process),
// so it can enter the calibration gym and, eventually, lichess-bot.
//
// UCI subset: uci / isready / ucinewgame / setoption name Level value N /
// position (fen|startpos) [moves ...] / go ... (all go params ignored — the
// Level determines effort) / quit.
//
// js-chess-engine v2: ai(fen, {level: 1..5}) -> { move: {"E2":"E4"}, ... }.
// Level 1 has no quiescence to speak of and genuinely hangs pieces (horizon
// effect) — the interesting property for the weak-bot range.

import { createInterface } from 'node:readline';
import { ai } from 'js-chess-engine';
import { Chess } from 'chess.js';

let level = 3;
let randomness = 0;
const chess = new Chess();

function send(line) {
	process.stdout.write(line + '\n');
}

function setPosition(args) {
	// "position fen <FEN> [moves ...]" | "position startpos [moves ...]"
	const movesIdx = args.indexOf('moves');
	const movesList = movesIdx >= 0 ? args.slice(movesIdx + 1) : [];
	if (args[0] === 'startpos') {
		chess.reset();
	} else if (args[0] === 'fen') {
		const fen = (movesIdx >= 0 ? args.slice(1, movesIdx) : args.slice(1)).join(' ');
		chess.load(fen);
	}
	for (const uci of movesList) {
		chess.move({ from: uci.slice(0, 2), to: uci.slice(2, 4), promotion: uci[4] });
	}
}

function bestmove() {
	const fen = chess.fen();
	const opts = { level };
	if (randomness > 0) opts.randomness = randomness;
	const result = ai(fen, opts);
	const [from, to] = Object.entries(result.move)[0];
	// js-chess-engine always promotes to queen; UCI needs the suffix spelled out
	const legal = chess
		.moves({ verbose: true })
		.find((m) => m.from === from.toLowerCase() && m.to === to.toLowerCase());
	const promo = legal?.promotion ? 'q' : '';
	return `${from.toLowerCase()}${to.toLowerCase()}${promo}`;
}

const rl = createInterface({ input: process.stdin });
rl.on('line', (line) => {
	const parts = line.trim().split(/\s+/);
	const cmd = parts[0];
	try {
		if (cmd === 'uci') {
			send('id name js-chess-engine (UCI shim)');
			send('id author josefjadrny; shim: botvinnik-web');
			send('option name Level type spin default 3 min 1 max 5');
			send('option name Randomness type spin default 0 min 0 max 100');
			send('uciok');
		} else if (cmd === 'isready') {
			send('readyok');
		} else if (cmd === 'setoption') {
			// "setoption name X value Y"
			const name = parts[parts.indexOf('name') + 1]?.toLowerCase();
			const value = Number(parts[parts.indexOf('value') + 1]);
			if (name === 'level' && value >= 1 && value <= 5) level = value;
			if (name === 'randomness' && value >= 0 && value <= 100) randomness = value;
		} else if (cmd === 'ucinewgame') {
			chess.reset();
		} else if (cmd === 'position') {
			setPosition(parts.slice(1));
		} else if (cmd === 'go') {
			send(`bestmove ${bestmove()}`);
		} else if (cmd === 'quit') {
			process.exit(0);
		}
		// silently ignore anything else (stop, ponderhit, debug, ...)
	} catch (e) {
		// a shim crash must not hang the harness: emit a null move so the
		// watchdog-side treats it as an adjudication point
		send(`info string shim error: ${e.message}`);
		send('bestmove 0000');
	}
});
